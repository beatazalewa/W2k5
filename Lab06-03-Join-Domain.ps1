# ==========================================================
# LAB 6 - Script 03 - Join Computers to Active Directory
#
# Run on host in elevated Windows PowerShell 5.1.
#
# Target virtual machines:
#   SEA-SRV1 - 10.10.10.20 - Windows Server 2025
#   SEA-SRV2 - 10.10.10.30 - Windows Server 2025
#   SEA-CL1  - 10.10.10.100 - Windows 11
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# DNS server: 10.10.10.10
#
# Prerequisite:
#   LAB06-02-Prepare-Members.ps1 completed successfully.
#
# Computers are not restarted automatically.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 2. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$DNSServer = '10.10.10.10'

$ReportDir = 'C:\LabReports'

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

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path `
    $ReportDir `
    "LAB06-DomainJoin_$Stamp.csv"

$AllResults = @()

# ----------------------------------------------------------
# 3. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - JOIN COMPUTERS TO DOMAIN"
Write-Host "=========================================="
Write-Host ""
Write-Host "Domain: $DomainName"
Write-Host "DNS: $DNSServer"
Write-Host "Target computers: $($Targets.Count)"
Write-Host ""

# ----------------------------------------------------------
# 4. Request domain administrator credentials
# ----------------------------------------------------------

$DomainCredential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password for joining computers'

if ($null -eq $DomainCredential) {
    throw 'Domain credentials were not provided.'
}

# ----------------------------------------------------------
# 5. Process each virtual machine
# ----------------------------------------------------------

