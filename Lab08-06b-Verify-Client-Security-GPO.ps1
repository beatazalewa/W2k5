# ==========================================================
# LAB 8 - Script 06 - Client Security GPO Verification
#
# Run on the Hyper-V host as Administrator.
# Windows PowerShell 5.1.
#
# Target VM: SEA-CL1
# Expected GPO: LAB08-Security-Workstations
#
# This script does not modify the GPO.
# It refreshes and verifies client-side computer policy.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$HostName = $env:COMPUTERNAME
$VMName = 'SEA-CL1'
$ExpectedGPO = 'LAB08-Security-Workstations'

$ReportDir = 'C:\LabReports'
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$TXT = Join-Path $ReportDir "LAB08-06-Client-Verify_$Timestamp.txt"
$CSV = Join-Path $ReportDir "LAB08-06-Client-Verify_$Timestamp.csv"

# ----------------------------------------------------------
# 2. Verify host environment
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - SECURITY GPO CLIENT VERIFICATION"
Write-Host "=========================================="
Write-Host ""

Write-Host "Detected host: $HostName"
Write-Host "Client: $VMName"
Write-Host "Expected GPO: $ExpectedGPO"

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw 'Run Windows PowerShell as Administrator.'
}

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ([string]$VM.State -ne 'Running') {
    throw "VM is not running: $VMName"
}

New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null

# ----------------------------------------------------------
# 3. Request credentials
# ----------------------------------------------------------

$CredentialParameters = @{
    UserName = 'CONTOSO\Administrator'
    Message  = 'Enter domain Administrator password'
}

$Credential = Get-Credential @CredentialParameters

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 4. Execute client verification
# ----------------------------------------------------------

