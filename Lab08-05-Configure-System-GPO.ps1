# ==========================================================
# LAB 8 - Script 05 - Configure System GPO
# Corrected version
#
# Run on a Hyper-V host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# Workstation: SEA-CL1
#
# GPO: LAB08-System-Workstations
#
# Target OU:
# OU=Stacje robocze,OU=Centrala,DC=contoso,DC=com
#
# Configuration:
#   Windows Update notification mode
#   Restart behavior
#   Windows Consumer Features
#   First sign-in animation
#
# All checks are returned as individual records.
# ==========================================================

[CmdletBinding()]
param(
    [string]$GPOName = 'LAB08-System-Workstations'
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
    "LAB08-System-GPO_$Timestamp.csv"

$TXT = Join-Path $ReportDir `
    "LAB08-System-GPO_$Timestamp.txt"

$HTML = Join-Path $ReportDir `
    "LAB08-System-GPO_$Timestamp.html"

$Results = New-Object `
    'System.Collections.Generic.List[object]'

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
# 3. Verify execution environment
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CONFIGURE SYSTEM GPO"
Write-Host "=========================================="
Write-Host ""

Write-Host "Detected host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host "Client: $ClientName"
Write-Host "GPO: $GPOName"
Write-Host "Target OU: $TargetOU"
Write-Host ""

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal `
    -ArgumentList $Identity

$IsAdmin = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {
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
# 4. Request credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 5. Connect to domain controller
# ----------------------------------------------------------

$Session = $null
$Data = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 6. Configure GPO on domain controller
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
            # 7. Load Active Directory and GPO modules
            # ----------------------------------------------

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            Import-Module GroupPolicy `
                -ErrorAction Stop

            # ----------------------------------------------
            # 8. Verify domain
            # ----------------------------------------------

            $Domain = Get-ADDomain -ErrorAction Stop

            if ($Domain.DNSRoot -ine $ExpectedDomain) {
                throw "Unexpected domain: $($Domain.DNSRoot)"
            }

            # ----------------------------------------------
            # 9. Verify target OU
            # ----------------------------------------------

            $OU = Get-ADOrganizationalUnit `
                -Identity $TargetOU `
                -ErrorAction Stop

            if (
                $OU.DistinguishedName -ine
                $TargetOU
            ) {
                throw 'Target OU does not match.'
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
                    "Workstation $ClientName is not in " +
                    "the expected OU. Current OU: " +
                    $ComputerOU
                )
            }

            # ----------------------------------------------
            # 11. Find existing GPO
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
                throw 'Multiple matching GPOs found.'
            }

            # ----------------------------------------------
            # 12. Prepare backup directory
            # ----------------------------------------------

            $BackupDirectory = Join-Path `
                $BackupRoot `
                "LAB08-05_$Timestamp"

            New-Item `
                -ItemType Directory `
                -Path $BackupDirectory `
                -Force `
                -ErrorAction Stop | Out-Null

            # ----------------------------------------------
            # 13. Back up or create GPO
            # ----------------------------------------------

            $PreviousBackupID = ''

            if ($ExistingGPO.Count -eq 1) {

                $GPO = $ExistingGPO[0]
                $Action = 'UPDATED'

                $PreviousBackup = Backup-GPO `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Path $BackupDirectory `
                    -Comment 'LAB08-05 before system GPO update' `
                    -ErrorAction Stop

                $PreviousBackupID = (
                    [string]$PreviousBackup.Id
                )
            }
            else {

                $GPO = New-GPO `
                    -Name $GPOName `
                    -Domain $ExpectedDomain `
                    -Comment 'LAB 8 - Workstation system configuration' `
                    -ErrorAction Stop

                $Action = 'CREATED'
            }

            # ----------------------------------------------
            # 14. Ensure computer configuration is enabled
            # ----------------------------------------------

            $GPO = Get-GPO `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            if (
                [string]$GPO.GpoStatus -eq
                'ComputerSettingsDisabled'
            ) {

                Set-GPO `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Status AllSettingsEnabled `
                    -ErrorAction Stop | Out-Null
            }

            if (
                [string]$GPO.GpoStatus -eq
                'AllSettingsDisabled'
            ) {

                Set-GPO `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Status AllSettingsEnabled `
                    -ErrorAction Stop | Out-Null
            }

            # ----------------------------------------------
            # 15. Define machine policy values
            # ----------------------------------------------

            $WindowsUpdateAUKey = (
                'HKLM\Software\Policies\Microsoft\' +
                'Windows\WindowsUpdate\AU'
            )

            $CloudContentKey = (
                'HKLM\Software\Policies\Microsoft\' +
                'Windows\CloudContent'
            )

            $SystemPolicyKey = (
                'HKLM\Software\Microsoft\Windows\' +
                'CurrentVersion\Policies\System'
            )

            $Settings = @(
                [PSCustomObject]@{
                    Name = 'NoAutoUpdate'
                    Key = $WindowsUpdateAUKey
                    Expected = 0
                }
                [PSCustomObject]@{
                    Name = 'AUOptions'
                    Key = $WindowsUpdateAUKey
                    Expected = 2
                }
                [PSCustomObject]@{
                    Name = 'NoAutoRebootWithLoggedOnUsers'
                    Key = $WindowsUpdateAUKey
                    Expected = 1
                }
                [PSCustomObject]@{
                    Name = 'DisableWindowsConsumerFeatures'
                    Key = $CloudContentKey
                    Expected = 1
                }
                [PSCustomObject]@{
                    Name = 'EnableFirstLogonAnimation'
                    Key = $SystemPolicyKey
                    Expected = 0
                }
            )

            # ----------------------------------------------
            # 16. Configure all registry policy values
            # ----------------------------------------------

            foreach ($Setting in $Settings) {

                Set-GPRegistryValue `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Key $Setting.Key `
                    -ValueName $Setting.Name `
                    -Type DWord `
                    -Value $Setting.Expected `
                    -ErrorAction Stop
            }

            # ----------------------------------------------
            # 17. Configure GPO link
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
            # 18. Verify registry values
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
            # 19. Verify GPO link
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
            # 20. Verify computer-side GPO status
            # ----------------------------------------------

            $FinalGPO = Get-GPO `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $ComputerSettingsEnabled = (
                [string]$FinalGPO.GpoStatus -in
                @(
                    'AllSettingsEnabled'
                    'UserSettingsDisabled'
                )
            )

            # ----------------------------------------------
            # 21. Back up configured GPO
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
                -Comment 'LAB08-05 configured system GPO' `
                -ErrorAction Stop

            # ----------------------------------------------
            # 22. Export GPO XML report
            # ----------------------------------------------

            $GPOReportPath = Join-Path `
                $BackupDirectory `
                'System-GPO-Report.xml'

            Get-GPOReport `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -ReportType Xml `
                -Path $GPOReportPath `
                -ErrorAction Stop

            # ----------------------------------------------
            # 23. Return flat verification data
            # ----------------------------------------------

            # Return each setting as a separate record.
            # Avoid nested array serialization issues.

            $SettingResults = @(
                foreach ($Item in $Verification) {

                    [PSCustomObject]@{
                        RecordType = 'SETTING'
                        Name = [string]$Item.Name
                        Expected = [int]$Item.Expected
                        Actual = [int]$Item.Actual
                        Passed = [bool]$Item.Passed
                    }
                }
            )

            $Summary = [PSCustomObject]@{
                RecordType = 'SUMMARY'
                Domain = [string]$Domain.DNSRoot
                GPOName = $GPOName
                GPOID = [string]$GPO.Id
                Action = $Action

                TargetOU = $TargetOU
                ClientName = $ClientName
                ComputerDN = $ComputerDN
                ComputerInTargetOU = [bool]$ComputerInTargetOU

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

            # Use separate output objects.
            $Summary

            foreach ($Item in $SettingResults) {
                $Item
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
# 24. Separate summary and setting records
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

if ($SettingRecords.Count -ne 5) {
    throw (
        "Expected five setting records; received " +
        $SettingRecords.Count
    )
}

$Summary = $SummaryRecords[0]

# ----------------------------------------------------------
# 25. Verify expected setting names
# ----------------------------------------------------------

$ExpectedNames = @(
    'NoAutoUpdate'
    'AUOptions'
    'NoAutoRebootWithLoggedOnUsers'
    'DisableWindowsConsumerFeatures'
    'EnableFirstLogonAnimation'
)

$ActualNames = @(
    $SettingRecords |
    ForEach-Object {
        [string]$_.Name
    }
)

foreach ($ExpectedName in $ExpectedNames) {

    $Matches = @(
        $ActualNames |
        Where-Object {
            $_ -eq $ExpectedName
        }
    )

    if ($Matches.Count -ne 1) {
        throw (
            "Missing or duplicated verification record: " +
            $ExpectedName
        )
    }
}

# ----------------------------------------------------------
# 26. Build verification checks
# ----------------------------------------------------------

Add-Check `
    -Check 'GPO created or updated' `
    -Expected $GPOName `
    -Actual $Summary.GPOName `
    -Status $(if (
        $Summary.GPOID -and
        $Summary.GPOName -eq $GPOName
    ) {
        'PASS'
    }
    else {
        'FAIL'
    })

Add-Check `
    -Check 'SEA-CL1 in workstation OU' `
    -Expected 'True' `
    -Actual ([string]$Summary.ComputerInTargetOU) `
    -Status $(if ($Summary.ComputerInTargetOU) {
        'PASS'
    }
    else {
        'FAIL'
    })

foreach ($Setting in $SettingRecords) {

    $Status = if ($Setting.Passed -eq $true) {
        'PASS'
    }
    else {
        'FAIL'
    }

    Add-Check `
        -Check ([string]$Setting.Name) `
        -Expected "DWORD $($Setting.Expected)" `
        -Actual "DWORD $($Setting.Actual)" `
        -Status $Status
}

Add-Check `
    -Check 'GPO link to workstation OU' `
    -Expected 'Enabled' `
    -Actual ([string]$Summary.LinkOK) `
    -Status $(if ($Summary.LinkOK) {
        'PASS'
    }
    else {
        'FAIL'
    })

Add-Check `
    -Check 'Computer configuration enabled' `
    -Expected 'True' `
    -Actual ([string]$Summary.ComputerSettingsEnabled) `
    -Status $(if ($Summary.ComputerSettingsEnabled) {
        'PASS'
    }
    else {
        'FAIL'
    })

Add-Check `
    -Check 'Configured GPO backup' `
    -Expected 'Backup ID' `
    -Actual $Summary.ConfiguredBackupID `
    -Status $(if ($Summary.ConfiguredBackupID) {
        'PASS'
    }
    else {
        'FAIL'
    })

Add-Check `
    -Check 'GPO XML report created' `
    -Expected 'Report path' `
    -Actual $Summary.GPOReportPath `
    -Status $(if ($Summary.GPOReportPath) {
        'PASS'
    }
    else {
        'FAIL'
    })

# ----------------------------------------------------------
# 27. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $Results |
    Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Results |
    Where-Object Status -eq 'FAIL'
).Count

$Total = $Results.Count

# ----------------------------------------------------------
# 28. Export CSV report
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 29. Create TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 8 - SCRIPT 05 - SYSTEM GPO
============================================================

Host: $HostName
Domain: $DomainName
Domain controller: $DCName

Date: $(Get-Date)

GPO:
$($Summary.GPOName)

GPO ID:
$($Summary.GPOID)

Action:
$($Summary.Action)

TARGET OU:
$($Summary.TargetOU)

WORKSTATION:
$($Summary.ClientName)

COMPUTER ACCOUNT:
$($Summary.ComputerDN)

GPO LINK:
$($Summary.LinkOK)

COMPUTER CONFIGURATION:
$($Summary.ComputerSettingsEnabled)

GPO BACKUP ON SEA-DC1:
$($Summary.BackupDirectory)

Previous GPO backup:
$($Summary.PreviousBackupID)

Configured GPO backup:
$($Summary.ConfiguredBackupID)

GPO XML report:
$($Summary.GPOReportPath)

VERIFICATION:
Total: $Total
PASS: $Passed
FAIL: $Failed

NOTE:
This report verifies the GPO configuration and link.
Client-side application must be verified separately.

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
# 30. Create HTML report
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
.summary {
    background: #ffffff;
    border: 1px solid #dce6eb;
    padding: 16px;
    margin-bottom: 24px;
}
</style>
"@

$SafeGPOName = [System.Net.WebUtility]::HtmlEncode(
    [string]$Summary.GPOName
)

$SafeTargetOU = [System.Net.WebUtility]::HtmlEncode(
    [string]$Summary.TargetOU
)

$HTMLIntro = @"
<h1>LAB 8 - System GPO Configuration</h1>

<div class="summary">
<p><strong>Host:</strong> $HostName</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>GPO:</strong> $SafeGPOName</p>
<p><strong>Action:</strong> $($Summary.Action)</p>
<p><strong>Target OU:</strong> $SafeTargetOU</p>
<p><strong>Workstation:</strong> $ClientName</p>
<p><strong>GPO link enabled:</strong> $($Summary.LinkOK)</p>
<p><strong>Computer configuration enabled:</strong> $($Summary.ComputerSettingsEnabled)</p>
</div>

<h2>System configuration checks</h2>
"@

$Results |
    ConvertTo-Html `
        -Title 'LAB 8 - System GPO' `
        -Head $CSS `
        -PreContent $HTMLIntro |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 31. Display final results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - SYSTEM GPO RESULTS"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Host: $HostName"
Write-Host "GPO: $($Summary.GPOName)"
Write-Host "GPO ID: $($Summary.GPOID)"
Write-Host "Action: $($Summary.Action)"
Write-Host "Target OU: $($Summary.TargetOU)"
Write-Host "Workstation: $($Summary.ClientName)"

Write-Host ""
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red

Write-Host ""
Write-Host "Backup on $DCName :"
Write-Host $Summary.BackupDirectory

Write-Host ""
Write-Host "Reports on $HostName :"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 32. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0) {
    throw 'LAB 8 - System GPO verification failed.'
}

if ($Total -ne 11) {
    throw (
        "Expected 11 verification checks; received $Total."
    )
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - SYSTEM GPO CONFIGURED"
Write-Host "==========================================" `
    -ForegroundColor Green
