# ==========================================================
# LAB 8 - Script 02 - Configure Password Policy
#
# Run on a Hyper-V host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Automatically detects the current host name.
#
# Domain: contoso.com
# Domain controller VM: SEA-DC1
#
# Configuration:
#   Minimum password length: 12 characters
#
# Preserved settings:
#   Password history
#   Password complexity
#   Minimum and maximum password age
#   Reversible encryption
#   Account lockout threshold
#   Lockout duration
#   Lockout observation window
#
# Safety:
#   Verify host and VM
#   Verify domain and PDC Emulator
#   Export existing password policy
#   Back up Default Domain Policy
#   Change only minimum password length
#   Verify resulting Active Directory policy
#   Check Default Domain Policy consistency
#
# Reports are stored on the Hyper-V host.
# GPO backup is stored inside SEA-DC1.
# ==========================================================

[CmdletBinding()]
param(
    [ValidateRange(8, 14)]
    [int]$MinimumPasswordLength = 12
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

# Automatically detect the current host.
$HostName = $env:COMPUTERNAME

$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'

$HostReportDir = 'C:\LabReports'
$DCBackupRoot = 'C:\LabReports\LAB08-Backups'

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $HostReportDir `
    "LAB08-Password-Policy_$Timestamp.csv"

$TXT = Join-Path $HostReportDir `
    "LAB08-Password-Policy_$Timestamp.txt"

$HTML = Join-Path $HostReportDir `
    "LAB08-Password-Policy_$Timestamp.html"

# ----------------------------------------------------------
# 2. Verify execution environment
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - HOST ENVIRONMENT VERIFICATION"
Write-Host "=========================================="
Write-Host ""

Write-Host "Detected host: $HostName"

# Verify administrative privileges.
$CurrentIdentity = (
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
)

$CurrentPrincipal = New-Object `
    System.Security.Principal.WindowsPrincipal `
    -ArgumentList $CurrentIdentity

$IsElevated = $CurrentPrincipal.IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsElevated) {
    throw 'Run Windows PowerShell as Administrator.'
}

# Verify the Hyper-V module.
Import-Module Hyper-V -ErrorAction Stop

# Verify the domain controller VM.
$VM = Get-VM `
    -Name $DCName `
    -ErrorAction Stop

if ([string]$VM.State -ne 'Running') {
    throw "$DCName is not running."
}

Write-Host "Hyper-V host verified: $HostName" `
    -ForegroundColor Green

Write-Host "Domain controller VM: $DCName" `
    -ForegroundColor Green

# ----------------------------------------------------------
# 3. Prepare report directory
# ----------------------------------------------------------

New-Item `
    -ItemType Directory `
    -Path $HostReportDir `
    -Force `
    -ErrorAction Stop | Out-Null

# ----------------------------------------------------------
# 4. Display configuration
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CONFIGURE DOMAIN PASSWORD POLICY"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host "Minimum password length: $MinimumPasswordLength"
Write-Host ""

# ----------------------------------------------------------
# 5. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 6. Connect to the domain controller
# ----------------------------------------------------------

$Session = $null
$Result = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 7. Inspect and configure password policy
    # ------------------------------------------------------

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList @(
            $DomainName
            $MinimumPasswordLength
            $DCBackupRoot
            $Timestamp
        ) `
        -ScriptBlock {

            param(
                [string]$ExpectedDomain,
                [int]$MinimumPasswordLength,
                [string]$BackupRoot,
                [string]$Timestamp
            )

            $ErrorActionPreference = 'Stop'

            # ----------------------------------------------
            # 8. Load required modules
            # ----------------------------------------------

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            Import-Module GroupPolicy `
                -ErrorAction Stop

            # ----------------------------------------------
            # 9. Validate Active Directory domain
            # ----------------------------------------------

            $Domain = Get-ADDomain `
                -ErrorAction Stop

            if ($Domain.DNSRoot -ine $ExpectedDomain) {

                throw (
                    "Unexpected domain: " +
                    $Domain.DNSRoot
                )
            }

            # Verify PDC Emulator availability.
            if (-not $Domain.PDCEmulator) {
                throw 'PDC Emulator could not be identified.'
            }

            # ----------------------------------------------
            # 10. Read current password policy
            # ----------------------------------------------

            $Before = Get-ADDefaultDomainPasswordPolicy `
                -Identity $ExpectedDomain `
                -ErrorAction Stop

            Write-Host ""
            Write-Host "CURRENT DOMAIN PASSWORD POLICY"

            $Before |
                Format-List `
                    MinPasswordLength,
                    PasswordHistoryCount,
                    ComplexityEnabled,
                    MinPasswordAge,
                    MaxPasswordAge,
                    LockoutThreshold,
                    LockoutDuration,
                    LockoutObservationWindow |
                Out-Host

            # ----------------------------------------------
            # 11. Prepare backup directory
            # ----------------------------------------------

            $BackupDirectory = Join-Path `
                $BackupRoot `
                "LAB08-02_$Timestamp"

            New-Item `
                -ItemType Directory `
                -Path $BackupDirectory `
                -Force `
                -ErrorAction Stop | Out-Null

            # ----------------------------------------------
            # 12. Export existing password policy
            # ----------------------------------------------

            $BeforePath = Join-Path `
                $BackupDirectory `
                'PasswordPolicy-Before.csv'

            $Before |
                Select-Object `
                    MinPasswordLength,
                    PasswordHistoryCount,
                    ComplexityEnabled,
                    ReversibleEncryptionEnabled,
                    MinPasswordAge,
                    MaxPasswordAge,
                    LockoutThreshold,
                    LockoutDuration,
                    LockoutObservationWindow |
                Export-Csv `
                    -Path $BeforePath `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -ErrorAction Stop

            # ----------------------------------------------
            # 13. Verify Default Domain Policy
            # ----------------------------------------------

            $GPO = Get-GPO `
                -Name 'Default Domain Policy' `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $ExpectedGPOId = [guid](
                '31b2f340-016d-11d2-945f-00c04fb984f9'
            )

            if ($GPO.Id -ne $ExpectedGPOId) {

                throw (
                    "Default Domain Policy has " +
                    "an unexpected GPO ID."
                )
            }

            # ----------------------------------------------
            # 14. Back up Default Domain Policy
            # ----------------------------------------------

            $GPOBackupPath = Join-Path `
                $BackupDirectory `
                'DefaultDomainPolicy'

            New-Item `
                -ItemType Directory `
                -Path $GPOBackupPath `
                -Force `
                -ErrorAction Stop | Out-Null

            $Backup = Backup-GPO `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -Path $GPOBackupPath `
                -Comment 'LAB08-02 before password policy change' `
                -ErrorAction Stop

            if (-not $Backup) {
                throw 'Default Domain Policy backup failed.'
            }

            # ----------------------------------------------
            # 15. Inspect GPO security template
            # ----------------------------------------------

            $PolicyTemplate = Join-Path `
                $env:windir `
                'SYSVOL\domain\Policies\{31B2F340-016D-11D2-945F-00C04FB984F9}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf'

            $GPOConfiguredLength = $null

            if (Test-Path -LiteralPath $PolicyTemplate) {

                $TemplateLines = @(
                    Get-Content `
                        -LiteralPath $PolicyTemplate `
                        -ErrorAction Stop
                )

                foreach ($Line in $TemplateLines) {

                    if (
                        $Line -match
                        '^\s*MinimumPasswordLength\s*=\s*(\d+)\s*$'
                    ) {

                        $GPOConfiguredLength = [int]$Matches[1]
                        break
                    }
                }
            }

            # ----------------------------------------------
            # 16. Modify the domain password policy
            # ----------------------------------------------

            $Action = 'UNCHANGED'

            if (
                $Before.MinPasswordLength -ne
                $MinimumPasswordLength
            ) {

                Write-Host ""
                Write-Host "Applying minimum password length..."

                Set-ADDefaultDomainPasswordPolicy `
                    -Identity $ExpectedDomain `
                    -MinPasswordLength $MinimumPasswordLength `
                    -ErrorAction Stop

                $Action = 'UPDATED'
            }

            # ----------------------------------------------
            # 17. Read policy after modification
            # ----------------------------------------------

            $After = Get-ADDefaultDomainPasswordPolicy `
                -Identity $ExpectedDomain `
                -ErrorAction Stop

            # ----------------------------------------------
            # 18. Verify password length
            # ----------------------------------------------

            $LengthOK = (
                $After.MinPasswordLength -eq
                $MinimumPasswordLength
            )

            # ----------------------------------------------
            # 19. Verify preserved settings
            # ----------------------------------------------

            $HistoryPreserved = (
                $After.PasswordHistoryCount -eq
                $Before.PasswordHistoryCount
            )

            $ComplexityPreserved = (
                $After.ComplexityEnabled -eq
                $Before.ComplexityEnabled
            )

            $LockoutPreserved = (
                $After.LockoutThreshold -eq
                    $Before.LockoutThreshold -and
                $After.LockoutDuration -eq
                    $Before.LockoutDuration -and
                $After.LockoutObservationWindow -eq
                    $Before.LockoutObservationWindow
            )

            $OtherSettingsPreserved = (
                $After.MinPasswordAge -eq
                    $Before.MinPasswordAge -and
                $After.MaxPasswordAge -eq
                    $Before.MaxPasswordAge -and
                $After.ReversibleEncryptionEnabled -eq
                    $Before.ReversibleEncryptionEnabled
            )

            $Verified = (
                $LengthOK -and
                $HistoryPreserved -and
                $ComplexityPreserved -and
                $LockoutPreserved -and
                $OtherSettingsPreserved
            )

            # ----------------------------------------------
            # 20. Export resulting password policy
            # ----------------------------------------------

            $AfterPath = Join-Path `
                $BackupDirectory `
                'PasswordPolicy-After.csv'

            $After |
                Select-Object `
                    MinPasswordLength,
                    PasswordHistoryCount,
                    ComplexityEnabled,
                    ReversibleEncryptionEnabled,
                    MinPasswordAge,
                    MaxPasswordAge,
                    LockoutThreshold,
                    LockoutDuration,
                    LockoutObservationWindow |
                Export-Csv `
                    -Path $AfterPath `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -ErrorAction Stop

            # ----------------------------------------------
            # 21. Check GPO and AD consistency
            # ----------------------------------------------

            $GPOConsistency = 'UNKNOWN'

            if ($null -ne $GPOConfiguredLength) {

                if (
                    $GPOConfiguredLength -eq
                    $MinimumPasswordLength
                ) {

                    $GPOConsistency = 'MATCH'
                }
                else {

                    $GPOConsistency = 'MISMATCH'
                }
            }

            # ----------------------------------------------
            # 22. Return results
            # ----------------------------------------------

            [PSCustomObject]@{
                Computer = $env:COMPUTERNAME
                Domain = [string]$Domain.DNSRoot
                PDCEmulator = [string]$Domain.PDCEmulator

                Action = $Action
                Verified = [bool]$Verified

                BeforeLength = [int]$Before.MinPasswordLength
                AfterLength = [int]$After.MinPasswordLength

                BeforeHistory = [int]$Before.PasswordHistoryCount
                AfterHistory = [int]$After.PasswordHistoryCount

                BeforeComplexity = [bool]$Before.ComplexityEnabled
                AfterComplexity = [bool]$After.ComplexityEnabled

                BeforeLockoutThreshold = [int]$Before.LockoutThreshold
                AfterLockoutThreshold = [int]$After.LockoutThreshold

                HistoryPreserved = [bool]$HistoryPreserved
                ComplexityPreserved = [bool]$ComplexityPreserved
                LockoutPreserved = [bool]$LockoutPreserved
                OtherSettingsPreserved = [bool]$OtherSettingsPreserved

                BackupDirectory = $BackupDirectory
                GPOBackupID = [string]$Backup.Id

                GPOConfiguredLength = if (
                    $null -ne $GPOConfiguredLength
                ) {
                    [string]$GPOConfiguredLength
                }
                else {
                    'Not found'
                }

                GPOConsistency = $GPOConsistency
            }

        } `
        -ErrorAction Stop

}
finally {

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------
# 23. Create host-side verification results
# ----------------------------------------------------------

$Checks = @(
    [PSCustomObject]@{
        Check = 'Minimum password length'
        Expected = [string]$MinimumPasswordLength
        Actual = [string]$Result.AfterLength
        Status = if (
            $Result.AfterLength -eq $MinimumPasswordLength
        ) { 'PASS' } else { 'FAIL' }
    }

    [PSCustomObject]@{
        Check = 'Password history preserved'
        Expected = 'True'
        Actual = [string]$Result.HistoryPreserved
        Status = if (
            $Result.HistoryPreserved
        ) { 'PASS' } else { 'FAIL' }
    }

    [PSCustomObject]@{
        Check = 'Password complexity preserved'
        Expected = 'True'
        Actual = [string]$Result.ComplexityPreserved
        Status = if (
            $Result.ComplexityPreserved
        ) { 'PASS' } else { 'FAIL' }
    }

    [PSCustomObject]@{
        Check = 'Account lockout settings preserved'
        Expected = 'True'
        Actual = [string]$Result.LockoutPreserved
        Status = if (
            $Result.LockoutPreserved
        ) { 'PASS' } else { 'FAIL' }
    }

    [PSCustomObject]@{
        Check = 'Other password settings preserved'
        Expected = 'True'
        Actual = [string]$Result.OtherSettingsPreserved
        Status = if (
            $Result.OtherSettingsPreserved
        ) { 'PASS' } else { 'FAIL' }
    }

    [PSCustomObject]@{
        Check = 'GPO backup created'
        Expected = 'Backup ID'
        Actual = [string]$Result.GPOBackupID
        Status = if (
            -not [string]::IsNullOrWhiteSpace(
                $Result.GPOBackupID
            )
        ) { 'PASS' } else { 'FAIL' }
    }

    [PSCustomObject]@{
        Check = 'Default Domain Policy consistency'
        Expected = [string]$MinimumPasswordLength
        Actual = [string]$Result.GPOConfiguredLength
        Status = if (
            $Result.GPOConsistency -eq 'MATCH'
        ) {
            'PASS'
        }
        else {
            'REVIEW'
        }
    }
)

# ----------------------------------------------------------
# 24. Export CSV report
# ----------------------------------------------------------

$Checks |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 25. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $Checks | Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Checks | Where-Object Status -eq 'FAIL'
).Count