$InvokeParameters = @{
    VMName = $VMName
    Credential = $Credential
    ErrorAction = 'Stop'
    ArgumentList = @($ExpectedGPO)
    ScriptBlock = {

        param([string]$ExpectedGPO)

        $ErrorActionPreference = 'Stop'

        # Refresh computer policies.
        $GPUpdateText = (& gpupdate.exe /target:computer /force 2>&1 | Out-String)
        $GPUpdateExitCode = $LASTEXITCODE

        # Generate an XML RSoP report.
        $TempFile = Join-Path $env:TEMP (
            'LAB08-06-GPResult-' + [guid]::NewGuid().ToString('N') + '.xml'
        )

        $GPResultText = ''
        $GPResultExitCode = -1
        $AppliedGPO = $false
        $GPResultError = ''

        try {
            $GPResultText = (& gpresult.exe /scope computer /r 2>&1 | Out-String)
            $GPResultExitCode = $LASTEXITCODE

            # gpresult /r is retained for readable diagnostics.
            # XML report is used to verify applied GPO membership.
            & gpresult.exe /scope computer /x $TempFile /f 2>&1 | Out-Null
            $XMLExitCode = $LASTEXITCODE

            if ($XMLExitCode -eq 0 -and (Test-Path $TempFile)) {
                [xml]$XML = Get-Content -LiteralPath $TempFile -Raw

                $Nodes = @(
                    $XML.SelectNodes(
                        "//*[local-name()='ComputerResults']" +
                        "//*[local-name()='GPO']"
                    )
                )

                foreach ($Node in $Nodes) {
                    $NameNode = $Node.SelectSingleNode(
                        "./*[local-name()='Name']"
                    )

                    $FilterNode = $Node.SelectSingleNode(
                        "./*[local-name()='FilterAllowed']"
                    )

                    $EnabledNode = $Node.SelectSingleNode(
                        "./*[local-name()='Enabled']"
                    )

                    if ($null -ne $NameNode -and
                        $NameNode.InnerText -eq $ExpectedGPO -and
                        $null -ne $FilterNode -and
                        $FilterNode.InnerText -eq 'true' -and
                        ($null -eq $EnabledNode -or
                         $EnabledNode.InnerText -eq 'true')) {

                        $AppliedGPO = $true
                    }
                }
            }
            else {
                $GPResultError = 'Could not generate gpresult XML.'
            }
        }
        finally {
            Remove-Item -LiteralPath $TempFile -Force -ErrorAction SilentlyContinue
        }

        # Check expected registry policy settings.
        $Settings = @(
            @{
                Name = 'EnableFirewall'
                Path = 'HKLM:\Software\Policies\Microsoft\WindowsFirewall\DomainProfile'
                Expected = 1
            }
            @{
                Name = 'DefaultInboundAction'
                Path = 'HKLM:\Software\Policies\Microsoft\WindowsFirewall\DomainProfile'
                Expected = 1
            }
            @{
                Name = 'DefaultOutboundAction'
                Path = 'HKLM:\Software\Policies\Microsoft\WindowsFirewall\DomainProfile'
                Expected = 0
            }
            @{
                Name = 'DisableNotifications'
                Path = 'HKLM:\Software\Policies\Microsoft\WindowsFirewall\DomainProfile'
                Expected = 0
            }
            @{
                Name = 'ConsentPromptBehaviorAdmin'
                Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
                Expected = 5
            }
            @{
                Name = 'PromptOnSecureDesktop'
                Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
                Expected = 1
            }
        )

        # Send one summary record.
        [PSCustomObject]@{
            RecordType = 'SUMMARY'
            Computer = $env:COMPUTERNAME
            GPUpdateExitCode = [int]$GPUpdateExitCode
            GPResultExitCode = [int]$GPResultExitCode
            GPUpdateText = $GPUpdateText
            GPResultText = $GPResultText
            AppliedGPO = [bool]$AppliedGPO
            GPResultError = $GPResultError
        }

        # Send one record per registry value.
        foreach ($Setting in $Settings) {

            $Actual = $null
            $ReadError = ''

            try {
                $Actual = (Get-ItemProperty `
                    -Path $Setting.Path `
                    -Name $Setting.Name `
                    -ErrorAction Stop).($Setting.Name)
            }
            catch {
                $ReadError = $_.Exception.Message
            }

            [PSCustomObject]@{
                RecordType = 'SETTING'
                Name = [string]$Setting.Name
                Expected = [int]$Setting.Expected
                Actual = $Actual
                ReadError = $ReadError
                Passed = [bool](
                    $null -ne $Actual -and
                    [int]$Actual -eq [int]$Setting.Expected
                )
            }
        }

        # Send the effective Domain firewall profile.
        try {
            $Firewall = Get-NetFirewallProfile -PolicyStore ActiveStore -Name Domain -ErrorAction Stop

            [PSCustomObject]@{
                RecordType = 'FIREWALL'
                Enabled = [string]$Firewall.Enabled
                Inbound = [string]$Firewall.DefaultInboundAction
                Outbound = [string]$Firewall.DefaultOutboundAction
                ErrorText = ''
            }
        }
        catch {
            [PSCustomObject]@{
                RecordType = 'FIREWALL'
                Enabled = ''
                Inbound = ''
                Outbound = ''
                ErrorText = $_.Exception.Message
            }
        }
    }
}

$Data = Invoke-Command @InvokeParameters

# ----------------------------------------------------------
# 5. Separate returned records
# ----------------------------------------------------------

$Summaries = @($Data | Where-Object RecordType -eq 'SUMMARY')
$Settings = @($Data | Where-Object RecordType -eq 'SETTING')
$Firewalls = @($Data | Where-Object RecordType -eq 'FIREWALL')

if ($Summaries.Count -ne 1) {
    throw "Expected one SUMMARY record; got $($Summaries.Count)."
}

if ($Settings.Count -ne 6) {
    throw "Expected six SETTING records; got $($Settings.Count)."
}

if ($Firewalls.Count -ne 1) {
    throw "Expected one FIREWALL record; got $($Firewalls.Count)."
}

$Summary = $Summaries[0]
$Firewall = $Firewalls[0]

# ----------------------------------------------------------
# 6. Build verification results
# ----------------------------------------------------------

$Checks = New-Object 'System.Collections.Generic.List[object]'

function Add-Check {
    param(
        [string]$Name,
        [string]$Expected,
        [string]$Actual,
        [bool]$Passed
    )

    $Checks.Add([PSCustomObject]@{
        Check = $Name
        Expected = $Expected
        Actual = $Actual
        Status = if ($Passed) { 'PASS' } else { 'FAIL' }
    })
}

Add-Check 'Computer policy refresh' 'Exit code 0' `
    ([string]$Summary.GPUpdateExitCode) ($Summary.GPUpdateExitCode -eq 0)

Add-Check 'gpresult execution' 'Exit code 0' `
    ([string]$Summary.GPResultExitCode) ($Summary.GPResultExitCode -eq 0)

Add-Check 'Expected GPO applied' 'True' `
    ([string]$Summary.AppliedGPO) ([bool]$Summary.AppliedGPO)

$ExpectedNames = @(
    'EnableFirewall',
    'DefaultInboundAction',
    'DefaultOutboundAction',
    'DisableNotifications',
    'ConsentPromptBehaviorAdmin',
    'PromptOnSecureDesktop'
)

foreach ($ExpectedName in $ExpectedNames) {

    $Match = @($Settings | Where-Object Name -eq $ExpectedName)

    if ($Match.Count -ne 1) {
        throw "Missing or duplicate setting: $ExpectedName"
    }

    $Setting = $Match[0]

    $ActualText = if ($null -ne $Setting.Actual) {
        "DWORD $($Setting.Actual)"
    }
    else {
        "Not found: $($Setting.ReadError)"
    }

    Add-Check $Setting.Name "DWORD $($Setting.Expected)" `
        $ActualText ([bool]$Setting.Passed)
}

# Verify the effective firewall profile separately.
Add-Check 'Domain firewall enabled' 'True' `
    ([string]$Firewall.Enabled) ($Firewall.Enabled -eq 'True')

Add-Check 'Default inbound firewall action' 'Block' `
    ([string]$Firewall.Inbound) ($Firewall.Inbound -eq 'Block')

Add-Check 'Default outbound firewall action' 'Allow' `
    ([string]$Firewall.Outbound) ($Firewall.Outbound -eq 'Allow')

# ----------------------------------------------------------
# 7. Export reports
# ----------------------------------------------------------

$Passed = @($Checks | Where-Object Status -eq 'PASS').Count
$Failed = @($Checks | Where-Object Status -eq 'FAIL').Count

$Checks | Export-Csv -Path $CSV -NoTypeInformation -Encoding UTF8

$Report = @"
============================================================
LAB 8 - SCRIPT 06 - CLIENT VERIFICATION
============================================================

Host: $HostName
Client: $VMName
Expected GPO: $ExpectedGPO
Date: $(Get-Date)

GPUPDATE OUTPUT
$($Summary.GPUpdateText)

GPRESULT OUTPUT
$($Summary.GPResultText)

GPRESULT DIAGNOSTIC
$($Summary.GPResultError)

FIREWALL DIAGNOSTIC
$($Firewall.ErrorText)

VERIFICATION RESULTS
$($Checks | Format-Table -AutoSize | Out-String -Width 220)

PASS: $Passed
FAIL: $Failed
"@

$Report | Out-File -FilePath $TXT -Encoding UTF8

# ----------------------------------------------------------
# 8. Display results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - SECURITY GPO CLIENT RESULTS"
Write-Host "=========================================="
Write-Host ""

$Checks | Format-Table -AutoSize | Out-Host

Write-Host ""
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red

Write-Host ""
Write-Host "CSV: $CSV"
Write-Host "TXT: $TXT"

if ($Failed -gt 0) {
    throw 'LAB08-06 client verification failed. Review the TXT report.'
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - SECURITY GPO CLIENT VERIFIED"
Write-Host "==========================================" -ForegroundColor Green

