#requires -Version 5.1
<#
LAB 9 - Script 02 - Configure Group Policy Objects
Run on the Hyper-V host in elevated Windows PowerShell 5.1.
Target domain: contoso.com; target DC virtual machine: SEA-DC1.
All guest-side operations are performed using PowerShell Direct.
#>
[CmdletBinding()]
param(
    [string]$DomainName = 'contoso.com',
    [string]$DCName = 'SEA-DC1',
    [string]$ReportDir = 'C:\LabReports'
)

$ErrorActionPreference = 'Stop'
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$ComputerName = $env:COMPUTERNAME
$CsvPath = Join-Path $ReportDir "LAB09-Configured-GPOs_$Timestamp.csv"
$TxtPath = Join-Path $ReportDir "LAB09-Configured-GPOs_$Timestamp.txt"
$HtmlPath = Join-Path $ReportDir "LAB09-Configured-GPOs_$Timestamp.html"

# Verify host elevation and Hyper-V access.
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator on the Hyper-V host.'
}
Import-Module Hyper-V -ErrorAction Stop
$VM = Get-VM -Name $DCName -ErrorAction Stop
if ($VM.State -ne 'Running') { throw "The VM '$DCName' must be running." }
New-Item -ItemType Directory -Path $ReportDir -Force -ErrorAction Stop | Out-Null

Write-Host "`nLAB 9 - GPO CONFIGURATION" -ForegroundColor Cyan
Write-Host "Host: $ComputerName | VM: $DCName | Domain: $DomainName"
$Credential = Get-Credential -UserName 'CONTOSO\Administrator' -Message 'Enter domain administrator credentials for SEA-DC1'
if ($null -eq $Credential) { throw 'Credentials are required.' }

