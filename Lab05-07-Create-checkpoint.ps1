# ==========================================================
# LAB 5 - Script 07 - Create Production Checkpoint
# Run ONLY on Hyper-V host as Administrator
# Target: SEA-DC1
# Domain: contoso.com
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$VMName = 'SEA-DC1'
$CheckpointName = 'LAB05-AD-Structure-Configured'

# ----------------------------------------------------------
# 2. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "VM $VMName is not running."
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 5 - PRODUCTION CHECKPOINT"
Write-Host "=========================================="
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "VM: $VMName"
Write-Host "Checkpoint: $CheckpointName"
Write-Host ""

# ----------------------------------------------------------
# 3. Check whether checkpoint already exists
# ----------------------------------------------------------

$Existing = @(
    Get-VMSnapshot `
        -VMName $VMName `
        -Name $CheckpointName `
        -ErrorAction SilentlyContinue
)

if ($Existing.Count -gt 0) {

    Write-Host "Existing checkpoint found:" `
        -ForegroundColor Yellow

    $Existing |
        Select-Object Name, SnapshotType, CreationTime |
        Format-Table -AutoSize |
        Out-Host

    $ExistingType = [string]$Existing[0].SnapshotType

    if ($ExistingType -match 'Production') {

        Write-Host ""
        Write-Host "Production checkpoint already exists." `
            -ForegroundColor Green

        return
    }

    Write-Warning "Existing checkpoint is not identified as production."

    # Preserve the existing checkpoint
    $CheckpointName = 'LAB05-AD-Structure-Configured-Production'
}

# ----------------------------------------------------------
# 4. Configure production checkpoints only
# ----------------------------------------------------------

Set-VM `
    -Name $VMName `
    -CheckpointType ProductionOnly `
    -ErrorAction Stop

Write-Host "ProductionOnly checkpoint mode configured." `
    -ForegroundColor Green

# ----------------------------------------------------------
# 5. Prevent duplicate checkpoint names
# ----------------------------------------------------------

$Target = @(
    Get-VMSnapshot `
        -VMName $VMName `
        -Name $CheckpointName `
        -ErrorAction SilentlyContinue
)

if ($Target.Count -gt 0) {

    Write-Warning "Target checkpoint name already exists."

    $Target |
        Select-Object Name, SnapshotType, CreationTime |
        Format-Table -AutoSize |
        Out-Host

    return
}

# ----------------------------------------------------------
# 6. Create production checkpoint
# ----------------------------------------------------------

Write-Host ""
Write-Host "Creating checkpoint: $CheckpointName" `
    -ForegroundColor Cyan

Checkpoint-VM `
    -Name $VMName `
    -SnapshotName $CheckpointName `
    -ErrorAction Stop

# ----------------------------------------------------------
# 7. Verify checkpoint
# ----------------------------------------------------------

$Created = Get-VMSnapshot `
    -VMName $VMName `
    -Name $CheckpointName `
    -ErrorAction Stop

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 5 - CHECKPOINT REPORT"
Write-Host "=========================================="

$Created |
    Select-Object VMName, Name, SnapshotType, CreationTime |
    Format-Table -AutoSize |
    Out-Host

# Hyper-V may display production checkpoints using
# a different SnapshotType representation.
$CreatedType = [string]$Created.SnapshotType

if ($CreatedType -match 'Standard') {

    Write-Warning "Checkpoint appears to be a standard checkpoint."
    Write-Warning "Verify the checkpoint type in Hyper-V Manager."
}
else {

    Write-Host ""
    Write-Host "LAB 5 - CHECKPOINT CREATED SUCCESSFULLY" `
        -ForegroundColor Green
}

# ----------------------------------------------------------
# 8. List all existing checkpoints
# ----------------------------------------------------------

Write-Host ""
Write-Host "ALL CHECKPOINTS FOR $VMName" `
    -ForegroundColor Cyan

Get-VMSnapshot -VMName $VMName |
    Select-Object Name, SnapshotType, CreationTime |
    Sort-Object CreationTime |
    Format-Table -AutoSize |
    Out-Host