# ==========================================================
# LAB 6 - Script 02 - Prepare Domain Member Computers
#
# Run on host in elevated Windows PowerShell 5.1.
#
# Target virtual machines:
#   SEA-SRV1 - 10.10.10.20 - Windows Server 2025
#   SEA-SRV2 - 10.10.10.30 - Windows Server 2025
#   SEA-CL1  - 10.10.10.100 - Windows 11
#
# Domain: contoso.com
# DNS server: 10.10.10.10
#
# A computer rename requires a restart.
# Rerun this script after any required restart.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 2. Define target virtual machines
# ----------------------------------------------------------

$Targets = @(

    [PSCustomObject]@{
        VM   = 'SEA-SRV1'
        Name = 'SEA-SRV1'
        IP   = '10.10.10.20'
        User = '.\Administrator'
    }

    [PSCustomObject]@{
        VM   = 'SEA-SRV2'
        Name = 'SEA-SRV2'
        IP   = '10.10.10.30'
        User = '.\Administrator'
    }

    [PSCustomObject]@{
        VM   = 'SEA-CL1'
        Name = 'SEA-CL1'
        IP   = '10.10.10.100'
        User = '.\Admin'
    }
)

$AllResults = @()

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - PREPARE DOMAIN MEMBER COMPUTERS"
Write-Host "=========================================="
Write-Host ""

# ----------------------------------------------------------
# 3. Process each virtual machine
# ----------------------------------------------------------

foreach ($Target in $Targets) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Preparing: $($Target.VM)"
    Write-Host "------------------------------------------"

    # ------------------------------------------------------
    # 4. Verify virtual machine state
    # ------------------------------------------------------

    $VM = Get-VM `
        -Name $Target.VM `
        -ErrorAction Stop

    if ($VM.State -ne 'Running') {
        throw "Virtual machine $($Target.VM) is not running."
    }

    # ------------------------------------------------------
    # 5. Request local administrator credentials
    # ------------------------------------------------------

    $Credential = Get-Credential `
        -UserName $Target.User `
        -Message "Enter local administrator password for $($Target.VM)"

    $Session = $null

    try {

        # --------------------------------------------------
        # 6. Connect using PowerShell Direct
        # --------------------------------------------------

        $Session = New-PSSession `
            -VMName $Target.VM `
            -Credential $Credential `
            -ErrorAction Stop

        # --------------------------------------------------
        # 7. Verify network settings inside the guest
        # --------------------------------------------------

        $Result = Invoke-Command `
            -Session $Session `
            -ArgumentList $Target.Name, $Target.IP `
            -ScriptBlock {

                param(
                    [string]$ExpectedName,
                    [string]$ExpectedIP
                )

                $ErrorActionPreference = 'Stop'

                # ------------------------------------------
                # 8. Find the expected IPv4 interface
                # ------------------------------------------

                $IPAddresses = @(
                    Get-NetIPAddress `
                        -AddressFamily IPv4 `
                        -ErrorAction Stop |
                    Where-Object {
                        $_.IPAddress -eq $ExpectedIP
                    }
                )

                if ($IPAddresses.Count -ne 1) {

                    throw (
                        "Expected exactly one interface " +
                        "with IPv4 address $ExpectedIP."
                    )
                }

                $InterfaceIndex = $IPAddresses[0].InterfaceIndex

                # ------------------------------------------
                # 9. Verify and configure DNS client
                # ------------------------------------------

                $DNSServers = @(
                    (
                        Get-DnsClientServerAddress `
                            -InterfaceIndex $InterfaceIndex `
                            -AddressFamily IPv4 `
                            -ErrorAction Stop
                    ).ServerAddresses
                )

                $DNSCorrect = (
                    $DNSServers.Count -eq 1 -and
                    $DNSServers[0] -eq '10.10.10.10'
                )

                if (-not $DNSCorrect) {

                    Write-Host "Configuring DNS server: 10.10.10.10"

                    Set-DnsClientServerAddress `
                        -InterfaceIndex $InterfaceIndex `
                        -ServerAddresses '10.10.10.10' `
                        -ErrorAction Stop

                    Clear-DnsClientCache
                }

                # ------------------------------------------
                # 10. Check current domain membership
                # ------------------------------------------

                $ComputerSystem = Get-CimInstance `
                    -ClassName Win32_ComputerSystem `
                    -ErrorAction Stop

                $DomainMember = [bool]$ComputerSystem.PartOfDomain

                # ------------------------------------------
                # 11. Verify computer name
                # ------------------------------------------

                if ($env:COMPUTERNAME -ne $ExpectedName) {

                    if ($DomainMember) {

                        throw (
                            "Computer is already domain joined " +
                            "under another name. A planned " +
                            "domain rename is required."
                        )
                    }

                    # Rename computer without automatic reboot
                    Rename-Computer `
                        -NewName $ExpectedName `
                        -Force `
                        -ErrorAction Stop

                    [PSCustomObject]@{
                        VM     = $ExpectedName
                        IPv4   = $ExpectedIP
                        DNS    = '10.10.10.10'
                        Result = 'RESTART_REQUIRED'
                        Detail = 'Computer renamed; restart required'
                    }

                }
                else {

                    # --------------------------------------
                    # 12. Verify domain controller DNS record
                    # --------------------------------------

                    $DNSAnswers = @(
                        Resolve-DnsName `
                            -Name 'SEA-DC1.contoso.com' `
                            -Type A `
                            -Server '10.10.10.10' `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.IPAddress -eq '10.10.10.10'
                        }
                    )

                    if ($DNSAnswers.Count -eq 0) {

                        throw (
                            "Domain controller DNS A record " +
                            "cannot be resolved."
                        )
                    }

                    # --------------------------------------
                    # 13. Return verification result
                    # --------------------------------------

                    [PSCustomObject]@{
                        VM     = $ExpectedName
                        IPv4   = $ExpectedIP
                        DNS    = '10.10.10.10'
                        Result = 'PASS'
                        Detail = 'Network settings and name verified'
                    }
                }

            } `
            -ErrorAction Stop

        # --------------------------------------------------
        # 14. Collect results
        # --------------------------------------------------

        $AllResults += $Result

        if ($Result.Result -eq 'RESTART_REQUIRED') {

            Write-Warning (
                "$($Target.VM) requires a restart. " +
                "Restart the VM and rerun Script 02."
            )
        }

    }
    finally {

        # --------------------------------------------------
        # 15. Close PowerShell Direct session
        # --------------------------------------------------

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 16. Display preparation results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - MEMBER PREPARATION REPORT"
Write-Host "=========================================="
Write-Host ""

$AllResults |
    Format-Table `
        VM,
        IPv4,
        DNS,
        Result,
        Detail `
        -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 17. Verify final preparation status
# ----------------------------------------------------------

$Incomplete = @(
    $AllResults |
    Where-Object {
        $_.Result -ne 'PASS'
    }
).Count

if ($Incomplete -gt 0) {

    throw (
        "Some computers require a restart. " +
        "Complete the restarts and rerun Script 02 " +
        "before joining the domain."
    )
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - MEMBER PREPARATION PASSED"
Write-Host "==========================================" `
    -ForegroundColor Green