$Session = $null
try {
    $Session = New-PSSession -VMName $DCName -Credential $Credential -ErrorAction Stop

    $RawData = @(
        Invoke-Command -Session $Session -ArgumentList $DomainName, $Timestamp -ErrorAction Stop -ScriptBlock {
            param([string]$ExpectedDomain, [string]$RunTimestamp)
            $ErrorActionPreference = 'Stop'
            Import-Module ActiveDirectory -ErrorAction Stop
            Import-Module GroupPolicy -ErrorAction Stop

            $Domain = Get-ADDomain -ErrorAction Stop
            if ($Domain.DNSRoot -ine $ExpectedDomain) {
                throw "Connected to unexpected domain: $($Domain.DNSRoot)"
            }
            $DomainDN = $Domain.DistinguishedName

            # The backup directory exists inside SEA-DC1, not on the host.
            $GuestBackupRoot = 'C:\LabReports\LAB09-Backups'
            New-Item -ItemType Directory -Path $GuestBackupRoot -Force -ErrorAction Stop | Out-Null

            $Definitions = @(
                [pscustomobject]@{
                    Name='LAB09-Users-Finance'; Scope='User';
                    OU="OU=Uzytkownicy,OU=Finanse,OU=Centrala,$DomainDN";
                    Key='HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer';
                    ValueName='NoRecentDocsHistory'; Value=1;
                    Description='Disable recently opened documents history'
                }
                [pscustomobject]@{
                    Name='LAB09-Admin-Accounts'; Scope='User';
                    OU="OU=Konta administracyjne,OU=Centrala,$DomainDN";
                    Key='HKCU\Software\Policies\Microsoft\Windows NT\Terminal Services';
                    ValueName='DisablePasswordSaving'; Value=1;
                    Description='Prevent saved passwords in Remote Desktop client'
                }
                [pscustomobject]@{
                    Name='LAB09-Workstations'; Scope='Computer';
                    OU="OU=Stacje robocze,OU=Centrala,$DomainDN";
                    Key='HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer';
                    ValueName='NoDriveTypeAutoRun'; Value=255;
                    Description='Disable AutoRun on all drive types'
                }
                [pscustomobject]@{
                    Name='LAB09-Member-Servers'; Scope='Computer';
                    OU="OU=Serwery,OU=Centrala,$DomainDN";
                    Key='HKLM\Software\Policies\Microsoft\Windows\EventLog\Application';
                    ValueName='MaxSize'; Value=33554432;
                    Description='Set Application log maximum size to 32 MiB'
                }
                [pscustomobject]@{
                    Name='LAB09-Domain-Controllers'; Scope='Computer';
                    OU="OU=Domain Controllers,$DomainDN";
                    Key='HKLM\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging';
                    ValueName='EnableScriptBlockLogging'; Value=1;
                    Description='Enable PowerShell Script Block Logging'
                }
            )

            # Validate the five target OUs BEFORE modifying any GPO.
            foreach ($Definition in $Definitions) {
                $null = Get-ADOrganizationalUnit -Identity $Definition.OU -ErrorAction Stop
            }

            # Confirm that the computer accounts reside in their expected OUs.
            $ComputerTargets = @(
                @{ Name='SEA-CL1'; OU="OU=Stacje robocze,OU=Centrala,$DomainDN" }
                @{ Name='SEA-SRV1'; OU="OU=Serwery,OU=Centrala,$DomainDN" }
                @{ Name='SEA-SRV2'; OU="OU=Serwery,OU=Centrala,$DomainDN" }
                @{ Name='SEA-DC1'; OU="OU=Domain Controllers,$DomainDN" }
            )
            foreach ($Target in $ComputerTargets) {
                $Computer = Get-ADComputer -Identity $Target.Name -ErrorAction Stop
                $ParentDN = ($Computer.DistinguishedName -split ',', 2)[1]
                if ($ParentDN -ine $Target.OU) {
                    throw "Computer $($Target.Name) is located in '$ParentDN', expected '$($Target.OU)'. No GPO was modified."
                }
            }

            # Administrative test accounts are optional for creating the policy.
            $AdminOU = "OU=Konta administracyjne,OU=Centrala,$DomainDN"
            $AdminUserCount = @(Get-ADUser -Filter * -SearchBase $AdminOU -SearchScope OneLevel).Count
            if ($AdminUserCount -eq 0) {
                Write-Warning 'No direct administrative user accounts found in the target OU. User-side validation requires a test account.'
            }

            $ExistingAll = @(Get-GPO -All -Domain $ExpectedDomain)
            foreach ($Definition in $Definitions) {
                if (@($ExistingAll | Where-Object { $_.DisplayName -eq $Definition.Name }).Count -gt 1) {
                    throw "Duplicate GPO display name: $($Definition.Name)"
                }
            }

            foreach ($Definition in $Definitions) {
                $Name = $Definition.Name
                Write-Host "Configuring: $Name" -ForegroundColor Cyan
                $Action = 'NONE'
                $LinkAction = 'NONE'
                $BackupPath = ''
                $GPOId = ''
                $ActualValue = $null
                $ValueOK = $false
                $LinkOK = $false
                $ErrorText = ''

                try {
                    $Existing = @(Get-GPO -All -Domain $ExpectedDomain | Where-Object DisplayName -eq $Name)
                    $BackupPath = Join-Path $GuestBackupRoot "${Name}_$RunTimestamp"
                    New-Item -ItemType Directory -Path $BackupPath -Force -ErrorAction Stop | Out-Null

                    if ($Existing.Count -eq 1) {
                        $GPO = $Existing[0]
                        $Action = 'UPDATED'
                        # Existing policy must be backed up before modification.
                        $null = Backup-GPO -Guid $GPO.Id -Domain $ExpectedDomain -Path $BackupPath -Comment 'Before LAB09-02 update' -ErrorAction Stop
                    }
                    else {
                        $GPO = New-GPO -Name $Name -Domain $ExpectedDomain -Comment $Definition.Description -ErrorAction Stop
                        $Action = 'CREATED'
                    }
                    $GPOId = [string]$GPO.Id

                    $CurrentGPO = Get-GPO -Guid $GPO.Id -Domain $ExpectedDomain -ErrorAction Stop
                    $Status = [string]$CurrentGPO.GpoStatus
                    $ScopeEnabled = if ($Definition.Scope -eq 'User') {
                        $Status -in @('AllSettingsEnabled','ComputerSettingsDisabled')
                    }
                    else {
                        $Status -in @('AllSettingsEnabled','UserSettingsDisabled')
                    }
                    if (-not $ScopeEnabled) {
                        throw "The $($Definition.Scope) portion of '$Name' is disabled: $Status"
                    }

                    $SetParameters = @{
                        Guid=$GPO.Id; Domain=$ExpectedDomain;
                        Key=$Definition.Key; ValueName=$Definition.ValueName;
                        Type='DWord'; Value=[int]$Definition.Value;
                        ErrorAction='Stop'
                    }
                    # CRITICAL: suppress the cmdlet output to avoid doubling result records.
                    Set-GPRegistryValue @SetParameters | Out-Null

                    $GetParameters = @{
                        Guid=$GPO.Id; Domain=$ExpectedDomain;
                        Key=$Definition.Key; ValueName=$Definition.ValueName;
                        ErrorAction='Stop'
                    }
                    $Actual = Get-GPRegistryValue @GetParameters
                    $ActualValue = [int]$Actual.Value
                    $ValueOK = ($ActualValue -eq [int]$Definition.Value -and [string]$Actual.Type -eq 'DWord')

                    $Inheritance = Get-GPInheritance -Target $Definition.OU -Domain $ExpectedDomain -ErrorAction Stop
                    $ExistingLinks = @($Inheritance.GpoLinks | Where-Object { [string]$_.GpoId -eq $GPOId })
                    if ($ExistingLinks.Count -eq 0) {
                        New-GPLink -Guid $GPO.Id -Domain $ExpectedDomain -Target $Definition.OU -LinkEnabled Yes -Enforced No -ErrorAction Stop | Out-Null
                        $LinkAction = 'CREATED'
                    }
                    elseif ($ExistingLinks.Count -eq 1) {
                        if ([string]$ExistingLinks[0].Enabled -notin @('True','Yes')) {
                            Set-GPLink -Guid $GPO.Id -Domain $ExpectedDomain -Target $Definition.OU -LinkEnabled Yes -ErrorAction Stop | Out-Null
                            $LinkAction = 'ENABLED'
                        }
                        else {
                            $LinkAction = 'UNCHANGED'
                        }
                    }
                    else {
                        throw "Multiple direct links found for '$Name'."
                    }

                    $FinalInheritance = Get-GPInheritance -Target $Definition.OU -Domain $ExpectedDomain -ErrorAction Stop
                    $FinalLinks = @($FinalInheritance.GpoLinks | Where-Object { [string]$_.GpoId -eq $GPOId })
                    $LinkOK = ($FinalLinks.Count -eq 1 -and [string]$FinalLinks[0].Enabled -in @('True','Yes'))

                    $ConfiguredPath = Join-Path $BackupPath 'Configured'
                    New-Item -ItemType Directory -Path $ConfiguredPath -Force -ErrorAction Stop | Out-Null
                    $null = Backup-GPO -Guid $GPO.Id -Domain $ExpectedDomain -Path $ConfiguredPath -Comment 'After LAB09-02 update' -ErrorAction Stop
                    Get-GPOReport -Guid $GPO.Id -Domain $ExpectedDomain -ReportType Xml -Path (Join-Path $BackupPath 'GPO-Report.xml') -ErrorAction Stop | Out-Null
                }
                catch {
                    $ErrorText = $_.Exception.Message
                }

                # Output EXACTLY ONE report object for each policy.
                [pscustomobject]@{
                    RecordType='LAB09_GPO_RESULT'
                    Name=$Name
                    Scope=$Definition.Scope
                    Action=$Action
                    GPOID=$GPOId
                    OU=$Definition.OU
                    Description=$Definition.Description
                    Setting=$Definition.ValueName
                    Expected=[int]$Definition.Value
                    Actual=$ActualValue
                    ValueOK=[bool]$ValueOK
                    LinkAction=$LinkAction
                    LinkOK=[bool]$LinkOK
                    AdminTestUsers=$AdminUserCount
                    BackupDirectory=$BackupPath
                    Status=if ($ValueOK -and $LinkOK -and -not $ErrorText) { 'PASS' } else { 'FAIL' }
                    ErrorText=$ErrorText
                }
            }
        }
    )
}
finally {
    if ($null -ne $Session) { Remove-PSSession -Session $Session -ErrorAction SilentlyContinue }
}

