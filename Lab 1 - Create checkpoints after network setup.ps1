# =====================================================
# LAB 1 - Create checkpoints after network setup
# Run on Hyper-V host as Administrator
# =====================================================

$ErrorActionPreference = 'Stop'

$VMNames = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

$CheckpointName = 'LAB01-Network-Ready'

foreach ($VMName in $VMNames) {

    try {
        Get-VM -Name $VMName -ErrorAction Stop |
            Out-Null

        $Existing = Get-VMSnapshot `
            -VMName $VMName `
            -Name $CheckpointName `
            -ErrorAction SilentlyContinue

        if ($Existing) {
            Write-Warning "$VMName - checkpoint already exists."
            continue
        }

        Checkpoint-VM `
            -Name $VMName `
            -SnapshotName $CheckpointName `
            -ErrorAction Stop

        Write-Host "$VMName - checkpoint created." `
            -ForegroundColor Green
    }
    catch {
        Write-Warning "$VMName - $($_.Exception.Message)"
    }
}

# Verify all checkpoints
foreach ($VMName in $VMNames) {
    Get-VMSnapshot -VMName $VMName |
        Select-Object VMName, Name, CreationTime
}