$Review = @(
    $Checks | Where-Object Status -eq 'REVIEW'
).Count

$Total = $Checks.Count

# ----------------------------------------------------------
# 26. Generate TXT report
# ----------------------------------------------------------

$Header = @"
LAB 8 - SCRIPT 02 - PASSWORD POLICY REPORT

Host: $HostName
Domain: $DomainName
Domain controller: $DCName
PDC Emulator: $($Result.PDCEmulator)
Date: $(Get-Date)

Action: $($Result.Action)

Minimum password length:
Before: $($Result.BeforeLength)
After:  $($Result.AfterLength)

Password history:
Before: $($Result.BeforeHistory)
After:  $($Result.AfterHistory)

Complexity enabled:
Before: $($Result.BeforeComplexity)
After:  $($Result.AfterComplexity)

Account lockout threshold:
Before: $($Result.BeforeLockoutThreshold)
After:  $($Result.AfterLockoutThreshold)

Backup stored on SEA-DC1:
$($Result.BackupDirectory)

Default Domain Policy backup ID:
$($Result.GPOBackupID)

GPO configured minimum length:
$($Result.GPOConfiguredLength)

GPO consistency:
$($Result.GPOConsistency)

Total checks: $Total
PASS: $Passed
FAIL: $Failed
REVIEW: $Review

