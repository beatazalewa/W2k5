# ==========================================================
# LAB 8 - Script 01 - Group Policy PreCheck
#
# Run on host as Administrator.
# Windows PowerShell 5.1 and Hyper-V required.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
#
# Checks:
#   Hyper-V virtual machines
#   Domain controller connectivity
#   Active Directory and GroupPolicy modules
#   SYSVOL and NETLOGON shares
#   Required organizational units
#   Current domain password and lockout policy
#   Existing Group Policy Objects
#
# Read-only script.
# ==========================================================

$ErrorActionPreference = 'Stop'

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'
$ReportDir = 'C:\LabReports'

$VMNames = @(
    'SEA-DC1'
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

New-Item -ItemType Directory `
    -Path $ReportDir -Force | Out-Null

$CSV = Join-Path $ReportDir `
    "LAB08-PreCheck_$Timestamp.csv"

$TXT = Join-Path $ReportDir `
    "LAB08-PreCheck_$Timestamp.txt"

$Results = [System.Collections.Generic.List[object]]::new()
$Details = [System.Collections.Generic.List[string]]::new()

function Add-Check {

    param(
        [string]$Machine,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [bool]$Passed
    )

    $Results.Add(
        [PSCustomObject]@{
            Machine = $Machine
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = if ($Passed) {
                'PASS'
            }
            else {
                'FAIL'
            }
        }
    )
}

# ----------------------------------------------------------
# 2. Verify virtual machines
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - GROUP POLICY PRECHECK"
Write-Host "=========================================="

foreach ($VMName in $VMNames) {

    $VM = Get-VM `
        -Name $VMName `
        -ErrorAction SilentlyContinue

    $Exists = $null -ne $VM

    Add-Check `
        $VMName 'VM exists' `
        'True' ([string]$Exists) $Exists

    $Running = (
        $Exists -and
        [string]$VM.State -eq 'Running'
    )

    Add-Check `
        $VMName 'VM running' `
        'True' ([string]$Running) $Running
}

# ----------------------------------------------------------
# 3. Request credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator credentials'

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 4. Connect to domain controller
# ----------------------------------------------------------

$Session = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    $Data = Invoke-Command `
        -Session $Session `
        -ScriptBlock {

            $ErrorActionPreference = 'Stop'

            # ----------------------------------------------
            # 5. Load management modules
            # ----------------------------------------------

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            Import-Module GroupPolicy `
                -ErrorAction Stop

            $ADModuleOK = [bool](
                Get-Module ActiveDirectory
            )

            $GPOModuleOK = [bool](
                Get-Module GroupPolicy
            )

            # ----------------------------------------------
            # 6. Read domain information
            # ----------------------------------------------

            $Domain = Get-ADDomain `
                -ErrorAction Stop

            $DomainDN = $Domain.DistinguishedName

            # ----------------------------------------------
            # 7. Verify SYSVOL and NETLOGON
            # ----------------------------------------------

            $SYSVOL = Get-SmbShare `
                -Name SYSVOL `
                -ErrorAction SilentlyContinue

            $NETLOGON = Get-SmbShare `
                -Name NETLOGON `
                -ErrorAction SilentlyContinue

            $SYSVOLOK = $null -ne $SYSVOL
            $NETLOGONOK = $null -ne $NETLOGON

            # ----------------------------------------------
            # 8. Verify required organizational units
            # ----------------------------------------------

            $RequiredOUs = @(
                "OU=Centrala,$DomainDN"
                "OU=IT,OU=Centrala,$DomainDN"
                "OU=Finanse,OU=Centrala,$DomainDN"
                "OU=Uzytkownicy,OU=Finanse,OU=Centrala,$DomainDN"
                "OU=Serwery,OU=Centrala,$DomainDN"
                "OU=Stacje robocze,OU=Centrala,$DomainDN"
            )

            $OUResults = foreach ($OUPath in $RequiredOUs) {

                # Search by distinguished name instead
                # of using Get-ADOrganizationalUnit
                # -Identity for possibly missing objects.

                $Found = @(
                    Get-ADOrganizationalUnit `
                        -LDAPFilter '(objectClass=organizationalUnit)' `
                        -SearchBase $DomainDN `
                        -SearchScope Subtree `
                        -ErrorAction Stop |
                    Where-Object {
                        $_.DistinguishedName -ieq $OUPath
                    }
                ).Count -gt 0

                [PSCustomObject]@{
                    Path = $OUPath
                    Exists = [bool]$Found
                }
            }

            # ----------------------------------------------
            # 9. Read default domain password policy
            # ----------------------------------------------

            $PasswordPolicy = Get-ADDefaultDomainPasswordPolicy `
                -ErrorAction Stop

            # ----------------------------------------------
            # 10. Read existing GPOs
            # ----------------------------------------------

            $GPOs = @(
                Get-GPO -All `
                    -Domain $Domain.DNSRoot `
                    -ErrorAction Stop |
                Select-Object `
                    DisplayName,
                    Id,
                    GpoStatus
            )

            # ----------------------------------------------
            # 11. Return serializable information
            # ----------------------------------------------

            [PSCustomObject]@{
                Domain = [string]$Domain.DNSRoot
                DomainDN = [string]$DomainDN

                ADModuleOK = $ADModuleOK
                GPOModuleOK = $GPOModuleOK

                SYSVOLOK = $SYSVOLOK
                NETLOGONOK = $NETLOGONOK

                OUResults = @($OUResults)

                MinPasswordLength = [int](
                    $PasswordPolicy.MinPasswordLength
                )

                PasswordHistoryCount = [int](
                    $PasswordPolicy.PasswordHistoryCount
                )

                ComplexityEnabled = [bool](
                    $PasswordPolicy.ComplexityEnabled
                )

                LockoutThreshold = [int](
                    $PasswordPolicy.LockoutThreshold
                )

                LockoutDuration = [string](
                    $PasswordPolicy.LockoutDuration
                )

                LockoutObservationWindow = [string](
                    $PasswordPolicy.LockoutObservationWindow
                )

                GPOs = @($GPOs)
            }
        } `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 12. Validate domain controller results
    # ------------------------------------------------------

    Add-Check `
        $DCName 'AD module' `
        'Available' `
        ([string]$Data.ADModuleOK) `
        ([bool]$Data.ADModuleOK)

    Add-Check `
        $DCName 'GroupPolicy module' `
        'Available' `
        ([string]$Data.GPOModuleOK) `
        ([bool]$Data.GPOModuleOK)

    Add-Check `
        $DCName 'Domain name' `
        $DomainName `
        $Data.Domain `
        ($Data.Domain -ieq $DomainName)

    Add-Check `
        $DCName 'SYSVOL share' `
        'Available' `
        ([string]$Data.SYSVOLOK) `
        ([bool]$Data.SYSVOLOK)

    Add-Check `
        $DCName 'NETLOGON share' `
        'Available' `
        ([string]$Data.NETLOGONOK) `
        ([bool]$Data.NETLOGONOK)

    foreach ($OU in @($Data.OUResults)) {

        Add-Check `
            $DCName `
            "OU exists: $($OU.Path)" `
            'True' `
            ([string]$OU.Exists) `
            ([bool]$OU.Exists)
    }

    # ------------------------------------------------------
    # 13. Display current domain security settings
    # ------------------------------------------------------

    $PolicyText = @"

CURRENT DOMAIN PASSWORD POLICY

Minimum password length:
$($Data.MinPasswordLength)

Password history:
$($Data.PasswordHistoryCount)

Complexity enabled:
$($Data.ComplexityEnabled)

Account lockout threshold:
$($Data.LockoutThreshold)

Account lockout duration:
$($Data.LockoutDuration)

Reset account lockout counter:
$($Data.LockoutObservationWindow)

"@

    $Details.Add($PolicyText)

    Write-Host ""
    Write-Host "Current domain password policy:"
    Write-Host $PolicyText

    # ------------------------------------------------------
    # 14. Display existing GPOs
    # ------------------------------------------------------

    $GPODetails = @($Data.GPOs)

    $GPOText = $GPODetails |
        Format-Table `
            DisplayName,
            GpoStatus,
            Id `
            -AutoSize |
        Out-String -Width 180

    $Details.Add(
        "EXISTING GROUP POLICY OBJECTS`r`n$GPOText"
    )

    Write-Host ""
    Write-Host "Existing GPOs:"
    Write-Host $GPOText

}
catch {

    Add-Check `
        $DCName `
        'Domain controller inspection' `
        'Successful' `
        $_.Exception.Message `
        $false

    Write-Warning (
        "Domain controller inspection failed: " +
        $_.Exception.Message
    )
}
finally {

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------
# 15. Export reports
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

$Passed = @(
    $Results |
    Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Results |
    Where-Object Status -eq 'FAIL'
).Count

$Total = $Results.Count

$Header = @"
LAB 8 - GROUP POLICY PRECHECK

Host: $env:COMPUTERNAME
Domain: $DomainName
Date: $(Get-Date)

Total: $Total
Passed: $Passed
Failed: $Failed

"@

$ChecksText = $Results |
    Format-Table `
        Machine, Check, Status `
        -AutoSize |
    Out-String -Width 200

$ReportText = (
    $Header +
    $ChecksText +
    "`r`n" +
    ($Details -join "`r`n")
)

$ReportText |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 16. Display final results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - PRECHECK RESULTS"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table `
        Machine,
        Check,
        Status `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "Passed: $Passed" -ForegroundColor Green
Write-Host "Failed: $Failed" -ForegroundColor Yellow

Write-Host ""
Write-Host "CSV: $CSV"
Write-Host "TXT: $TXT"

if ($Failed -gt 0) {

    Write-Warning (
        "LAB 8 - PRECHECK REQUIRES ATTENTION."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 8 - PRECHECK PASSED"
    Write-Host "==========================================" `
        -ForegroundColor Green
}

