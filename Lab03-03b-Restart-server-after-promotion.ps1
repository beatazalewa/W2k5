# ==========================================================
# LAB 3 - Restart server after AD DS promotion
# Run ONLY on Hyper-V host as Administrator
# Target VM: SEA-DC1
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop

Write-Host ""
Write-Host "========================================"
Write-Host "LAB 3 - RESTART AFTER AD DS PROMOTION"
Write-Host "========================================"
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "VM: $VMName"
Write-Host "State: $($VM.State)"

if ($VM.State -ne 'Running') {
    throw "VM $VMName is not running."
}

# Verify the shutdown integration service
$ShutdownService = Get-VMIntegrationService `
    -VMName $VMName `
    -Name 'Shutdown' `
    -ErrorAction Stop

if (-not $ShutdownService.Enabled) {
    throw "The Hyper-V Shutdown integration service is disabled."
}

# Request confirmation
$Confirmation = Read-Host 'Type RESTART to confirm'

if ($Confirmation -cne 'RESTART') {
    Write-Host 'Operation cancelled.'
    return
}

# Request an operating system restart through Hyper-V
# Restart-VM without -Force requests a graceful restart
Restart-VM `
    -Name $VMName `
    -ErrorAction Stop

Write-Host ""
Write-Host "Restart requested for $VMName." `
    -ForegroundColor Green

Write-Host "Wait for Windows Server to start before continuing."