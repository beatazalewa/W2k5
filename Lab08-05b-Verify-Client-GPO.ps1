# ==========================================================
# LAB 8 - Script 05A - Verify Client GPO Application
#
# Run on the Hyper-V host as Administrator.
# Requires Windows PowerShell 5.1.
#
# Domain: contoso.com
# Client VM: SEA-CL1
# Expected GPO: LAB08-System-Workstations
#
# Verifies actual client-side Group Policy application.
# ==========================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$HostName = $env:COMPUTERNAME
$ClientName = 'SEA-CL1'
$ExpectedGPO = 'LAB08-System-Workstations'

$ReportDir = 'C:\LabReports'
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$TXT = Join-Path $ReportDir `
    "LAB08-Client-GPO-Verify_$Timestamp.txt"

$CSV = Join-Path $ReportDir `
    "LAB08-Client-GPO-Verify_$Timestamp.csv"

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CLIENT GPO VERIFICATION"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $HostName"
Write-Host "Client: $ClientName"
Write-Host "Expected GPO: $ExpectedGPO"

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $ClientName -ErrorAction Stop

if ([string]$VM.State -ne 'Running') {
    throw "$ClientName is not running."
}

New-Item -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

$Session = $null

try {

    $Session = New-PSSession `
        -VMName $ClientName `
        -Credential $Credential `
        -ErrorAction Stop

    $Data = Invoke-Command `
        -Session $Session `
        -ScriptBlock {

            $ErrorActionPreference = 'Stop'

            # Refresh computer policies.
            $GPUpdateOutput = @(
                & gpupdate.exe /target:computer /force 2>&1 |
                    Out-String
            )

            $GPUpdateExitCode = $LASTEXITCODE

            # Generate computer Group Policy results.
            $GPResultOutput = (
                & gpresult.exe /scope computer /r 2>&1 |
                    Out-String
            )

            $GPResultExitCode = $LASTEXITCODE

            # Define expected client registry settings.
            $Settings = @(
                @{
                    Name = 'NoAutoUpdate'
                    Path = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
                    Expected = 0
                },
                @{
                    Name = 'AUOptions'
                    Path = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
                    Expected = 2
                },
                @{
                    Name = 'NoAutoRebootWithLoggedOnUsers'
                    Path = 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
                    Expected = 1
                },
                @{
                    Name = 'DisableWindowsConsumerFeatures'
                    Path = 'HKLM:\Software\Policies\Microsoft\Windows\CloudContent'
                    Expected = 1
                },
                @{
                    Name = 'EnableFirstLogonAnimation'
                    Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
                    Expected = 0
                }
            )

            # Emit flat records to avoid nested array issues.
            [PSCustomObject]@{
                RecordType = 'SUMMARY'
                Computer = $env:COMPUTERNAME
                GPUpdateExitCode = $GPUpdateExitCode
                GPResultExitCode = $GPResultExitCode
                GPUpdateText = ($GPUpdateOutput -join "`n")
                GPResultText = $GPResultOutput
            }

            foreach ($Setting in $Settings) {

                $Actual = $null
                $ReadError = ''

                try {

                    $Property = Get-ItemProperty `
                        -Path $Setting.Path `
                        -Name $Setting.Name `
                        -ErrorAction Stop

                    $Actual = $Property.($Setting.Name)
                }
                catch {
                    $ReadError = $_.Exception.Message
                }

                [PSCustomObject]@{
                    RecordType = 'SETTING'
                    Name = $Setting.Name
                    Expected = [int]$Setting.Expected
                    Actual = $Actual
                    ReadError = $ReadError
                    Passed = (
                        $null -ne $Actual -and
                        [int]$Actual -eq
                            [int]$Setting.Expected
                    )
                }
            }
        } `
        -ErrorAction Stop
}
finally {

    if ($null -ne $Session) {
        Remove-PSSession -Session $Session
    }
}

$Summary = @(
    $Data | Where-Object RecordType -eq 'SUMMARY'
)

$Settings = @(
    $Data | Where-Object RecordType -eq 'SETTING'
)

if ($Summary.Count -ne 1) {
    throw 'Expected exactly one summary record.'
}

if ($Settings.Count -ne 5) {
    throw 'Expected exactly five setting records.'
}

$Summary = $Summary[0]

$AppliedGPO = (
    $Summary.GPResultExitCode -eq 0 -and
    $Summary.GPResultText -match
        '(?im)^\s*LAB08-System-Workstations\s*$'
)

$Checks = @()

$Checks += [PSCustomObject]@{
    Check = 'Computer policy refresh'
    Expected = 'Exit code 0'
    Actual = [string]$Summary.GPUpdateExitCode
    Status = if ($Summary.GPUpdateExitCode -eq 0) {
        'PASS'
    } else {
        'FAIL'
    }
}

$Checks += [PSCustomObject]@{
    Check = 'gpresult execution'
    Expected = 'Exit code 0'
    Actual = [string]$Summary.GPResultExitCode
    Status = if ($Summary.GPResultExitCode -eq 0) {
        'PASS'
    } else {
        'FAIL'
    }
}

$Checks += [PSCustomObject]@{
    Check = 'Expected GPO applied'
    Expected = $ExpectedGPO
    Actual = [string]$AppliedGPO
    Status = if ($AppliedGPO) {
        'PASS'
    } else {
        'FAIL'
    }
}

foreach ($Setting in $Settings) {

    $Checks += [PSCustomObject]@{
        Check = [string]$Setting.Name
        Expected = "DWORD $($Setting.Expected)"
        Actual = if ($null -ne $Setting.Actual) {
            "DWORD $($Setting.Actual)"
        } else {
            "Not found: $($Setting.ReadError)"
        }
        Status = if ($Setting.Passed) {
            'PASS'
        } else {
            'FAIL'
        }
    }
}

$Checks | Export-Csv `
    -Path $CSV `
    -NoTypeInformation `
    -Encoding UTF8

$Passed = @($Checks | Where-Object Status -eq 'PASS').Count
$Failed = @($Checks | Where-Object Status -eq 'FAIL').Count

$Report = @"
LAB 8 - CLIENT GPO VERIFICATION

Host: $HostName
Client: $ClientName
Expected GPO: $ExpectedGPO

GPUPDATE OUTPUT
$($Summary.GPUpdateText)

GPRESULT OUTPUT
$($Summary.GPResultText)

VERIFICATION RESULTS
$($Checks | Format-Table -AutoSize | Out-String -Width 220)

PASS: $Passed
FAIL: $Failed
"@

$Report | Out-File `
    -FilePath $TXT `
    -Encoding UTF8

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CLIENT GPO RESULTS"
Write-Host "=========================================="
Write-Host ""

$Checks | Format-Table -AutoSize | Out-Host

Write-Host ""
Write-Host "PASS: $Passed"
Write-Host "FAIL: $Failed"

Write-Host ""
Write-Host "CSV: $CSV"
Write-Host "TXT: $TXT"

if ($Failed -gt 0) {
    throw 'LAB 8 - Client-side GPO verification failed.'
}

Write-Host ""
Write-Host "LAB 8 - CLIENT GPO VERIFIED" `
    -ForegroundColor Green
