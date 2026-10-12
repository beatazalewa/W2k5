# ==========================================================
# LAB 03 - Create checkpoint before AD DS installation
# Run on Hyper-V host as Administrator
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'
$CheckpointName = 'LAB03-Before-ADDS'

Import-Module Hyper-V -ErrorAction Stop

$Existing = Get-VMSnapshot `
    -VMName $VMName `
    -Name $CheckpointName `
    -ErrorAction SilentlyContinue

if ($Existing) {
    Write-Host "Checkpoint already exists." -ForegroundColor Yellow
}
else {
    Checkpoint-VM `
        -Name $VMName `
        -SnapshotName $CheckpointName `
        -ErrorAction Stop

    Write-Host "Checkpoint created successfully." -ForegroundColor Green
}

Get-VMSnapshot -VMName $VMName |
    Select-Object VMName, Name, CreationTime |
    Format-Table -AutoSize