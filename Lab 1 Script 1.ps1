
# =====================================================
# LAB 1 script 1 - Verify Hyper-V virtual machines and network
# Run on the Hyper-V host as Administrator
# =====================================================

$ErrorActionPreference = 'Stop'

$SwitchName = 'LabSwitch'

$VMNames = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

Import-Module Hyper-V -ErrorAction Stop

# Verify the laboratory switch
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction Stop

if ($switch.SwitchType -ne 'Internal') {
    throw "$SwitchName must be an Internal switch."
}

Write-Host "LabSwitch verified." -ForegroundColor Green

foreach ($VMName in $VMNames) {

    $vm = Get-VM -Name $VMName -ErrorAction Stop

    $adapters = @(
        Get-VMNetworkAdapter -VMName $VMName
    )

    if ($adapters.Count -ne 1) {
        Write-Warning "$VMName has $($adapters.Count) adapters. Check manually."
        continue
    }

    $nic = $adapters[0]

    if ($nic.SwitchName -eq $SwitchName) {
        Write-Host "$VMName already connected to LabSwitch."
    }
    elseif ([string]::IsNullOrEmpty($nic.SwitchName)) {

        $nic | Connect-VMNetworkAdapter -SwitchName $SwitchName

        Write-Host "$VMName connected to LabSwitch." -ForegroundColor Green
    }
    else {
        Write-Warning "$VMName uses switch $($nic.SwitchName). No changes made."
    }
}

# Display network adapters
foreach ($VMName in $VMNames) {

    Get-VMNetworkAdapter -VMName $VMName |
        Select-Object VMName, Name, SwitchName, MacAddress
}
