#requires -Version 5.1
<#
.SYNOPSIS
    LAB 9 - Script 03 - Verify GPO configuration, OU links and client application.
.DESCRIPTION
    Run on the Hyper-V host with Windows PowerShell 5.1 as Administrator.
    Reads five LAB09 GPOs through PowerShell Direct on SEA-DC1.
    Runs gpupdate and gpresult on target VMs and compares local policy values.
    User-side GPO application must be checked from a user logon session.
    No GPOs, AD accounts or OU links are modified by this script.
    gpupdate does initiate a Group Policy refresh on target computers.
#>
[CmdletBinding()]
param(
    [string]$DomainName = 'contoso.com',
    [string]$DCName = 'SEA-DC1',
    [string]$ReportDir = 'C:\LabReports',
    [switch]$SkipGPUpdate
)

$ErrorActionPreference = 'Stop'
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$CsvPath = Join-Path $ReportDir "LAB09-03-Results_$Timestamp.csv"
$TxtPath = Join-Path $ReportDir "LAB09-03-Results_$Timestamp.txt"
$HtmlPath = Join-Path $ReportDir "LAB09-03-Results_$Timestamp.html"
$EvidenceDir = Join-Path $ReportDir "LAB09-03-Evidence_$Timestamp"
$Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Area,[string]$Target,[string]$Check,[string]$Expected,
          [string]$Actual,[ValidateSet('PASS','FAIL','REVIEW')][string]$Status,
          [string]$Details='')
    $script:Results.Add([pscustomobject]@{
        Area=$Area; Target=$Target; Check=$Check; Expected=$Expected
        Actual=$Actual; Status=$Status; Details=$Details
    })
}

# Validate local prerequisites.
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator on the Hyper-V host.'
}
Import-Module Hyper-V -ErrorAction Stop
New-Item -Path $EvidenceDir -ItemType Directory -Force -ErrorAction Stop | Out-Null

