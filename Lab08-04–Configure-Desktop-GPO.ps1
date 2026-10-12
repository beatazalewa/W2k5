# ==========================================================
# LAB 8 - Script 04 - Configure Desktop GPO
#
# Run on a Hyper-V host as Administrator.
# Windows PowerShell 5.1 and Hyper-V required.
#
# Host name is detected automatically.
#
# Domain: contoso.com
# Domain controller VM: SEA-DC1
#
# GPO:
#   LAB08-Desktop-Finance
#
# Target OU:
#   OU=Uzytkownicy,OU=Finanse,
#   OU=Centrala,DC=contoso,DC=com
#
# User configuration:
#   Disable Control Panel and Windows Settings
#   Remove Run command from Start menu
#
# The script:
#   Verifies domain and target OU
#   Checks the location of ewa.kaczmarek
#   Creates or reuses the target GPO
#   Backs up an existing GPO before modification
#   Configures registry-based user policies
#   Links the GPO to the target OU
#   Verifies registry settings and GPO link
#   Exports CSV, TXT and HTML reports
#
# Does not change Default Domain Policy.
# ==========================================================

[CmdletBinding()]
param(
    [string]$GPOName = 'LAB08-Desktop-Finance'
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$HostName = $env:COMPUTERNAME

$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'

$TargetOU = (
    'OU=Uzytkownicy,' +
    'OU=Finanse,' +
    'OU=Centrala,' +
    'DC=contoso,DC=com'
)

$TestUser = 'ewa.kaczmarek'

$HostReportDir = 'C:\LabReports'
$DCBackupRoot = 'C:\LabReports\LAB08-Backups'

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $HostReportDir `
    "LAB08-Desktop-GPO_$Timestamp.csv"

$TXT = Join-Path $HostReportDir `
    "LAB08-Desktop-GPO_$Timestamp.txt"

$HTML = Join-Path $HostReportDir `
    "LAB08-Desktop-GPO_$Timestamp.html"

$ReportItems = [System.Collections.Generic.List[object]]::new()

# ----------------------------------------------------------
# 2. Helper function
# ----------------------------------------------------------

function Add-Check {

    param(
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [ValidateSet('PASS','FAIL','INFO','REVIEW')]
        [string]$Status
    )

    $ReportItems.Add(
        [PSCustomObject]@{
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = $Status
        }
    )
}

# ----------------------------------------------------------
# 3. Verify host environment
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CONFIGURE DESKTOP GPO"
Write-Host "=========================================="
Write-Host ""

Write-Host "Detected host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host "GPO: $GPOName"
Write-Host "Target OU: $TargetOU"
Write-Host ""

$Identity = (
    [System.Security.Principal.WindowsIdentity]::GetCurrent()
)

$Principal = New-Object `
    System.Security.Principal.WindowsPrincipal `
    -ArgumentList $Identity

$IsAdmin = $Principal.IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator
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
$Result = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 6. Configure GPO inside domain controller
    # ------------------------------------------------------

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList @(
            $DomainName
            $GPOName
            $TargetOU
            $TestUser
            $DCBackupRoot
            $Timestamp
        ) `
        -ScriptBlock {

            param(
                [string]$ExpectedDomain,
                [string]$GPOName,
                [string]$TargetOU,
                [string]$TestUser,
                [string]$BackupRoot,
                [string]$Timestamp
            )

            $ErrorActionPreference = 'Stop'

            # ----------------------------------------------
            # 7. Load management modules
            # ----------------------------------------------

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            Import-Module GroupPolicy `
                -ErrorAction Stop

            # ----------------------------------------------
            # 8. Verify domain
            # ----------------------------------------------

            $Domain = Get-ADDomain `
                -ErrorAction Stop

            if ($Domain.DNSRoot -ine $ExpectedDomain) {

                throw (
                    "Unexpected domain: $($Domain.DNSRoot)"
                )
            }

            # ----------------------------------------------
            # 9. Verify target organizational unit
            # ----------------------------------------------

            $OU = @(
                Get-ADOrganizationalUnit `
                    -LDAPFilter '(objectClass=organizationalUnit)' `
                    -SearchBase $Domain.DistinguishedName `
                    -SearchScope Subtree `
                    -ErrorAction Stop |
                Where-Object {
                    $_.DistinguishedName -ieq $TargetOU
                }
            )

            if ($OU.Count -ne 1) {
                throw "Target OU not found: $TargetOU"
            }

            # ----------------------------------------------
            # 10. Verify test user location
            # ----------------------------------------------

            $User = Get-ADUser `
                -Identity $TestUser `
                -Properties Enabled `
                -ErrorAction Stop

            $UserDN = [string]$User.DistinguishedName

            $UserOU = (
                $UserDN.Substring(
                    $UserDN.IndexOf(',') + 1
                )
            )

            $UserInTargetOU = (
                $UserOU -ieq $TargetOU
            )

            # Stop before changing GPO if the test
            # account is outside the intended OU.

            if (-not $UserInTargetOU) {

                throw (
                    "Test user $TestUser is not in target OU. " +
                    "Current location: $UserOU. " +
                    "Move the account only after confirming " +
                    "the intended OU design."
                )
            }

            # ----------------------------------------------
            # 11. Identify existing GPO
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
                throw 'Multiple matching GPOs were found.'
            }

            # ----------------------------------------------
            # 12. Prepare backup directory
            # ----------------------------------------------

            $BackupDirectory = Join-Path `
                $BackupRoot `
                "LAB08-04_$Timestamp"

            New-Item `
                -ItemType Directory `
                -Path $BackupDirectory `
                -Force `
                -ErrorAction Stop | Out-Null

            # ----------------------------------------------
            # 13. Back up existing GPO
            # ----------------------------------------------

            $PreviousBackupID = ''
            $Action = ''

            if ($ExistingGPO.Count -eq 1) {

                $GPO = $ExistingGPO[0]
                $Action = 'UPDATED'

                $Backup = Backup-GPO `
                    -Guid $GPO.Id `
                    -Domain $ExpectedDomain `
                    -Path $BackupDirectory `
                    -Comment 'LAB08-04 before desktop GPO update' `
                    -ErrorAction Stop

                $PreviousBackupID = [string]$Backup.Id

            }
            else {

                # Create a dedicated policy for this lab.
                $GPO = New-GPO `
                    -Name $GPOName `
                    -Domain $ExpectedDomain `
                    -Comment 'LAB 8 - Finance desktop user restrictions' `
                    -ErrorAction Stop

                $Action = 'CREATED'
            }

            # ----------------------------------------------
            # 14. Configure Control Panel restriction
            # ----------------------------------------------

            # User Configuration:
            # Administrative Templates:
            # Control Panel:
            # Prohibit access to Control Panel
            # and PC settings.

            $ExplorerKey = (
                'HKCU\Software\Microsoft\Windows\' +
                'CurrentVersion\Policies\Explorer'
            )

            Set-GPRegistryValue `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -Key $ExplorerKey `
                -ValueName 'NoControlPanel' `
                -Type DWord `
                -Value 1 `
                -ErrorAction Stop

            # ----------------------------------------------
            # 15. Configure Start menu restriction
            # ----------------------------------------------

            # User Configuration:
            # Administrative Templates:
            # Start Menu and Taskbar:
            # Remove Run menu from Start Menu.

            Set-GPRegistryValue `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -Key $ExplorerKey `
                -ValueName 'NoRun' `
                -Type DWord `
                -Value 1 `
                -ErrorAction Stop

            # ----------------------------------------------
            # 16. Check existing direct GPO link
            # ----------------------------------------------

            $InheritanceBefore = Get-GPInheritance `
                -Target $TargetOU `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $ExistingLinks = @(
                $InheritanceBefore.GpoLinks |
                Where-Object {
                    $_.GpoId -eq $GPO.Id
                }
            )

            $LinkAction = 'UNCHANGED'

            if ($ExistingLinks.Count -eq 0) {

                # Link only this GPO to the Finance users OU.
                # Do not change inheritance or other links.

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

                $Link = $ExistingLinks[0]

                if ($Link.Enabled -ne 'Yes') {

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
            # 17. Verify registry policy values
            # ----------------------------------------------

            $NoControlPanel = Get-GPRegistryValue `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -Key $ExplorerKey `
                -ValueName 'NoControlPanel' `
                -ErrorAction Stop

            $NoRun = Get-GPRegistryValue `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -Key $ExplorerKey `
                -ValueName 'NoRun' `
                -ErrorAction Stop

            $ControlPanelOK = (
                [int]$NoControlPanel.Value -eq 1 -and
                [string]$NoControlPanel.Type -eq 'DWord'
            )

            $NoRunOK = (
                [int]$NoRun.Value -eq 1 -and
                [string]$NoRun.Type -eq 'DWord'
            )

            # ----------------------------------------------
            # 18. Verify GPO link
            # ----------------------------------------------

            $InheritanceAfter = Get-GPInheritance `
                -Target $TargetOU `
                -Domain $ExpectedDomain `
                -ErrorAction Stop

            $VerifiedLinks = @(
                $InheritanceAfter.GpoLinks |
                Where-Object {
                    $_.GpoId -eq $GPO.Id
                }
            )

            $LinkOK = (
                $VerifiedLinks.Count -eq 1 -and
                [string]$VerifiedLinks[0].Enabled -eq 'Yes'
            )

            # ----------------------------------------------
            # 19. Back up configured GPO
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
                -Comment 'LAB08-04 configured desktop GPO' `
                -ErrorAction Stop

            # ----------------------------------------------
            # 20. Generate GPO XML report
            # ----------------------------------------------

            $GPOReportPath = Join-Path `
                $BackupDirectory `
                'Desktop-GPO-Report.xml'

            Get-GPOReport `
                -Guid $GPO.Id `
                -Domain $ExpectedDomain `
                -ReportType Xml `
                -Path $GPOReportPath `
                -ErrorAction Stop

            # ----------------------------------------------
            # 21. Return verification data
            # ----------------------------------------------

            [PSCustomObject]@{
                Computer = $env:COMPUTERNAME
                Domain = [string]$Domain.DNSRoot

                GPOName = $GPOName
                GPOID = [string]$GPO.Id
                Action = $Action

                TargetOU = $TargetOU
                User = $TestUser
                UserDN = $UserDN
                UserInTargetOU = [bool]$UserInTargetOU

                NoControlPanel = [int]$NoControlPanel.Value
                ControlPanelOK = [bool]$ControlPanelOK

                NoRun = [int]$NoRun.Value
                NoRunOK = [bool]$NoRunOK

                LinkAction = $LinkAction
                LinkOK = [bool]$LinkOK

                BackupDirectory = $BackupDirectory
                PreviousBackupID = $PreviousBackupID
                ConfiguredBackupID = (
                    [string]$ConfiguredBackup.Id
                )

                GPOReportPath = $GPOReportPath
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
# 22. Build verification checks
# ----------------------------------------------------------

Add-Check `
    'GPO created or updated' `
    $GPOName `
    $Result.GPOName `
    $(if ($Result.GPOID) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'Target user in Finance OU' `
    'True' `
    ([string]$Result.UserInTargetOU) `
    $(if ($Result.UserInTargetOU) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'Control Panel and Settings restriction' `
    'DWORD 1' `
    "DWORD $($Result.NoControlPanel)" `
    $(if ($Result.ControlPanelOK) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'Remove Run from Start menu' `
    'DWORD 1' `
    "DWORD $($Result.NoRun)" `
    $(if ($Result.NoRunOK) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'GPO link to Finance users OU' `
    'Enabled' `
    ([string]$Result.LinkOK) `
    $(if ($Result.LinkOK) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'Configured GPO backup' `
    'Backup ID' `
    $Result.ConfiguredBackupID `
    $(if ($Result.ConfiguredBackupID) {
        'PASS'
    } else {
        'FAIL'
    })

Add-Check `
    'GPO XML report created' `
    'Report path' `
    $Result.GPOReportPath `
    $(if ($Result.GPOReportPath) {
        'PASS'
    } else {
        'FAIL'
    })

# ----------------------------------------------------------
# 23. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $ReportItems |
    Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $ReportItems |
    Where-Object Status -eq 'FAIL'
).Count

$Total = $ReportItems.Count

# ----------------------------------------------------------
# 24. Export CSV
# ----------------------------------------------------------

$ReportItems |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 25. Generate TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 8 - SCRIPT 04 - DESKTOP GPO
============================================================

Host: $HostName
Domain: $DomainName
Domain controller: $DCName

Date: $(Get-Date)

GPO:
$($Result.GPOName)

GPO ID:
$($Result.GPOID)

Action:
$($Result.Action)

TARGET OU:
$($Result.TargetOU)

TEST USER:
$($Result.User)

USER LOCATION:
$($Result.UserDN)

DESKTOP CONFIGURATION:

NoControlPanel:
$($Result.NoControlPanel)

NoRun:
$($Result.NoRun)

GPO LINK:
$($Result.LinkOK)

Link action:
$($Result.LinkAction)

GPO BACKUP ON SEA-DC1:
$($Result.BackupDirectory)

Previous GPO backup ID:
$($Result.PreviousBackupID)

Configured GPO backup ID:
$($Result.ConfiguredBackupID)

GPO XML report:
$($Result.GPOReportPath)

VERIFICATION:
Total: $Total
PASS: $Passed
FAIL: $Failed

"@

$ChecksText = $ReportItems |
    Format-Table `
        Check, Expected, Actual, Status `
        -AutoSize |
    Out-String -Width 220

($Header + "`r`n" + $ChecksText) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 26. Generate HTML report
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
.summary {
    background: #ffffff;
    border: 1px solid #dce6eb;
    padding: 16px;
    margin-bottom: 24px;
}
</style>
"@

$Escape = [System.Net.WebUtility]

$HTMLIntro = @"
<h1>LAB 8 - Desktop GPO Configuration</h1>

<div class="summary">
<p><strong>Host:</strong> $HostName</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>GPO:</strong> $($Result.GPOName)</p>
<p><strong>Action:</strong> $($Result.Action)</p>
<p><strong>Target OU:</strong> $($Result.TargetOU)</p>
<p><strong>Test user:</strong> $($Result.User)</p>
<p><strong>GPO link enabled:</strong> $($Result.LinkOK)</p>
</div>

<h2>User restrictions</h2>

<p>
Control Panel and Windows Settings: blocked
</p>

<p>
Run command in Start menu: removed
</p>

<h2>Verification checks</h2>
"@

$ReportItems |
    ConvertTo-Html `
        -Title 'LAB 8 - Desktop GPO' `
        -Head $CSS `
        -PreContent $HTMLIntro |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 27. Display results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - DESKTOP GPO RESULTS"
Write-Host "=========================================="
Write-Host ""

$ReportItems |
    Format-Table -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Host: $HostName"
Write-Host "GPO: $($Result.GPOName)"
Write-Host "GPO ID: $($Result.GPOID)"
Write-Host "Action: $($Result.Action)"
Write-Host "Target OU: $($Result.TargetOU)"
Write-Host "Test user: $($Result.User)"

Write-Host ""
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red

Write-Host ""
Write-Host "Backup on $DCName :"
Write-Host $Result.BackupDirectory

Write-Host ""
Write-Host "Reports on $HostName :"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 28. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0) {

    throw 'LAB 8 - Desktop GPO verification failed.'
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - DESKTOP GPO CONFIGURED"
Write-Host "==========================================" `
    -ForegroundColor Green