# PowerShell Direct can serialize and return unexpected pipeline objects.
# Keep only explicitly tagged report records; do not count GPO cmdlet output.
$Data = @($RawData | Where-Object { $_.RecordType -eq 'LAB09_GPO_RESULT' })
if ($Data.Count -ne 5) {
    $Types = @($RawData | ForEach-Object { $_.GetType().FullName }) -join ', '
    throw "Expected five LAB09_GPO_RESULT records; received $($Data.Count) (raw: $($RawData.Count)). Types: $Types"
}
$Names = @('LAB09-Users-Finance','LAB09-Admin-Accounts','LAB09-Workstations','LAB09-Member-Servers','LAB09-Domain-Controllers')
foreach ($ExpectedName in $Names) {
    if (@($Data | Where-Object Name -eq $ExpectedName).Count -ne 1) {
        throw "Expected exactly one result for '$ExpectedName'."
    }
}

$Passed = @($Data | Where-Object Status -eq 'PASS').Count
$Failed = @($Data | Where-Object Status -eq 'FAIL').Count
$Data | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

$TableText = $Data | Format-Table Name,Scope,Action,Setting,Actual,LinkOK,Status -AutoSize | Out-String -Width 240
$DetailText = $Data | Format-List * | Out-String -Width 240
@"
LAB 9 - GPO CONFIGURATION
Host: $ComputerName
Domain: $DomainName
Domain controller VM: $DCName
Date: $(Get-Date)
PASS: $Passed
FAIL: $Failed