foreach ($Target in $Targets) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Processing: $($Target.VM)"
    Write-Host "------------------------------------------"

    $Session = $null

    try {

        # --------------------------------------------------
        # 6. Verify Hyper-V virtual machine
        # --------------------------------------------------

        $VM = Get-VM `
            -Name $Target.VM `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "VM $($Target.VM) is not running."
        }

        # --------------------------------------------------
        # 7. Request local administrator credentials
        # --------------------------------------------------

        $LocalCredential = Get-Credential `
            -UserName $Target.User `
            -Message "Enter local administrator password for $($Target.VM)"

        if ($null -eq $LocalCredential) {
            throw "Local credentials were not provided for $($Target.VM)."
        }

        # --------------------------------------------------
        # 8. Connect through PowerShell Direct
        # --------------------------------------------------

        $Session = New-PSSession `
            -VMName $Target.VM `
            -Credential $LocalCredential `
            -ErrorAction Stop

        # --------------------------------------------------
        # 9. Verify prerequisites and join domain
        # --------------------------------------------------

        $Result = Invoke-Command `
            -Session $Session `
            -ArgumentList `
                $Target.Name, `
                $Target.IP, `
                $DomainName, `
                $DNSServer, `
                $DomainCredential `
            -ScriptBlock {

                param(
                    [string]$ExpectedName,
                    [string]$ExpectedIP,
                    [string]$ExpectedDomain,
                    [string]$ExpectedDNS,
                    [PSCredential]$JoinCredential
                )

                $ErrorActionPreference = 'Stop'

                # ------------------------------------------
                # 10. Verify computer name
                # ------------------------------------------

                $CurrentName = $env:COMPUTERNAME

                if ($CurrentName -ne $ExpectedName) {

                    throw (
                        "Unexpected computer name: $CurrentName. " +
                        "Expected: $ExpectedName. " +
                        "Complete Script 02 and restart the VM."
                    )
                }

                # ------------------------------------------
                # 11. Verify IPv4 address
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
                        "Expected IPv4 address $ExpectedIP " +
                        "was not found on exactly one interface."
                    )
                }

                $InterfaceIndex = $IPAddresses[0].InterfaceIndex

                # ------------------------------------------
                # 12. Verify DNS client configuration
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
                    $DNSServers[0] -eq $ExpectedDNS
                )

                if (-not $DNSCorrect) {

                    throw (
                        "Incorrect DNS configuration on $CurrentName. " +
                        "Expected DNS server: $ExpectedDNS. " +
                        "Run Script 02 before joining the domain."
                    )
                }

                # ------------------------------------------
                # 13. Check current domain membership
                # ------------------------------------------

                $ComputerSystem = Get-CimInstance `
                    -ClassName Win32_ComputerSystem `
                    -ErrorAction Stop

                if ($ComputerSystem.PartOfDomain) {

                    if ($ComputerSystem.Domain -ieq $ExpectedDomain) {

                        return [PSCustomObject]@{
                            VM     = $ExpectedName
                            IPv4   = $ExpectedIP
                            Domain = $ComputerSystem.Domain
                            Result = 'ALREADY_JOINED'
                            Detail = 'Computer is already a domain member'
                        }
                    }

                    throw (
                        "Computer is already joined to another domain: " +
                        $ComputerSystem.Domain
                    )
                }

                # ------------------------------------------
                # 14. Verify domain controller DNS record
                # ------------------------------------------

                $DNSAnswers = @(
                    Resolve-DnsName `
                        -Name 'SEA-DC1.contoso.com' `
                        -Type A `
                        -Server $ExpectedDNS `
                        -ErrorAction Stop |
                    Where-Object {
                        $_.IPAddress -eq $ExpectedDNS
                    }
                )

                if ($DNSAnswers.Count -eq 0) {

                    throw (
                        "Domain controller SEA-DC1.contoso.com " +
                        "cannot be resolved through DNS."
                    )
                }

                # ------------------------------------------
                # 15. Verify domain controller connectivity
                # ------------------------------------------

                $LDAPAvailable = Test-NetConnection `
                    -ComputerName $ExpectedDNS `
                    -Port 389 `
                    -InformationLevel Quiet `
                    -WarningAction SilentlyContinue

                if (-not $LDAPAvailable) {

                    throw (
                        "LDAP TCP port 389 is not reachable " +
                        "on domain controller $ExpectedDNS."
                    )
                }

                # ------------------------------------------
                # 16. Join computer to Active Directory
                # ------------------------------------------

                Add-Computer `
                    -DomainName $ExpectedDomain `
                    -Credential $JoinCredential `
                    -ErrorAction Stop

                # ------------------------------------------
                # 17. Return result without restarting
                # ------------------------------------------

                [PSCustomObject]@{
                    VM     = $ExpectedName
                    IPv4   = $ExpectedIP
                    Domain = $ExpectedDomain
                    Result = 'JOINED_RESTART_REQUIRED'
                    Detail = 'Domain join successful; restart required'
                }

            } `
            -ErrorAction Stop

        # --------------------------------------------------
        # 18. Collect successful result
        # --------------------------------------------------

        $AllResults += $Result

        if ($Result.Result -eq 'JOINED_RESTART_REQUIRED') {

            Write-Host ""
            Write-Warning (
                "$($Target.VM) joined the domain. " +
                "Restart is required."
            )
        }
        elseif ($Result.Result -eq 'ALREADY_JOINED') {

            Write-Host (
                "$($Target.VM) is already joined to $DomainName."
            ) -ForegroundColor Green
        }

    }
    catch {

        # --------------------------------------------------
        # 19. Record failure without stopping other targets
        # --------------------------------------------------

        $Message = $_.Exception.Message

        Write-Warning (
            "Domain join failed for $($Target.VM): $Message"
        )

        $AllResults += [PSCustomObject]@{
            VM     = $Target.VM
            IPv4   = $Target.IP
            Domain = $DomainName
            Result = 'FAILED'
            Detail = $Message
        }

    }
    finally {

        # --------------------------------------------------
        # 20. Close PowerShell Direct session
        # --------------------------------------------------

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 21. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - DOMAIN JOIN REPORT"
Write-Host "=========================================="
Write-Host ""

$AllResults |
    Format-Table `
        VM,
        IPv4,
        Domain,
        Result,
        Detail `
        -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 22. Export results
# ----------------------------------------------------------

$AllResults |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

Write-Host ""
Write-Host "CSV report: $CSV"

# ----------------------------------------------------------
# 23. Calculate statistics
# ----------------------------------------------------------

$Joined = @(
    $AllResults |
    Where-Object {
        $_.Result -eq 'JOINED_RESTART_REQUIRED'
    }
).Count

$AlreadyJoined = @(
    $AllResults |
    Where-Object {
        $_.Result -eq 'ALREADY_JOINED'
    }
).Count

$Failed = @(
    $AllResults |
    Where-Object {
        $_.Result -eq 'FAILED'
    }
).Count

Write-Host ""
Write-Host "Joined: $Joined" -ForegroundColor Green
Write-Host "Already joined: $AlreadyJoined" -ForegroundColor Cyan
Write-Host "Failed: $Failed" -ForegroundColor Yellow

# ----------------------------------------------------------
# 24. Final status
# ----------------------------------------------------------

if (
    $Failed -eq 0 -and
    ($Joined + $AlreadyJoined) -eq $Targets.Count
) {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 6 - DOMAIN JOIN COMPLETED"
    Write-Host "==========================================" `
        -ForegroundColor Green

    if ($Joined -gt 0) {

        Write-Host ""
        Write-Host "Restart the newly joined virtual machines."
        Write-Host ""

        Write-Host "Run on PREDATOR-PC:" `
            -ForegroundColor Cyan

        Write-Host (
            "Restart-VM -Name 'SEA-SRV1','SEA-SRV2','SEA-CL1'"
        )
    }

}
else {

    Write-Warning (
        "Some computers were not joined successfully. " +
        "Review the report before continuing."
    )
}
