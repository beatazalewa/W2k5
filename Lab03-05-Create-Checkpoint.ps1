# ==========================================================
# LAB 3 - Script 05 - Create Hyper-V Checkpoint
# Run ONLY on Hyper-V host as Administrator
#
# Target: SEA-DC1
# Checkpoint: LAB03-ADDS-Installed
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$VMName = 'SEA-DC1'
$CheckpointName = 'LAB03-ADDS-Installed'

Import-Module Hyper-V -ErrorAction Stop

Write-Host ""
Write-Host "========================================"
Write-Host "LAB 3 - CREATE CHECKPOINT"
Write-Host "========================================"
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "VM: $VMName"
Write-Host "Checkpoint: $CheckpointName"

# ----------------------------------------------------------
# 2. Verify virtual machine
# ----------------------------------------------------------

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "VM $VMName is not running."
}

# ----------------------------------------------------------
# 3. Check for an existing checkpoint
# ----------------------------------------------------------

$ExistingCheckpoint = Get-VMSnapshot `
    -VMName $VMName `
    -Name $CheckpointName `
    -ErrorAction SilentlyContinue

if ($ExistingCheckpoint) {

    Write-Host ""
    Write-Host "Checkpoint already exists." `
        -ForegroundColor Yellow

}
else {

    # ------------------------------------------------------
    # 4. Configure production checkpoints
    # ------------------------------------------------------

    Set-VM `
        -Name $VMName `
        -CheckpointType ProductionOnly `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 5. Create checkpoint
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "Creating production checkpoint..." `
        -ForegroundColor Cyan

    Checkpoint-VM `
        -Name $VMName `
        -SnapshotName $CheckpointName `
        -ErrorAction Stop

    Write-Host "Checkpoint created successfully." `
        -ForegroundColor Green
}

# ----------------------------------------------------------
# 6. Verify checkpoint
# ----------------------------------------------------------

$Checkpoint = Get-VMSnapshot `
    -VMName $VMName `
    -Name $CheckpointName `
    -ErrorAction Stop

Write-Host ""
Write-Host "========================================"
Write-Host "LAB 3 - CHECKPOINT REPORT"
Write-Host "========================================"

$Checkpoint |
    Select-Object VMName, Name, CreationTime, SnapshotType |
    Format-Table -AutoSize |
    Out-Host

Write-Host ""
Write-Host "LAB 3 - CHECKPOINT VERIFICATION PASSED" `
    -ForegroundColor Green
