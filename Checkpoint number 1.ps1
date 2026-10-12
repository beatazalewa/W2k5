$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

foreach ($VM in $VMs) {
    Checkpoint-VM -Name $VM -SnapshotName 'Baseline-Initial'
}