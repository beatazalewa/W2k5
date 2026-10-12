# ==========================================================
# LAB 6 - Script 03a - Restart computers
#
# Run on host in elevated Windows PowerShell 5.1.
#
# Target virtual machines:
#   SEA-SRV1 - 10.10.10.20 - Windows Server 2025
#   SEA-SRV2 - 10.10.10.30 - Windows Server 2025
#   SEA-CL1  - 10.10.10.100 - Windows 11
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# DNS server: 10.10.10.10
#
# Prerequisite:
#   LAB06-03-Join-Domain.ps1 completed successfully.
#
# Computers are not restarted automatically.
# ==========================================================

Restart-VM -Name 'SEA-SRV1'
Restart-VM -Name 'SEA-CL1'
Restart-VM -Name 'SEA-SRV2'
