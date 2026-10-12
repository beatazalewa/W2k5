# ==========================================================
# LAB 8 - Script 03 - Configure Account Lockout Policy
#
# Run on a Hyper-V host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Host name is detected automatically.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
#
# Target settings:
#   Account lockout threshold: 5
#   Account lockout duration: 15 minutes
#   Reset counter after: 15 minutes
#
# Safety:
#   Verify execution environment
#   Verify Active Directory domain
#   Back up Default Domain Policy
#   Export settings before modification
#   Configure account lockout settings
#   Verify other password settings are unchanged
#   Inspect Default Domain Policy consistency
#   Export reports
#
# No user accounts are deliberately locked.
# ==========================================================

[CmdletBinding()]
param(
    [ValidateRange(1, 999)]
    [int]$LockoutThreshold = 5,

    [ValidateRange(1, 99999)]
    [int]$LockoutDurationMinutes = 15,

    [ValidateRange(1, 99999)]
    [int]$ResetCounterMinutes = 15
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$HostName = $env:COMPUTERNAME

$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'

$HostReportDir = 'C:\LabReports'
$DCBackupRoot = 'C:\LabReports\LAB08-Backups'

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $HostReportDir `
    "LAB08-Account-Lockout_$Timestamp.csv"

$TXT = Join-Path $HostReportDir `
    "LAB08-Account-Lockout_$Timestamp.txt"

$HTML = Join-Path $HostReportDir `
    "LAB08-Account-Lockout_$Timestamp.html"

$Results = [System.Collections.Generic.List[object]]::new()

# ----------------------------------------------------------
# 2. Helper function
# ----------------------------------------------------------

function Add-Check {

    param(
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [ValidateSet('PASS','FAIL','REVIEW')]
        [string]$Status
    )

    $Results.Add(
        [PSCustomObject]@{
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = $Status
        }
    )
}

# ----------------------------------------------------------
# 3. Verify input parameters
# ----------------------------------------------------------

# The counter reset interval must not exceed
# the lockout duration for this lab configuration.

if ($ResetCounterMinutes -gt $LockoutDurationMinutes) {

    throw (
        "ResetCounterMinutes cannot exceed " +
        "LockoutDurationMinutes."
    )
}

# ----------------------------------------------------------
# 4. Verify host environment
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - ACCOUNT LOCKOUT CONFIGURATION"
Write-Host "=========================================="
Write-Host ""

Write-Host "Detected host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host ""

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    System.Security.Principal.WindowsPrincipal `
    -ArgumentList $Identity

$IsAdmin = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {

    throw 'Run Windows PowerShell as Administrator.'
}

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM `
    -Name $DCName `
    -ErrorAction Stop

if ([string]$VM.State -ne 'Running') {

    throw "$DCName is not running."
}

New-Item `
    -ItemType Directory `
    -Path $HostReportDir `
    -Force `
    -ErrorAction Stop | Out-Null

# ----------------------------------------------------------
# 5. Display target configuration
# ----------------------------------------------------------

Write-Host "Target account lockout configuration:"
Write-Host ""
Write-Host "Threshold: $LockoutThreshold"
Write-Host "Lockout duration: $LockoutDurationMinutes minutes"
Write-Host "Reset counter: $ResetCounterMinutes minutes"
Write-Host ""

# ----------------------------------------------------------
# 6. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {

    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 7. Connect to SEA-DC1
# ----------------------------------------------------------

$Session = $null
$Data = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 8. Inspect and configure account lockout policy
    # ------------------------------------------------------

    $Data = Invoke-Command `
        -Session $Session `
        -ArgumentList @(
            $DomainName
            $LockoutThreshold
            $LockoutDurationMinutes
            $ResetCounterMinutes
            $DCBackupRoot
            $Timestamp
        ) `
        -ScriptBlock {

            param(
                [string]$ExpectedDomain,
                [int]$Threshold,
                [int]$DurationMinutes,
                [int]$ResetMinutes,
                [string]$BackupRoot,
                [string]$Timestamp
            )

            $ErrorActionPreference = 'Stop'

            # ----------------------------------------------
            # 9. Load management modules
            # ----------------------------------------------

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            Import-Module GroupPolicy `
                -ErrorAction Stop

            # ----------------------------------------------
            # 10. Verify domain and PDC Emulator
            # ----------------------------------------------

            $Domain = Get-ADDomain `
                -ErrorAction Stop

            if ($Domain.DNSRoot -ine $ExpectedDomain) {

                throw (
                    "Unexpected domain: $($Domain.DNSRoot)"
                )
            }

            if (-not $Domain.PDCEmulator) {

                throw 'PDC Emulator not found.'
            }

            # ----------------------------------------------
            # 11. Read current policy
            # ----------------------------------------------

            $Before = Get-ADDefaultDomainPasswordPolicy `
                -Identity $ExpectedDomain `
                -ErrorAction Stop

            Write-Host ""
            Write-Host "CURRENT ACCOUNT LOCKOUT POLICY"
            Write-Host ""

            $Before |
                Format-List `
                    LockoutThreshold,
                    LockoutDuration,
                    LockoutObservationWindow,
                    MinPasswordLength,
                    PasswordHistoryCount,
                    ComplexityEnabled |
                Out-Host

            # ----------------------------------------------
            # 12. Prepare backup folder
            # ----------------------------------------------

            $BackupDirectory = Join-Path `
                $BackupRoot `
                "LAB08-03_$Timestamp"

            New-Item `
                -ItemType Directory `
                -Path $BackupDirectory `
                -Force `
                -ErrorAction Stop | Out-Null

            # ----------------------------------------------
            # 13. Export original account policy
            # ----------------------------------------------

            $BeforeFile = Join-Path `
                $BackupDirectory `
                'DomainPolicy-Before.csv'

            $Before |
                Select-Object `
                    LockoutThreshold,
                    LockoutDuration,
                    LockoutObservationWindow,
                    MinPasswordLength,
                    PasswordHistoryCount,
                    ComplexityEnabled,
                    ReversibleEncryptionEnabled,
                    MinPasswordAge,
                    MaxPasswordAge |
                Export-Csv `
                    -Path $BeforeFile `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -ErrorAction Stop

            # ----------------------------------------------
            # 14. Verify Default Domain Policy
            # ----------------------------------------------

            $GPO = Get-GPO `
                -Name 'Default Domain Policy' `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $ExpectedGPOId = [guid](
                '31b2f340-016d-11d2-945f-00c04fb984f9'
            )

            if ($GPO.Id -ne $ExpectedGPOId) {

                throw 'Unexpected Default Domain Policy ID.'
            }

            # ----------------------------------------------
            # 15. Back up Default Domain Policy
            # ----------------------------------------------

            $GPOBackupDirectory = Join-Path `
                $BackupDirectory `
                'DefaultDomainPolicy'

            New-Item `
                -ItemType Directory `
                -Path $GPOBackupDirectory `
                -Force `
                -ErrorAction Stop | Out-Null

            $Backup = Backup-GPO `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -Path $GPOBackupDirectory `
                -Comment 'LAB08-03 before account lockout change' `
                -ErrorAction Stop

            if (-not $Backup) {

                throw 'GPO backup failed.'
            }

            # ----------------------------------------------
            # 16. Read GPO security template
            # ----------------------------------------------

            $GPOID = $GPO.Id.ToString('B').ToUpperInvariant()

            $TemplatePath = Join-Path `
                $env:windir `
                "SYSVOL\domain\Policies\$GPOID\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf"

            $TemplateValues = @{}

            if (Test-Path -LiteralPath $TemplatePath) {

                foreach (
                    $Line in (
                        Get-Content `
                            -LiteralPath $TemplatePath `
                            -ErrorAction Stop
                    )
                ) {

                    if (
                        $Line -match
                        '^\s*(LockoutBadCount|LockoutDuration|ResetLockoutCount)\s*=\s*(-?\d+)\s*$'
                    ) {

                        $TemplateValues[$Matches[1]] = (
                            [int]$Matches[2]
                        )
                    }
                }
            }

            # ----------------------------------------------
            # 17. Prepare target time intervals
            # ----------------------------------------------

            $TargetDuration = New-TimeSpan `
                -Minutes $DurationMinutes

            $TargetReset = New-TimeSpan `
                -Minutes $ResetMinutes

            # ----------------------------------------------
            # 18. Apply account lockout configuration
            # ----------------------------------------------

            $Action = 'UNCHANGED'

            $ChangeRequired = (
                $Before.LockoutThreshold -ne $Threshold -or
                $Before.LockoutDuration -ne $TargetDuration -or
                $Before.LockoutObservationWindow -ne $TargetReset
            )

            if ($ChangeRequired) {

                Write-Host ""
                Write-Host "Applying account lockout policy..."

                # The requested parameters are applied
                # together to avoid intermediate policy
                # states with inconsistent time intervals.

                Set-ADDefaultDomainPasswordPolicy `
                    -Identity $ExpectedDomain `
                    -LockoutThreshold $Threshold `
                    -LockoutDuration $TargetDuration `
                    -LockoutObservationWindow $TargetReset `
                    -ErrorAction Stop

                $Action = 'UPDATED'
            }

            # ----------------------------------------------
            # 19. Read resulting Active Directory policy
            # ----------------------------------------------

            $After = Get-ADDefaultDomainPasswordPolicy `
                -Identity $ExpectedDomain `
                -ErrorAction Stop

            # ----------------------------------------------
            # 20. Verify target settings
            # ----------------------------------------------

            $ThresholdOK = (
                $After.LockoutThreshold -eq $Threshold
            )

            $DurationOK = (
                $After.LockoutDuration -eq $TargetDuration
            )

            $ResetOK = (
                $After.LockoutObservationWindow -eq $TargetReset
            )

            # ----------------------------------------------
            # 21. Verify preserved password settings
            # ----------------------------------------------

            $PasswordSettingsPreserved = (
                $After.MinPasswordLength -eq
                    $Before.MinPasswordLength -and
                $After.PasswordHistoryCount -eq
                    $Before.PasswordHistoryCount -and
                $After.ComplexityEnabled -eq
                    $Before.ComplexityEnabled -and
                $After.ReversibleEncryptionEnabled -eq
                    $Before.ReversibleEncryptionEnabled -and
                $After.MinPasswordAge -eq
                    $Before.MinPasswordAge -and
                $After.MaxPasswordAge -eq
                    $Before.MaxPasswordAge
            )

            # ----------------------------------------------
            # 22. Export resulting domain policy
            # ----------------------------------------------

            $AfterFile = Join-Path `
                $BackupDirectory `
                'DomainPolicy-After.csv'

            $After |
                Select-Object `
                    LockoutThreshold,
                    LockoutDuration,
                    LockoutObservationWindow,
                    MinPasswordLength,
                    PasswordHistoryCount,
                    ComplexityEnabled,
                    ReversibleEncryptionEnabled,
                    MinPasswordAge,
                    MaxPasswordAge |
                Export-Csv `
                    -Path $AfterFile `
                    -NoTypeInformation `
                    -Encoding UTF8 `
                    -ErrorAction Stop

            # ----------------------------------------------
            # 23. Check GPO template consistency
            # ----------------------------------------------

            # In GptTmpl.inf the lockout duration
            # and reset interval are expressed in minutes.

            $RequiredTemplateKeys = @(
                'LockoutBadCount'
                'LockoutDuration'
                'ResetLockoutCount'
            )

            $TemplateComplete = $true

            foreach ($Key in $RequiredTemplateKeys) {

                if (-not $TemplateValues.ContainsKey($Key)) {

                    $TemplateComplete = $false
                }
            }

            $GPOConsistency = 'UNKNOWN'

            if ($TemplateComplete) {

                $TemplateMatches = (
                    $TemplateValues['LockoutBadCount'] -eq
                        $Threshold -and

                    $TemplateValues['LockoutDuration'] -eq
                        $DurationMinutes -and

                    $TemplateValues['ResetLockoutCount'] -eq
                        $ResetMinutes
                )

                $GPOConsistency = if ($TemplateMatches) {
                    'MATCH'
                }
                else {
                    'MISMATCH'
                }
            }

            # ----------------------------------------------
            # 24. Return verification data
            # ----------------------------------------------

            [PSCustomObject]@{
                Computer = $env:COMPUTERNAME
                Domain = $Domain.DNSRoot
                PDCEmulator = [string]$Domain.PDCEmulator

                Action = $Action

                BeforeThreshold = [int]$Before.LockoutThreshold
                AfterThreshold = [int]$After.LockoutThreshold

                BeforeDurationMinutes = [double](
                    $Before.LockoutDuration.TotalMinutes
                )

                AfterDurationMinutes = [double](
                    $After.LockoutDuration.TotalMinutes
                )

                BeforeResetMinutes = [double](
                    $Before.LockoutObservationWindow.TotalMinutes
                )

                AfterResetMinutes = [double](
                    $After.LockoutObservationWindow.TotalMinutes
                )

                ThresholdOK = [bool]$ThresholdOK
                DurationOK = [bool]$DurationOK
                ResetOK = [bool]$ResetOK

                PasswordSettingsPreserved = (
                    [bool]$PasswordSettingsPreserved
                )

                MinimumPasswordLength = [int](
                    $After.MinPasswordLength
                )

                PasswordHistory = [int](
                    $After.PasswordHistoryCount
                )

                ComplexityEnabled = [bool](
                    $After.ComplexityEnabled
                )

                BackupDirectory = $BackupDirectory
                GPOBackupID = [string]$Backup.Id

                GPOConsistency = $GPOConsistency

                GPOLockoutThreshold = if (
                    $TemplateValues.ContainsKey('LockoutBadCount')
                ) {
                    [string]$TemplateValues['LockoutBadCount']
                }
                else {
                    'Not found'
                }

                GPOLockoutDuration = if (
                    $TemplateValues.ContainsKey('LockoutDuration')
                ) {
                    [string]$TemplateValues['LockoutDuration']
                }
                else {
                    'Not found'
                }

                GPOResetCounter = if (
                    $TemplateValues.ContainsKey('ResetLockoutCount')
                ) {
                    [string]$TemplateValues['ResetLockoutCount']
                }
                else {
                    'Not found'
                }
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
# 25. Create verification checks
# ----------------------------------------------------------

Add-Check `
    'Account lockout threshold' `
    ([string]$LockoutThreshold) `
    ([string]$Data.AfterThreshold) `
    $(if ($Data.ThresholdOK) { 'PASS' } else { 'FAIL' })

Add-Check `
    'Account lockout duration' `
    "$LockoutDurationMinutes minutes" `
    "$($Data.AfterDurationMinutes) minutes" `
    $(if ($Data.DurationOK) { 'PASS' } else { 'FAIL' })

Add-Check `
    'Reset account lockout counter' `
    "$ResetCounterMinutes minutes" `
    "$($Data.AfterResetMinutes) minutes" `
    $(if ($Data.ResetOK) { 'PASS' } else { 'FAIL' })

Add-Check `
    'Other password settings preserved' `
    'True' `
    ([string]$Data.PasswordSettingsPreserved) `
    $(if ($Data.PasswordSettingsPreserved) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'Default Domain Policy backup' `
    'Backup ID' `
    $Data.GPOBackupID `
    $(if (
        -not [string]::IsNullOrWhiteSpace($Data.GPOBackupID)
    ) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'Default Domain Policy consistency' `
    'MATCH' `
    $Data.GPOConsistency `
    $(if ($Data.GPOConsistency -eq 'MATCH') {
        'PASS'
    } else {
        'REVIEW'
    })

# ----------------------------------------------------------
# 26. Calculate final statistics
# ----------------------------------------------------------

$Passed = @(
    $Results | Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Results | Where-Object Status -eq 'FAIL'
).Count

$Review = @(
    $Results | Where-Object Status -eq 'REVIEW'
).Count

$Total = $Results.Count

# ----------------------------------------------------------
# 27. Export CSV
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 28. Create TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 8 - SCRIPT 03 - ACCOUNT LOCKOUT POLICY
============================================================

Host: $HostName
Domain: $DomainName
Domain controller: $DCName
PDC Emulator: $($Data.PDCEmulator)

Date: $(Get-Date)

Action: $($Data.Action)

ACCOUNT LOCKOUT THRESHOLD
Before: $($Data.BeforeThreshold)
After:  $($Data.AfterThreshold)

ACCOUNT LOCKOUT DURATION
Before: $($Data.BeforeDurationMinutes) minutes
After:  $($Data.AfterDurationMinutes) minutes

RESET ACCOUNT LOCKOUT COUNTER
Before: $($Data.BeforeResetMinutes) minutes
After:  $($Data.AfterResetMinutes) minutes

PRESERVED PASSWORD SETTINGS
Minimum length: $($Data.MinimumPasswordLength)
Password history: $($Data.PasswordHistory)
Complexity enabled: $($Data.ComplexityEnabled)

GPO BACKUP ON SEA-DC1
Directory: $($Data.BackupDirectory)
Backup ID: $($Data.GPOBackupID)

DEFAULT DOMAIN POLICY TEMPLATE
LockoutBadCount: $($Data.GPOLockoutThreshold)
LockoutDuration: $($Data.GPOLockoutDuration)
ResetLockoutCount: $($Data.GPOResetCounter)

GPO consistency: $($Data.GPOConsistency)

VERIFICATION
Total: $Total
PASS: $Passed
FAIL: $Failed
REVIEW: $Review

"@

$ChecksText = $Results |
    Format-Table `
        Check, Expected, Actual, Status `
        -AutoSize |
    Out-String -Width 220

($Header + "`r`n" + $ChecksText) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 29. Create HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    background: #f5f9fb;
    color: #294554;
    margin: 32px;
    line-height: 1.5;
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
    padding: 10px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 9px;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
.summary {
    background: #ffffff;
    border: 1px solid #dce6eb;
    padding: 16px;
    margin-bottom: 24px;
}
</style>
"@

$HTMLIntro = @"
<h1>LAB 8 - Account Lockout Policy</h1>

<div class="summary">
<p><strong>Host:</strong> $HostName</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>Domain controller:</strong> $DCName</p>
<p><strong>Action:</strong> $($Data.Action)</p>
</div>

<h2>Account lockout settings</h2>

<p>
Lockout threshold:
$($Data.BeforeThreshold) to $($Data.AfterThreshold)
</p>

<p>
Lockout duration:
$($Data.BeforeDurationMinutes) to
$($Data.AfterDurationMinutes) minutes
</p>

<p>
Reset counter:
$($Data.BeforeResetMinutes) to
$($Data.AfterResetMinutes) minutes
</p>

<h2>Default Domain Policy</h2>

<p>GPO consistency: $($Data.GPOConsistency)</p>

<h2>Verification checks</h2>
"@

$Results |
    ConvertTo-Html `
        -Title 'LAB 8 - Account Lockout Policy' `
        -Head $CSS `
        -PreContent $HTMLIntro |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 30. Display final results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - ACCOUNT LOCKOUT POLICY RESULTS"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Host: $HostName"
Write-Host "Action: $($Data.Action)"

Write-Host ""
Write-Host "Account lockout threshold:"
Write-Host "Before: $($Data.BeforeThreshold)"
Write-Host "After:  $($Data.AfterThreshold)"

Write-Host ""
Write-Host "Account lockout duration:"
Write-Host "Before: $($Data.BeforeDurationMinutes) minutes"
Write-Host "After:  $($Data.AfterDurationMinutes) minutes"

Write-Host ""
Write-Host "Reset counter:"
Write-Host "Before: $($Data.BeforeResetMinutes) minutes"
Write-Host "After:  $($Data.AfterResetMinutes) minutes"

Write-Host ""
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red
Write-Host "REVIEW: $Review" -ForegroundColor Yellow

Write-Host ""
Write-Host "GPO backup stored on $DCName :"
Write-Host $Data.BackupDirectory

Write-Host ""
Write-Host "Reports stored on $HostName :"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 31. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0) {

    throw (
        "LAB 8 - Account lockout policy verification failed."
    )
}

if ($Review -gt 0) {

    Write-Warning (
        "The Active Directory lockout values were applied, " +
        "but the Default Domain Policy security template " +
        "does not confirm the same values. " +
        "Group Policy processing may reapply different " +
        "settings. Review and correct the GPO before " +
        "treating the deployment as complete."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 8 - ACCOUNT LOCKOUT POLICY VERIFIED"
    Write-Host "==========================================" `
        -ForegroundColor Green
}
