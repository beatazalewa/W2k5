# ==========================================================
# LAB 4 - Fix and Create Production Checkpoint
# Run ONLY on Hyper-V host as Administrator
# Target: SEA-DC1
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'
$CheckpointName = 'LAB04-DNS-Configured'

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "VM $VMName is not running."
}

# Get existing checkpoint
$Existing = Get-VMSnapshot `
    -VMName $VMName `
    -Name $CheckpointName `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "LAB 4 - CHECKPOINT DIAGNOSTICS" -ForegroundColor Cyan

if ($Existing) {

    $Existing |
        Select-Object Name, SnapshotType, CreationTime |
        Format-Table -AutoSize |
        Out-Host

    # Check whether the existing snapshot is production
    $ExistingType = [string]$Existing.SnapshotType

    if ($ExistingType -match 'Production') {
        Write-Host "Production checkpoint already exists." `
            -ForegroundColor Green
        return
    }

    Write-Warning "Existing checkpoint is not identified as production."

    # Preserve the old checkpoint
    $CheckpointName = 'LAB04-DNS-Configured-Production'
}

# Configure production checkpoints only
Set-VM `
    -Name $VMName `
    -CheckpointType ProductionOnly `
    -ErrorAction Stop

# Verify target name is not already used
$Target = Get-VMSnapshot `
    -VMName $VMName `
    -Name $CheckpointName `
    -ErrorAction SilentlyContinue

if ($Target) {
    Write-Warning "Target checkpoint name already exists. No changes made."
    return
}

Write-Host "Creating checkpoint: $CheckpointName" `
    -ForegroundColor Cyan

Checkpoint-VM `
    -Name $VMName `
    -SnapshotName $CheckpointName `
    -ErrorAction Stop

# Verify creation
$Created = Get-VMSnapshot `
    -VMName $VMName `
    -Name $CheckpointName `
    -ErrorAction Stop

Write-Host ""
Write-Host "LAB 4 - CHECKPOINT REPORT" -ForegroundColor Cyan

$Created |
    Select-Object VMName, Name, SnapshotType, CreationTime |
    Format-Table -AutoSize |
    Out-Host

Write-Host "Checkpoint creation completed." `
    -ForegroundColor Green
