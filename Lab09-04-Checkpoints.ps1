#requires -Version 5.1
#requires -RunAsAdministrator
<#
LAB 9 - Script 04 - Hyper-V production checkpoints
Run on the Hyper-V HOST in Windows PowerShell 5.1.
No checkpoint is created for the domain controller SEA-DC1.
ProductionOnly prevents fallback to a standard checkpoint.
Checkpoints are not backups. Restoring domain members to an older state can
create computer-account trust/password and other consistency issues.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$ReportDir = 'C:\LabReports',
    [string]$CheckpointName = 'LAB09-Complete-GPOs-2026-10-15'
)

$ErrorActionPreference = 'Stop'
Import-Module Hyper-V -ErrorAction Stop

$Targets = @('SEA-SRV1', 'SEA-SRV2', 'SEA-CL1')
$ExcludedDC = 'SEA-DC1'
$Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null
$CsvPath = Join-Path $ReportDir "LAB09-04-Checkpoints_$Stamp.csv"
$TxtPath = Join-Path $ReportDir "LAB09-04-Checkpoints_$Stamp.txt"
$Results = @()

Write-Host "LAB09-04 - Hyper-V production checkpoints" -ForegroundColor Cyan
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Checkpoint name: $CheckpointName"
Write-Warning "$ExcludedDC is intentionally excluded. Use appropriate AD DS backups."

foreach ($Name in $Targets) {
    $Status = 'FAIL'
    $Message = ''
    $CheckpointId = ''
    $VmState = ''
    $Type = ''
    try {
        $Vm = Get-VM -Name $Name -ErrorAction Stop
        $VmState = [string]$Vm.State
        $Type = [string]$Vm.CheckpointType
        $Existing = @(Get-VMSnapshot -VMName $Name -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $CheckpointName })

        if ($Existing.Count -gt 0) {
            $Status = 'EXISTS'
            $Message = 'Checkpoint with the requested name already exists; no changes made.'
            $CheckpointId = [string]$Existing[0].Id
        }
        elseif ($PSCmdlet.ShouldProcess($Name, 'Set ProductionOnly and create production checkpoint')) {
            if ([string]$Vm.CheckpointType -ne 'ProductionOnly') {
                Set-VM -Name $Name -CheckpointType ProductionOnly -ErrorAction Stop
            }
            $Vm = Get-VM -Name $Name -ErrorAction Stop
            $Type = [string]$Vm.CheckpointType
            if ($Type -ne 'ProductionOnly') {
                throw "ProductionOnly configuration was not applied: $Type"
            }
            Checkpoint-VM -Name $Name -SnapshotName $CheckpointName -ErrorAction Stop | Out-Null
            $Created = @(Get-VMSnapshot -VMName $Name -ErrorAction Stop |
                Where-Object { $_.Name -eq $CheckpointName })
            if ($Created.Count -ne 1) {
                throw "Checkpoint verification failed; matches: $($Created.Count)"
            }
            $CheckpointId = [string]$Created[0].Id
            $Status = 'PASS'
            $Message = 'Production checkpoint created and verified.'
        }
        else {
            $Status = 'WHATIF'
            $Message = 'Preview only; no checkpoint created.'
        }
    }
    catch {
        $Message = $_.Exception.Message
    }
    $Results += [pscustomobject]@{
        VMName = $Name
        VMState = $VmState
        CheckpointType = $Type
        CheckpointName = $CheckpointName
        CheckpointId = $CheckpointId
        Status = $Status
        Details = $Message
    }
}

$Results | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
$Results | Format-Table VMName, VMState, CheckpointType, Status -AutoSize | Out-Host
$Summary = @(
    "LAB09-04 - Hyper-V checkpoints"
    "Date: $(Get-Date)"
    "Host: $env:COMPUTERNAME"
    "Excluded domain controller: $ExcludedDC"
    "Checkpoint name: $CheckpointName"
    ''
    ($Results | Format-List * | Out-String -Width 220)
    'CAUTION: Checkpoints are not backups. Do not casually roll back domain members.'
) -join [Environment]::NewLine
$Summary | Out-File -LiteralPath $TxtPath -Encoding UTF8
Write-Host "CSV: $CsvPath"
Write-Host "TXT: $TxtPath"
$Failures = @($Results | Where-Object { $_.Status -eq 'FAIL' })
if ($Failures.Count -gt 0) {
    throw "LAB09-04: $($Failures.Count) checkpoint operations failed. Review reports."
}
Write-Host 'LAB09-04 completed.' -ForegroundColor Green