$Definitions = @(
    [pscustomobject]@{Name='LAB09-Users-Finance'; Scope='User'; OU='OU=Uzytkownicy,OU=Finanse,OU=Centrala,DC=contoso,DC=com'; Key='HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; ValueName='NoRecentDocsHistory'; Value=1; VM=''; RegistryPath=''},
    [pscustomobject]@{Name='LAB09-Admin-Accounts'; Scope='User'; OU='OU=Konta administracyjne,OU=Centrala,DC=contoso,DC=com'; Key='HKCU\Software\Policies\Microsoft\Windows NT\Terminal Services'; ValueName='DisablePasswordSaving'; Value=1; VM=''; RegistryPath=''},
    [pscustomobject]@{Name='LAB09-Workstations'; Scope='Computer'; OU='OU=Stacje robocze,OU=Centrala,DC=contoso,DC=com'; Key='HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; ValueName='NoDriveTypeAutoRun'; Value=255; VM='SEA-CL1'; RegistryPath='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'},
    [pscustomobject]@{Name='LAB09-Member-Servers'; Scope='Computer'; OU='OU=Serwery,OU=Centrala,DC=contoso,DC=com'; Key='HKLM\Software\Policies\Microsoft\Windows\EventLog\Application'; ValueName='MaxSize'; Value=33554432; VM='SEA-SRV1,SEA-SRV2'; RegistryPath='HKLM:\Software\Policies\Microsoft\Windows\EventLog\Application'},
    [pscustomobject]@{Name='LAB09-Domain-Controllers'; Scope='Computer'; OU='OU=Domain Controllers,DC=contoso,DC=com'; Key='HKLM\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; ValueName='EnableScriptBlockLogging'; Value=1; VM='SEA-DC1'; RegistryPath='HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'}
)

Write-Host 'LAB09-03 - Verify GPO configuration, linking and application' -ForegroundColor Cyan
$DomainCredential = Get-Credential -UserName 'CONTOSO\Administrator' -Message 'Credential for SEA-DC1 (PowerShell Direct)'
if ($null -eq $DomainCredential) { throw 'No credentials supplied.' }

# Collect authoritative policy state from the domain controller.
$DCSession = $null
try {
    $DCSession = New-PSSession -VMName $DCName -Credential $DomainCredential -ErrorAction Stop
    $DomainRecords = @(Invoke-Command -Session $DCSession -ArgumentList (,$Definitions),$DomainName -ScriptBlock {
        param($Items,[string]$ExpectedDomain)
        $ErrorActionPreference = 'Stop'
        Import-Module ActiveDirectory -ErrorAction Stop
        Import-Module GroupPolicy -ErrorAction Stop
        $ActualDomain = (Get-ADDomain -ErrorAction Stop).DNSRoot
        if ($ActualDomain -ine $ExpectedDomain) { throw "Unexpected domain: $ActualDomain" }
        foreach ($Def in $Items) {
            $Errors = New-Object System.Collections.Generic.List[string]
            $Gpo = $null; $CurrentValue = $null; $ValueOK = $false
            $LinkOK = $false; $SideOK = $false; $OUOK = $false
            $GpoOK = $false
            try { $null = Get-ADOrganizationalUnit -Identity $Def.OU -ErrorAction Stop; $OUOK = $true }
            catch { $Errors.Add("OU: $($_.Exception.Message)") }
            try {
                $Gpo = Get-GPO -Name $Def.Name -Domain $ExpectedDomain -ErrorAction Stop
                $GpoOK = $true
                $Status = [string]$Gpo.GpoStatus
                $SideOK = if ($Def.Scope -eq 'User') {
                    $Status -in @('AllSettingsEnabled','ComputerSettingsDisabled')
                } else { $Status -in @('AllSettingsEnabled','UserSettingsDisabled') }
                $Setting = Get-GPRegistryValue -Guid $Gpo.Id -Domain $ExpectedDomain -Key $Def.Key -ValueName $Def.ValueName -ErrorAction Stop
                $CurrentValue = [string]$Setting.Value
                $ValueOK = ([int64]$Setting.Value -eq [int64]$Def.Value -and [string]$Setting.Type -eq 'DWord')
                if ($OUOK) {
                    $Inheritance = Get-GPInheritance -Target $Def.OU -Domain $ExpectedDomain -ErrorAction Stop
                    $Links = @($Inheritance.GpoLinks | Where-Object { [string]$_.GpoId -eq [string]$Gpo.Id })
                    $LinkOK = ($Links.Count -eq 1 -and [string]$Links[0].Enabled -in @('True','Yes'))
                }
            } catch { $Errors.Add($_.Exception.Message) }
            [pscustomobject]@{
                Name=[string]$Def.Name; OUOK=[bool]$OUOK; GpoOK=[bool]$GpoOK
                SideOK=[bool]$SideOK; ValueOK=[bool]$ValueOK; LinkOK=[bool]$LinkOK
                ActualValue=$CurrentValue; ErrorText=($Errors -join ' | ')
            }
        }
        foreach ($Name in @('SEA-DC1','SEA-SRV1','SEA-SRV2','SEA-CL1')) {
            $DN=''; $Found=$false
            try { $Computer=Get-ADComputer -Identity $Name -ErrorAction Stop; $DN=$Computer.DistinguishedName; $Found=$true }
            catch { $DN=$_.Exception.Message }
            [pscustomobject]@{Name="COMPUTER::$Name"; OUOK=$Found; GpoOK=$false; SideOK=$false; ValueOK=$false; LinkOK=$false; ActualValue=$DN; ErrorText=''}
        }
        foreach ($Name in @('ewa.kaczmarek')) {
            $DN=''; $Found=$false
            try { $User=Get-ADUser -Identity $Name -ErrorAction Stop; $DN=$User.DistinguishedName; $Found=$true }
            catch { $DN=$_.Exception.Message }
            [pscustomobject]@{Name="USER::$Name"; OUOK=$Found; GpoOK=$false; SideOK=$false; ValueOK=$false; LinkOK=$false; ActualValue=$DN; ErrorText=''}
        }
    } -ErrorAction Stop)
} finally { if ($DCSession) { Remove-PSSession $DCSession } }

foreach ($Def in $Definitions) {
    $Found = @($DomainRecords | Where-Object { $_.Name -eq $Def.Name })
    if ($Found.Count -ne 1) {
        Add-Result 'Domain' $Def.Name 'GPO response' 'Exactly one record' ([string]$Found.Count) 'FAIL'
        continue
    }
    $R=$Found[0]
    foreach ($Check in @(
        @{Label='Target OU exists'; OK=$R.OUOK; Expected='True'; Actual=[string]$R.OUOK},
        @{Label='GPO exists'; OK=$R.GpoOK; Expected='True'; Actual=[string]$R.GpoOK},
        @{Label='Relevant policy section enabled'; OK=$R.SideOK; Expected='True'; Actual=[string]$R.SideOK},
        @{Label="Registry setting: $($Def.ValueName)"; OK=$R.ValueOK; Expected=[string]$Def.Value; Actual=[string]$R.ActualValue},
        @{Label='Direct OU link enabled'; OK=$R.LinkOK; Expected='True'; Actual=[string]$R.LinkOK}
    )) {
        Add-Result 'Domain' $Def.Name $Check.Label $Check.Expected $Check.Actual $(if ($Check.OK) {'PASS'} else {'FAIL'}) ([string]$R.ErrorText)
    }
}

$OUByComputer = @{
    'SEA-CL1'='OU=Stacje robocze,OU=Centrala,DC=contoso,DC=com'
    'SEA-SRV1'='OU=Serwery,OU=Centrala,DC=contoso,DC=com'
    'SEA-SRV2'='OU=Serwery,OU=Centrala,DC=contoso,DC=com'
    'SEA-DC1'='OU=Domain Controllers,DC=contoso,DC=com'
}
foreach ($Name in $OUByComputer.Keys) {
    $R=@($DomainRecords | Where-Object { $_.Name -eq "COMPUTER::$Name" })
    $DN=if ($R.Count -eq 1) { [string]$R[0].ActualValue } else { 'Not returned' }
    $Parent=if ($DN -match '^[^,]+,(.+)$') { $Matches[1] } else { '' }
    Add-Result 'AD placement' $Name 'Computer account OU' $OUByComputer[$Name] $Parent $(if ($Parent -ieq $OUByComputer[$Name]) {'PASS'} else {'FAIL'})
}
$FinanceR=@($DomainRecords | Where-Object { $_.Name -eq 'USER::ewa.kaczmarek' })
$FinanceDN=if ($FinanceR.Count -eq 1) { [string]$FinanceR[0].ActualValue } else { 'Not returned' }
$FinanceParent=if ($FinanceDN -match '^[^,]+,(.+)$') { $Matches[1] } else { '' }
$FinanceExpected='OU=Uzytkownicy,OU=Finanse,OU=Centrala,DC=contoso,DC=com'
Add-Result 'AD placement' 'ewa.kaczmarek' 'User account OU' $FinanceExpected $FinanceParent $(if ($FinanceParent -ieq $FinanceExpected) {'PASS'} else {'FAIL'})

# Client-side verification. A separate credential prompt accommodates local admin on SEA-CL1.
$Targets = @(
    [pscustomobject]@{VM='SEA-DC1'; GPO='LAB09-Domain-Controllers'; Def='LAB09-Domain-Controllers'},
    [pscustomobject]@{VM='SEA-SRV1'; GPO='LAB09-Member-Servers'; Def='LAB09-Member-Servers'},
    [pscustomobject]@{VM='SEA-SRV2'; GPO='LAB09-Member-Servers'; Def='LAB09-Member-Servers'},
    [pscustomobject]@{VM='SEA-CL1'; GPO='LAB09-Workstations'; Def='LAB09-Workstations'}
)
$CredentialByVM = @{'SEA-DC1'=$DomainCredential; 'SEA-SRV1'=$DomainCredential; 'SEA-SRV2'=$DomainCredential}
Write-Host 'Enter credentials for SEA-CL1 (the account usable through PowerShell Direct).' -ForegroundColor Yellow
$CredentialByVM['SEA-CL1'] = Get-Credential -Message 'SEA-CL1 guest credentials (e.g. local Admin)'

foreach ($Target in $Targets) {
    $Name=$Target.VM
    $Def=@($Definitions | Where-Object Name -eq $Target.Def)[0]
    Write-Host "Verifying $Name ..." -ForegroundColor Cyan
    $VM=Get-VM -Name $Name -ErrorAction SilentlyContinue
    if (-not $VM -or $VM.State -ne 'Running') {
        Add-Result 'Client' $Name 'VM state' 'Running' 'Not running or missing' 'FAIL'
        continue
    }
    $Session=$null
    try {
        $Session=New-PSSession -VMName $Name -Credential $CredentialByVM[$Name] -ErrorAction Stop
        $Readback=@(Invoke-Command -Session $Session -ArgumentList $Target.GPO,$Def.RegistryPath,$Def.ValueName,([int64]$Def.Value),([bool]$SkipGPUpdate) -ScriptBlock {
            param([string]$ExpectedGPO,[string]$RegistryPath,[string]$ValueName,[long]$ExpectedValue,[bool]$NoUpdate)
            $UpdateExit=$null; $UpdateText='Skipped by request'
            if (-not $NoUpdate) {
                $UpdateText=(& gpupdate.exe /target:computer /force /wait:120 2>&1 | Out-String)
                $UpdateExit=$LASTEXITCODE
            }
            $ResultText=(& gpresult.exe /scope computer /r 2>&1 | Out-String)
            $ResultExit=$LASTEXITCODE
            $XmlPath=Join-Path $env:TEMP ("LAB09-RSoP-" + [guid]::NewGuid().ToString('N') + '.xml')
            $XmlExit=$null; $Listed=$false; $XmlOK=$false; $XmlError=''
            try {
                $null = & gpresult.exe /scope computer /x $XmlPath /f 2>&1
                $XmlExit=$LASTEXITCODE
                if ($XmlExit -eq 0 -and (Test-Path -LiteralPath $XmlPath)) {
                    [xml]$Doc=Get-Content -LiteralPath $XmlPath -Raw -ErrorAction Stop
                    $Nodes=@($Doc.SelectNodes("//*[local-name()='ComputerResults']//*[local-name()='GPO']"))
                    foreach ($Node in $Nodes) {
                        $N=$Node.SelectSingleNode("./*[local-name()='Name']")
                        if ($N -and $N.InnerText -eq $ExpectedGPO) {
                            $Listed=$true
                        }
                    }
                    $XmlOK=$true
                }
            } catch { $XmlError=$_.Exception.Message }
            finally { Remove-Item -LiteralPath $XmlPath -Force -ErrorAction SilentlyContinue }
            $ValueText=''; $RegistryOK=$false
            try {
                $Value=(Get-ItemProperty -LiteralPath $RegistryPath -Name $ValueName -ErrorAction Stop).$ValueName
                $ValueText=[string]$Value
                $RegistryOK=([int64]$Value -eq $ExpectedValue)
            } catch { $ValueText='Unavailable: ' + $_.Exception.Message }
            [pscustomobject]@{
                Computer=$env:COMPUTERNAME; UpdateExit=$UpdateExit; UpdateText=$UpdateText
                ResultExit=$ResultExit; ResultText=$ResultText; XmlExit=$XmlExit
                XmlOK=$XmlOK; Listed=$Listed; XmlError=$XmlError
                RegistryOK=$RegistryOK; ActualValue=$ValueText
            }
        } -ErrorAction Stop)
        if ($Readback.Count -ne 1) { throw "Expected one client summary; received $($Readback.Count)." }
        $R=$Readback[0]
        $EvidencePath=Join-Path $EvidenceDir "$Name-gpresult.txt"
        @("COMPUTER: $Name","EXPECTED GPO: $($Target.GPO)","GPUPDATE EXIT: $($R.UpdateExit)","GPUPDATE:",$R.UpdateText,"GPRESULT EXIT: $($R.ResultExit)","GPRESULT:",$R.ResultText) | Out-File $EvidencePath -Encoding UTF8
        if (-not $SkipGPUpdate) {
            Add-Result 'Client' $Name 'gpupdate computer' 'Exit code 0' ([string]$R.UpdateExit) $(if ($R.UpdateExit -eq 0) {'PASS'} else {'FAIL'})
        }
        Add-Result 'Client' $Name 'gpresult computer' 'Exit code 0' ([string]$R.ResultExit) $(if ($R.ResultExit -eq 0) {'PASS'} else {'FAIL'})
        $GpStatus=if (-not $R.XmlOK) {'REVIEW'} elseif ($R.Listed) {'PASS'} else {'FAIL'}
        Add-Result 'Client' $Name "GPO listed by gpresult: $($Target.GPO)" 'True' $(if ($R.XmlOK) {[string]$R.Listed} else {'RSoP XML unavailable'}) $GpStatus ([string]$R.XmlError)
        Add-Result 'Client' $Name "Effective registry: $($Def.ValueName)" ([string]$Def.Value) ([string]$R.ActualValue) $(if ($R.RegistryOK) {'PASS'} else {'FAIL'})
    } catch {
        Add-Result 'Client' $Name 'PowerShell Direct verification' 'Successful' $_.Exception.Message 'FAIL'
    } finally { if ($Session) { Remove-PSSession $Session -ErrorAction SilentlyContinue } }
}

# User-policy application cannot be proven from an elevated remote session.
Add-Result 'User session' 'CONTOSO\ewa.kaczmarek' 'LAB09-Users-Finance applied' 'Check during interactive user sign-in' 'Not tested in user context' 'REVIEW' 'Log on as Ewa; run gpupdate /target:user /force, gpresult /scope user /r, and rsop.msc.'
Add-Result 'User session' 'Admin account in target OU' 'LAB09-Admin-Accounts applied' 'Check during interactive user sign-in' 'Not tested in user context' 'REVIEW' 'Use a dedicated administrative user in OU=Konta administracyjne; do not relocate built-in Administrator.'

# Save reports even when checks fail.
$Rows=@($Results.ToArray())
$Rows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
$Pass=@($Rows | Where-Object Status -eq 'PASS').Count
$Fail=@($Rows | Where-Object Status -eq 'FAIL').Count
$Review=@($Rows | Where-Object Status -eq 'REVIEW').Count
$Table=$Rows | Format-Table Area,Target,Check,Status -AutoSize | Out-String -Width 240
$Details=$Rows | Format-List * | Out-String -Width 240
@("LAB09-03 VERIFICATION REPORT","Host: $env:COMPUTERNAME","Domain: $DomainName","Date: $(Get-Date)","PASS=$Pass FAIL=$Fail REVIEW=$Review",'', $Table, 'DETAILS', $Details, 'USER SESSION COMMANDS:', 'gpupdate /target:user /force', 'gpresult /scope user /r', 'gpresult /h "$env:TEMP\LAB09-user.html" /f', 'rsop.msc') | Out-File -FilePath $TxtPath -Encoding UTF8
$HtmlHead='<style>body{font-family:Segoe UI,Arial,sans-serif;margin:28px;color:#294554}h1{color:#146393}table{border-collapse:collapse;width:100%}td,th{padding:8px;border:1px solid #dce6eb;text-align:left}th{background:#146393;color:white}tr:nth-child(even){background:#f5f9fb}</style>'
$Rows | ConvertTo-Html -Title 'LAB09-03 Verification' -Head $HtmlHead -PreContent "<h1>LAB09-03 - GPO verification</h1><p>PASS: $Pass | FAIL: $Fail | REVIEW: $Review</p>" | Out-File -FilePath $HtmlPath -Encoding UTF8
Write-Host "`nLAB09-03 RESULTS: PASS=$Pass FAIL=$Fail REVIEW=$Review" -ForegroundColor Cyan
$Rows | Format-Table Area,Target,Check,Status -AutoSize | Out-Host
Write-Host "CSV: $CsvPath"
Write-Host "TXT: $TxtPath"
Write-Host "HTML: $HtmlPath"
Write-Host "Evidence: $EvidenceDir"
if ($Fail -gt 0) { throw "LAB09-03 reported $Fail failed checks. Review reports." }
if ($Review -gt 0) { Write-Warning 'REVIEW is expected for user-side GPOs until verified in actual user sessions.' }
Write-Host 'LAB09-03 COMPLETED' -ForegroundColor Green
