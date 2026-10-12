# ==========================================================
# Checking VM State
# Run on the Hyper-V host as Administrator
# ==========================================================


Get-VM |
    Where-Object Name -in @(
        'SEA-DC1',
        'SEA-SRV1',
        'SEA-SRV2',
        'SEA-CL1'
    ) |
    Format-Table Name, State, Status

