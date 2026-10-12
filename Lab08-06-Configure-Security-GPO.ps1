# ==========================================================
# LAB 8 - Script 06 - Configure Security GPO
#
# Run on the Hyper-V host as Administrator.
# Windows PowerShell 5.1 required.
#
# Automatically detects the host computer name.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# Workstation: SEA-CL1
#
# GPO: LAB08-Security-Workstations
#
# Target OU:
# OU=Stacje robocze,OU=Centrala,DC=contoso,DC=com
#
# Security settings:
#   Domain firewall enabled
#   Default inbound connections blocked
#   Default outbound connections allowed
#   Firewall notifications enabled
#   Administrator UAC prompt enabled
#   UAC secure desktop enabled
#
# This script configures the GPO on SEA-DC1.
# Client-side enforcement is verified separately.
#
# Does not modify Default Domain Policy.
# Does not disable Microsoft Defender.
# Does not modify firewall exception rules.
# ==========================================================

[CmdletBinding()]
param(
    [string]$GPOName = 'LAB08-Security-Workstations'
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$HostName = $env:COMPUTERNAME
$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'
$ClientName = 'SEA-CL1'

$TargetOU = (
    'OU=Stacje robocze,' +
    'OU=Centrala,' +
    'DC=contoso,DC=com'
)

$ReportDir = 'C:\LabReports'
$DCBackupRoot = 'C:\LabReports\LAB08-Backups'

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $ReportDir `
    "LAB08-Security-GPO_$Timestamp.csv"

$TXT = Join-Path $ReportDir `
    "LAB08-Security-GPO_$Timestamp.txt"

$HTML = Join-Path $ReportDir `
    "LAB08-Security-GPO_$Timestamp.html"

$Checks = New-Object `
    'System.Collections.Generic.List[object]'

# ----------------------------------------------------------
# 2. Helper function
# ----------------------------------------------------------

function Add-LabCheck {

    param(
        [string]$Name,
        [string]$Expected,
        [string]$Actual,
        [bool]$Passed
    )

    $Checks.Add(
        [PSCustomObject]@{
            Check = $Name
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
# 3. Display configuration
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CONFIGURE SECURITY GPO"
Write-Host "=========================================="
Write-Host ""

Write-Host "Detected host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host "Workstation: $ClientName"
Write-Host "GPO: $GPOName"
Write-Host "Target OU: $TargetOU"
Write-Host ""

# ----------------------------------------------------------
# 4. Verify host environment
# ----------------------------------------------------------

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal `
    -ArgumentList $Identity

$IsAdministrator = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdministrator) {
    throw 'Run Windows PowerShell as Administrator.'
}

Import-Module Hyper-V -ErrorAction Stop

foreach ($VMName in @($DCName, $ClientName)) {

    $VM = Get-VM `
        -Name $VMName `
        -ErrorAction Stop

    if ([string]$VM.State -ne 'Running') {
        throw "Required VM is not running: $VMName"
    }
}

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force `
    -ErrorAction Stop | Out-Null

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
# 6. Connect to domain controller
# ----------------------------------------------------------

$Session = $null
$Data = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 7. Configure the security GPO on SEA-DC1
    # ------------------------------------------------------

    $Data = Invoke-Command `
        -Session $Session `
        -ArgumentList @(
            $DomainName
            $GPOName
            $TargetOU
            $ClientName
            $DCBackupRoot
            $Timestamp
        ) `
        -ScriptBlock {

            param(
                [string]$ExpectedDomain,
                [string]$GPOName,
                [string]$TargetOU,
                [string]$ClientName,
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
            # 9. Verify domain and target OU
            # ----------------------------------------------

            $Domain = Get-ADDomain -ErrorAction Stop

            if ($Domain.DNSRoot -ine $ExpectedDomain) {
                throw "Unexpected domain: $($Domain.DNSRoot)"
            }

            $OU = Get-ADOrganizationalUnit `
                -Identity $TargetOU `
                -ErrorAction Stop

            if ($OU.DistinguishedName -ine $TargetOU) {
                throw 'Target OU verification failed.'
            }

            # ----------------------------------------------
            # 10. Verify workstation location
            # ----------------------------------------------

            $Computer = Get-ADComputer `
                -Identity $ClientName `
                -ErrorAction Stop

            $ComputerDN = [string]$Computer.DistinguishedName

            $ComputerOU = $ComputerDN.Substring(
                $ComputerDN.IndexOf(',') + 1
            )

            $ComputerInTargetOU = (
                $ComputerOU -ieq $TargetOU
            )

            if (-not $ComputerInTargetOU) {

                throw (
                    "Workstation $ClientName is not " +
                    "in the target OU. Current OU: " +
                    $ComputerOU
                )
            }

            # ----------------------------------------------
            # 11. Locate existing GPO
            # ----------------------------------------------

            $ExistingGPO = @(
                Get-GPO `
                    -All `
                    -Domain $ExpectedDomain `
                    -ErrorAction Stop |
                Where-Object {
                    $_.DisplayName -eq $GPOName
                }
            )

            if ($ExistingGPO.Count -gt 1) {
                throw 'Multiple GPOs with the same name.'
            }

            # ----------------------------------------------
            # 12. Prepare backup folder
            # ----------------------------------------------

            $BackupDirectory = Join-Path `
                $BackupRoot `
                "LAB08-06_$Timestamp"

            New-Item `
                -ItemType Directory `
                -Path $BackupDirectory `
                -Force `
                -ErrorAction Stop | Out-Null

            # ----------------------------------------------
            # 13. Create or reuse GPO
            # ----------------------------------------------

            $PreviousBackupID = ''

            if ($ExistingGPO.Count -eq 1) {

                $GPO = $ExistingGPO[0]
                $Action = 'UPDATED'

                $PreviousBackup = Backup-GPO `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Path $BackupDirectory `
                    -Comment 'LAB08-06 before security GPO update' `
                    -ErrorAction Stop

                $PreviousBackupID = [string](
                    $PreviousBackup.Id
                )
            }
            else {

                $GPO = New-GPO `
                    -Name $GPOName `
                    -Domain $ExpectedDomain `
                    -Comment 'LAB 8 - Workstation security baseline' `
                    -ErrorAction Stop

                $Action = 'CREATED'
            }

            # ----------------------------------------------
            # 14. Verify computer configuration availability
            # ----------------------------------------------

            $GPO = Get-GPO `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $InitialStatus = [string]$GPO.GpoStatus

            if (
                $InitialStatus -in @(
                    'ComputerSettingsDisabled'
                    'AllSettingsDisabled'
                )
            ) {

                # Do not silently change an existing GPO
                # with disabled computer configuration.

                throw (
                    "Computer configuration is disabled " +
                    "in GPO $GPOName. Current status: " +
                    $InitialStatus
                )
            }

            # ----------------------------------------------
            # 15. Define policy registry keys
            # ----------------------------------------------

            $FirewallKey = (
                'HKLM\Software\Policies\Microsoft\' +
                'WindowsFirewall\DomainProfile'
            )

            $UACKey = (
                'HKLM\Software\Microsoft\Windows\' +
                'CurrentVersion\Policies\System'
            )

            # ----------------------------------------------
            # 16. Define security settings
            # ----------------------------------------------

            $Settings = @(
                [PSCustomObject]@{
                    Name = 'EnableFirewall'
                    Key = $FirewallKey
                    Expected = 1
                }
                [PSCustomObject]@{
                    Name = 'DefaultInboundAction'
                    Key = $FirewallKey
                    Expected = 1
                }
                [PSCustomObject]@{
                    Name = 'DefaultOutboundAction'
                    Key = $FirewallKey
                    Expected = 0
                }
                [PSCustomObject]@{
                    Name = 'DisableNotifications'
                    Key = $FirewallKey
                    Expected = 0
                }
                [PSCustomObject]@{
                    Name = 'ConsentPromptBehaviorAdmin'
                    Key = $UACKey
                    Expected = 5
                }
                [PSCustomObject]@{
                    Name = 'PromptOnSecureDesktop'
                    Key = $UACKey
                    Expected = 1
                }
            )

            # ----------------------------------------------
            # 17. Apply GPO registry settings
            # ----------------------------------------------

            Write-Host ""
            Write-Host "Configuring security policy settings..."

            foreach ($Setting in $Settings) {

                Set-GPRegistryValue `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Key $Setting.Key `
                    -ValueName $Setting.Name `
                    -Type DWord `
                    -Value ([int]$Setting.Expected) `
                    -ErrorAction Stop
            }

            # ----------------------------------------------
            # 18. Check existing GPO links
            # ----------------------------------------------

            $InheritanceBefore = Get-GPInheritance `
                -Target $TargetOU `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $ExistingLinks = @(
                $InheritanceBefore.GpoLinks |
                Where-Object {
                    [string]$_.GpoId -eq
                    [string]$GPO.Id
                }
            )

            $LinkAction = 'UNCHANGED'

            if ($ExistingLinks.Count -eq 0) {

                New-GPLink `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Target $TargetOU `
                    -LinkEnabled Yes `
                    -Enforced No `
                    -ErrorAction Stop | Out-Null

                $LinkAction = 'CREATED'
            }
            else {

                $LinkEnabled = (
                    [string]$ExistingLinks[0].Enabled -in
                    @('Yes','True')
                )

                if (-not $LinkEnabled) {

                    Set-GPLink `
                        -Guid $GPO.Id `
                        -Domain $ExpectedDomain `
                        -Target $TargetOU `
                        -LinkEnabled Yes `
                        -ErrorAction Stop | Out-Null

                    $LinkAction = 'ENABLED'
                }
            }

            # ----------------------------------------------
            # 19. Verify all six security settings
            # ----------------------------------------------

            $Verification = @(
                foreach ($Setting in $Settings) {

                    $Actual = Get-GPRegistryValue `
                        -Guid $GPO.Id `
                        -Domain $ExpectedDomain `
                        -Key $Setting.Key `
                        -ValueName $Setting.Name `
                        -ErrorAction Stop

                    [PSCustomObject]@{
                        Name = [string]$Setting.Name
                        Expected = [int]$Setting.Expected
                        Actual = [int]$Actual.Value
                        Passed = [bool](
                            [int]$Actual.Value -eq
                                [int]$Setting.Expected -and
                            [string]$Actual.Type -eq 'DWord'
                        )
                    }
                }
            )

            # ----------------------------------------------
            # 20. Verify direct GPO link
            # ----------------------------------------------

            $InheritanceAfter = Get-GPInheritance `
                -Target $TargetOU `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $VerifiedLinks = @(
                $InheritanceAfter.GpoLinks |
                Where-Object {
                    [string]$_.GpoId -eq
                    [string]$GPO.Id
                }
            )

            $LinkOK = (
                $VerifiedLinks.Count -eq 1 -and
                [string]$VerifiedLinks[0].Enabled -in
                    @('Yes','True')
            )

            # ----------------------------------------------
            # 21. Verify computer GPO status
            # ----------------------------------------------

            $FinalGPO = Get-GPO `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $ComputerSettingsEnabled = (
                [string]$FinalGPO.GpoStatus -in @(
                    'AllSettingsEnabled'
                    'UserSettingsDisabled'
                )
            )

            # ----------------------------------------------
            # 22. Back up final GPO
            # ----------------------------------------------

            $ConfiguredBackupPath = Join-Path `
                $BackupDirectory `
                'Configured'

            New-Item `
                -ItemType Directory `
                -Path $ConfiguredBackupPath `
                -Force `
                -ErrorAction Stop | Out-Null

            $ConfiguredBackup = Backup-GPO `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -Path $ConfiguredBackupPath `
                -Comment 'LAB08-06 configured security GPO' `
                -ErrorAction Stop

            # ----------------------------------------------
            # 23. Generate GPO XML report
            # ----------------------------------------------

            $GPOReportPath = Join-Path `
                $BackupDirectory `
                'Security-GPO-Report.xml'

            Get-GPOReport `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -ReportType Xml `
                -Path $GPOReportPath `
                -ErrorAction Stop

            # ----------------------------------------------
            # 24. Return summary as a separate record
            # ----------------------------------------------

            [PSCustomObject]@{
                RecordType = 'SUMMARY'

                Computer = $env:COMPUTERNAME
                Domain = [string]$Domain.DNSRoot

                GPOName = $GPOName
                GPOID = [string]$GPO.Id
                Action = $Action

                TargetOU = $TargetOU
                ClientName = $ClientName
                ComputerDN = $ComputerDN
                ComputerInTargetOU = (
                    [bool]$ComputerInTargetOU
                )

                LinkAction = $LinkAction
                LinkOK = [bool]$LinkOK
                ComputerSettingsEnabled = (
                    [bool]$ComputerSettingsEnabled
                )

                BackupDirectory = $BackupDirectory
                PreviousBackupID = $PreviousBackupID
                ConfiguredBackupID = (
                    [string]$ConfiguredBackup.Id
                )

                GPOReportPath = $GPOReportPath
            }

            # ----------------------------------------------
            # 25. Return one record per security setting
            # ----------------------------------------------

            foreach ($Item in $Verification) {

                [PSCustomObject]@{
                    RecordType = 'SETTING'
                    Name = [string]$Item.Name
                    Expected = [int]$Item.Expected
                    Actual = [int]$Item.Actual
                    Passed = [bool]$Item.Passed
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
# 26. Separate summary and setting records
# ----------------------------------------------------------

$SummaryRecords = @(
    $Data |
    Where-Object {
        $_.RecordType -eq 'SUMMARY'
    }
)

$SettingRecords = @(
    $Data |
    Where-Object {
        $_.RecordType -eq 'SETTING'
    }
)

if ($SummaryRecords.Count -ne 1) {

    throw (
        "Expected one summary record; received " +
        $SummaryRecords.Count
    )
}

if ($SettingRecords.Count -ne 6) {

    throw (
        "Expected six setting records; received " +
        $SettingRecords.Count
    )
}

$Summary = $SummaryRecords[0]

# ----------------------------------------------------------
# 27. Validate setting record names
# ----------------------------------------------------------

$ExpectedNames = @(
    'EnableFirewall'
    'DefaultInboundAction'
    'DefaultOutboundAction'
    'DisableNotifications'
    'ConsentPromptBehaviorAdmin'
    'PromptOnSecureDesktop'
)

foreach ($ExpectedName in $ExpectedNames) {

    $MatchingRecords = @(
        $SettingRecords |
        Where-Object {
            $_.Name -eq $ExpectedName
        }
    )

    if ($MatchingRecords.Count -ne 1) {

        throw (
            "Missing or duplicated setting record: " +
            $ExpectedName
        )
    }
}

# ----------------------------------------------------------
# 28. Add summary verification checks
# ----------------------------------------------------------

Add-LabCheck `
    -Name 'Security GPO exists' `
    -Expected $GPOName `
    -Actual ([string]$Summary.GPOName) `
    -Passed (
        $Summary.GPOName -eq $GPOName -and
        -not [string]::IsNullOrWhiteSpace(
            [string]$Summary.GPOID
        )
    )

Add-LabCheck `
    -Name 'SEA-CL1 in workstation OU' `
    -Expected 'True' `
    -Actual ([string]$Summary.ComputerInTargetOU) `
    -Passed ([bool]$Summary.ComputerInTargetOU)

# ----------------------------------------------------------
# 29. Add six registry setting checks
# ----------------------------------------------------------

foreach ($Setting in $SettingRecords) {

    Add-LabCheck `
        -Name ([string]$Setting.Name) `
        -Expected "DWORD $($Setting.Expected)" `
        -Actual "DWORD $($Setting.Actual)" `
        -Passed ([bool]$Setting.Passed)
}

# ----------------------------------------------------------
# 30. Add GPO link and backup checks
# ----------------------------------------------------------

Add-LabCheck `
    -Name 'GPO link to workstation OU' `
    -Expected 'Enabled' `
    -Actual ([string]$Summary.LinkOK) `
    -Passed ([bool]$Summary.LinkOK)

Add-LabCheck `
    -Name 'Computer configuration enabled' `
    -Expected 'True' `
    -Actual ([string]$Summary.ComputerSettingsEnabled) `
    -Passed ([bool]$Summary.ComputerSettingsEnabled)

Add-LabCheck `
    -Name 'Configured GPO backup' `
    -Expected 'Backup ID' `
    -Actual ([string]$Summary.ConfiguredBackupID) `
    -Passed (
        -not [string]::IsNullOrWhiteSpace(
            [string]$Summary.ConfiguredBackupID
        )
    )

Add-LabCheck `
    -Name 'GPO XML report created' `
    -Expected 'Report path' `
    -Actual ([string]$Summary.GPOReportPath) `
    -Passed (
        -not [string]::IsNullOrWhiteSpace(
            [string]$Summary.GPOReportPath
        )
    )

# ----------------------------------------------------------
# 31. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $Checks |
    Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Checks |
    Where-Object Status -eq 'FAIL'
).Count

$Total = $Checks.Count

# ----------------------------------------------------------
# 32. Export CSV report
# ----------------------------------------------------------

$Checks |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 33. Generate TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 8 - SCRIPT 06 - SECURITY GPO
============================================================

Host: $HostName
Domain: $DomainName
Domain controller: $DCName
Workstation: $ClientName

Date: $(Get-Date)

GPO:
$($Summary.GPOName)

GPO ID:
$($Summary.GPOID)

Action:
$($Summary.Action)

TARGET OU:
$($Summary.TargetOU)

COMPUTER ACCOUNT:
$($Summary.ComputerDN)

GPO LINK:
$($Summary.LinkOK)

Computer configuration:
$($Summary.ComputerSettingsEnabled)

GPO BACKUP ON SEA-DC1:
$($Summary.BackupDirectory)

Previous GPO backup ID:
$($Summary.PreviousBackupID)

Configured GPO backup ID:
$($Summary.ConfiguredBackupID)

GPO XML report:
$($Summary.GPOReportPath)

VERIFICATION:
Total: $Total
PASS: $Passed
FAIL: $Failed

NOTE:
The report confirms settings in Active Directory GPO.
Client-side application requires separate verification.

"@

$ChecksText = $Checks |
    Format-Table `
        Check, Expected, Actual, Status `
        -AutoSize |
    Out-String -Width 220

($Header + "`r`n" + $ChecksText) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 34. Generate HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    background: #f5f9fb;
    color: #294554;
    margin: 32px;
    line-height: 1.6;
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
</style>
"@

$SafeGPO = [System.Net.WebUtility]::HtmlEncode(
    [string]$Summary.GPOName
)

$SafeOU = [System.Net.WebUtility]::HtmlEncode(
    [string]$Summary.TargetOU
)

$HTMLIntro = @"
<h1>LAB 8 - Security GPO Configuration</h1>

<p><strong>Host:</strong> $HostName</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>GPO:</strong> $SafeGPO</p>
<p><strong>Workstation:</strong> $ClientName</p>
<p><strong>Target OU:</strong> $SafeOU</p>
<p><strong>GPO action:</strong> $($Summary.Action)</p>

<h2>Security configuration checks</h2>
"@

$Checks |
    ConvertTo-Html `
        -Title 'LAB 8 - Security GPO' `
        -Head $CSS `
        -PreContent $HTMLIntro |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 35. Display verification results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - SECURITY GPO RESULTS"
Write-Host "=========================================="
Write-Host ""

$Checks |
    Format-Table -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Host: $HostName"
Write-Host "GPO: $($Summary.GPOName)"
Write-Host "GPO ID: $($Summary.GPOID)"
Write-Host "Action: $($Summary.Action)"
Write-Host "Target OU: $($Summary.TargetOU)"

Write-Host ""
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red

Write-Host ""
Write-Host "Backup on $DCName :"
Write-Host $Summary.BackupDirectory

Write-Host ""
Write-Host "Reports on $HostName :"
Write-Host "CSV: $CSV"
Write-Host "TXT: $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 36. Final validation
# ----------------------------------------------------------

if ($Total -ne 12) {

    throw (
        "Expected 12 verification checks; " +
        "received $Total."
    )
}

if ($Failed -gt 0) {

    throw 'LAB 8 - Security GPO verification failed.'
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - SECURITY GPO CONFIGURED"
Write-Host "==========================================" `
    -ForegroundColor Green