"@

$ChecksText = $Checks |
    Format-Table -AutoSize |
    Out-String -Width 200

($Header + "`r`n" + $ChecksText) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 27. Generate HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    background: #f5f9fb;
    color: #294554;
}
h1, h2 {
    color: #146393;
}
table {
    border-collapse: collapse;
    width: 100%;
    background: #ffffff;
}
th {
    background: #146393;
    color: #ffffff;
    text-align: left;
    padding: 10px;
}
td {
    border: 1px solid #dce6eb;
    padding: 9px;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
</style>
"@

$Intro = @"
<h1>LAB 8 - Password Policy Configuration</h1>

<p><strong>Host:</strong> $HostName</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>Domain controller:</strong> $DCName</p>
<p><strong>Action:</strong> $($Result.Action)</p>

<h2>Password policy</h2>

<p>
Minimum length:
$($Result.BeforeLength) to $($Result.AfterLength)
</p>

<p>
Password history:
$($Result.AfterHistory)
</p>

<p>
Complexity:
$($Result.AfterComplexity)
</p>

<p>
GPO consistency:
$($Result.GPOConsistency)
</p>

<h2>Verification checks</h2>
"@

$Checks |
    ConvertTo-Html `
        -Title 'LAB 8 - Password Policy' `
        -Head $CSS `
        -PreContent $Intro |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 28. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - PASSWORD POLICY RESULTS"
Write-Host "=========================================="
Write-Host ""

$Checks |
    Format-Table -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Host: $HostName"
Write-Host "Action: $($Result.Action)"

Write-Host ""
Write-Host "Minimum password length:"
Write-Host "Before: $($Result.BeforeLength)"
Write-Host "After:  $($Result.AfterLength)"

Write-Host ""
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red
Write-Host "REVIEW: $Review" -ForegroundColor Yellow

Write-Host ""
Write-Host "GPO backup on $DCName :"
Write-Host $Result.BackupDirectory

Write-Host ""
Write-Host "Reports on $HostName :"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 29. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0) {

    throw (
        "LAB 8 - Password policy verification failed."
    )
}

if ($Review -gt 0) {

    Write-Warning (
        "The Active Directory password policy was updated, " +
        "but the Default Domain Policy GPO template does " +
        "not confirm the same minimum password length. " +
        "A later Group Policy refresh may overwrite the " +
        "domain attribute. Review GPO configuration " +
        "before treating this as a persistent deployment."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 8 - PASSWORD POLICY VERIFIED"
    Write-Host "==========================================" `
        -ForegroundColor Green
}

