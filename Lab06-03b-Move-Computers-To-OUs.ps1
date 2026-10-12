# ==========================================================
# LAB 6 - Script 03b - Move Computers to Organizational Units
#
# Run ONLY on host as Administrator.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
#
# Target computers:
#   SEA-SRV1 -> OU=Serwery
#   SEA-SRV2 -> OU=Serwery
#   SEA-CL1  -> OU=Stacje robocze
#
# Prerequisites:
#   LAB 5 - Organizational units created
#   LAB 6 - Computers joined to the domain
#   Required member computer restarts completed
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$VMName = 'SEA-DC1'
$DomainName = 'contoso.com'
$ReportDir = 'C:\LabReports'

$Targets = @(
    [PSCustomObject]@{
        Computer = 'SEA-SRV1'
        OU = 'Serwery'
    }

    [PSCustomObject]@{
        Computer = 'SEA-SRV2'
        OU = 'Serwery'
    }

    [PSCustomObject]@{
        Computer = 'SEA-CL1'
        OU = 'Stacje robocze'
    }
)

# ----------------------------------------------------------
# 2. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path `
    $ReportDir `
    "LAB06-Computer-OUs_$Timestamp.csv"

# ----------------------------------------------------------
# 3. Verify domain controller VM
# ----------------------------------------------------------

$VM = Get-VM `
    -Name $VMName `
    -ErrorAction Stop

if ([string]$VM.State -ne 'Running') {
    throw "Virtual machine $VMName is not running."
}

# ----------------------------------------------------------
# 4. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - MOVE COMPUTERS TO OUs"
Write-Host "=========================================="
Write-Host ""
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $VMName"
Write-Host "Computers: $($Targets.Count)"
Write-Host ""

# ----------------------------------------------------------
# 5. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {
    throw 'Domain credentials were not provided.'
}

$Session = $null

try {

    # ------------------------------------------------------
    # 6. Connect to domain controller using PowerShell Direct
    # ------------------------------------------------------

    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 7. Process computer objects inside Active Directory
    # ------------------------------------------------------

    $Results = Invoke-Command `
        -Session $Session `
        -ArgumentList (,$Targets) `
        -ScriptBlock {

            param(
                [object[]]$Targets
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            # ----------------------------------------------
            # 8. Verify Active Directory domain
            # ----------------------------------------------

            $Domain = Get-ADDomain `
                -ErrorAction Stop

            if ($Domain.DNSRoot -ne 'contoso.com') {
                throw "Unexpected domain: $($Domain.DNSRoot)"
            }

            $DomainDN = $Domain.DistinguishedName

            # ----------------------------------------------
            # 9. Process each target computer
            # ----------------------------------------------

            foreach ($Target in $Targets) {

                $ComputerName = [string]$Target.Computer
                $OUName = [string]$Target.OU

                $TargetOU = "OU=$OUName,OU=Centrala,$DomainDN"

                try {

                    # --------------------------------------
                    # 10. Verify destination OU
                    # --------------------------------------

                    $Destination = Get-ADOrganizationalUnit `
                        -Identity $TargetOU `
                        -ErrorAction Stop

                    if ($null -eq $Destination) {
                        throw "Destination OU does not exist."
                    }

                    # --------------------------------------
                    # 11. Find computer account
                    # --------------------------------------

                    $Computer = Get-ADComputer `
                        -Identity $ComputerName `
                        -Properties DistinguishedName `
                        -ErrorAction Stop

                    $CurrentDN = [string](
                        $Computer.DistinguishedName
                    )

                    # --------------------------------------
                    # 12. Verify whether move is necessary
                    # --------------------------------------

                    $ExpectedSuffix = ",$TargetOU"

                    if (
                        $CurrentDN.EndsWith(
                            $ExpectedSuffix,
                            [System.StringComparison]::OrdinalIgnoreCase
                        )
                    ) {

                        $Action = 'ALREADY_IN_OU'
                        $Status = 'PASS'
                    }
                    else {

                        # ----------------------------------
                        # 13. Move computer into target OU
                        # ----------------------------------

                        Move-ADObject `
                            -Identity $Computer.DistinguishedName `
                            -TargetPath $TargetOU `
                            -ErrorAction Stop

                        # ----------------------------------
                        # 14. Verify new location
                        # ----------------------------------

                        $MovedComputer = Get-ADComputer `
                            -Identity $ComputerName `
                            -Properties DistinguishedName `
                            -ErrorAction Stop

                        $NewDN = [string](
                            $MovedComputer.DistinguishedName
                        )

                        if (
                            -not $NewDN.EndsWith(
                                $ExpectedSuffix,
                                [System.StringComparison]::OrdinalIgnoreCase
                            )
                        ) {
                            throw "Computer move verification failed."
                        }

                        $Action = 'MOVED'
                        $Status = 'PASS'
                    }

                    # --------------------------------------
                    # 15. Return successful result
                    # --------------------------------------

                    [PSCustomObject]@{
                        Computer = $ComputerName
                        TargetOU = $TargetOU
                        Action = $Action
                        Status = $Status
                        Error = ''
                    }

                }
                catch {

                    # --------------------------------------
                    # 16. Record error and continue
                    # --------------------------------------

                    [PSCustomObject]@{
                        Computer = $ComputerName
                        TargetOU = $TargetOU
                        Action = 'ERROR'
                        Status = 'FAIL'
                        Error = $_.Exception.Message
                    }
                }
            }

        } `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 17. Display results
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 6 - COMPUTER OU REPORT"
    Write-Host "=========================================="
    Write-Host ""

    $Results |
        Format-Table `
            Computer,
            Action,
            Status,
            TargetOU `
            -AutoSize |
        Out-Host

    # ------------------------------------------------------
    # 18. Export CSV report
    # ------------------------------------------------------

    $Results |
        Select-Object `
            Computer,
            TargetOU,
            Action,
            Status,
            Error |
        Export-Csv `
            -Path $CSV `
            -NoTypeInformation `
            -Encoding UTF8

    # ------------------------------------------------------
    # 19. Calculate statistics
    # ------------------------------------------------------

    $Moved = @(
        $Results |
        Where-Object {
            $_.Action -eq 'MOVED'
        }
    ).Count

    $AlreadyCorrect = @(
        $Results |
        Where-Object {
            $_.Action -eq 'ALREADY_IN_OU'
        }
    ).Count

    $Failed = @(
        $Results |
        Where-Object {
            $_.Status -eq 'FAIL'
        }
    ).Count

    Write-Host ""
    Write-Host "Moved: $Moved" -ForegroundColor Green
    Write-Host "Already correct: $AlreadyCorrect" `
        -ForegroundColor Cyan
    Write-Host "Failed: $Failed" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "CSV report: $CSV"

    # ------------------------------------------------------
    # 20. Final validation
    # ------------------------------------------------------

    if (
        $Failed -eq 0 -and
        ($Moved + $AlreadyCorrect) -eq $Targets.Count
    ) {

        Write-Host ""
        Write-Host "=========================================="
        Write-Host "LAB 6 - COMPUTER OU CONFIGURATION PASSED"
        Write-Host "==========================================" `
            -ForegroundColor Green

    }
    else {

        Write-Warning (
            "Some computer accounts were not moved " +
            "successfully. Review the CSV report."
        )
    }

}
finally {

    # ------------------------------------------------------
    # 21. Close PowerShell Direct session
    # ------------------------------------------------------

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

