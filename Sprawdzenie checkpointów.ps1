Get-VM -Name SEA-DC1,SEA-SRV1,SEA-SRV2,SEA-CL1 |
    Get-VMSnapshot |
    Format-Table VMName, Name, CreationTime