$TableText

DETAILS:
$DetailText

NOTE: GPO backups and XML files are stored INSIDE the SEA-DC1 VM
under C:\LabReports\LAB09-Backups. The CSV/TXT/HTML reports are
stored on the Hyper-V host under $ReportDir.

This confirms GPO configuration and OU links only. Use LAB09-03
with gpupdate and gpresult to verify effective client-side policy.
"@ | Out-File -FilePath $TxtPath -Encoding UTF8

$Css = @'
<style>
body{font-family:Arial,sans-serif;margin:30px;background:#f5f9fb;color:#294554}
h1{color:#146393}table{border-collapse:collapse;width:100%;background:white}
th{background:#146393;color:white;text-align:left}
th,td{padding:8px;border:1px solid #dce6eb}
</style>
'@
$Data | Select-Object Name,Scope,Action,Setting,Expected,Actual,LinkOK,Status,ErrorText |
    ConvertTo-Html -Title 'LAB 9 GPO Configuration' -Head $Css -PreContent "<h1>LAB 9 - GPO Configuration</h1><p>PASS: $Passed | FAIL: $Failed</p>" |
    Out-File -FilePath $HtmlPath -Encoding UTF8

Write-Host "`nLAB 9 - RESULTS" -ForegroundColor Cyan
$Data | Format-Table Name,Scope,Action,Setting,Actual,LinkOK,Status -AutoSize | Out-Host
Write-Host "PASS: $Passed | FAIL: $Failed"
Write-Host "Host CSV:  $CsvPath"
Write-Host "Host TXT:  $TxtPath"
Write-Host "Host HTML: $HtmlPath"
Write-Host 'Guest backups: SEA-DC1\C:\LabReports\LAB09-Backups'
if ($Failed -gt 0) {
    $Data | Where-Object Status -eq 'FAIL' | Format-List Name,ErrorText | Out-Host
    throw "LAB09-02 failed for $Failed GPO(s). Review the report."
}
Write-Host 'LAB09-02: FIVE GPOS CONFIGURED' -ForegroundColor Green
