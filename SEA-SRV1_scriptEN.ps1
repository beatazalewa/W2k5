# ============================================================
# Creating the SEA-SRV1 virtual machine
# Operating system: Windows Server 2025
# Hyper-V / Generation 2 / ISO
# ============================================================

$ErrorActionPreference = 'Stop'

# Configuration
$VMName     = 'SEA-SRV1'
$VMRoot     = "C:\VMs\$VMName"
$VHDPath    = Join-Path $VMRoot "$VMName.vhdx"
$ISOPath    = 'F:\ISO\WindowsServer2025Eval.iso'
$SwitchName = 'LabSwitch'

$StartupRAM = 4GB
$MinimumRAM = 2GB
$MaximumRAM = 4GB
$DiskSize   = 128GB
$CPUCount   = 2

# Check administrator privileges
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Uruchom PowerShell jako administrator."
}

# Load the Hyper-V module
Import-Module Hyper-V -ErrorAction Stop

# Verify ISO image
if (-not (Test-Path -LiteralPath $ISOPath -PathType Leaf)) {
    throw "Nie znaleziono obrazu ISO: $ISOPath"
}

# Verify virtual switch
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

if (-not $switch) {
    throw "Nie znaleziono przelacznika Hyper-V: $SwitchName"
}

# Check whether the VM already exists
if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
    throw "Maszyna $VMName juz istnieje."
}

# Check virtual disk
if (Test-Path -LiteralPath $VHDPath) {
    throw "Dysk VHDX juz istnieje: $VHDPath"
}

# Create VM directory
New-Item -ItemType Directory -Path $VMRoot -Force |
    Out-Null

# Create virtual machine
New-VM `
    -Name $VMName `
    -Generation 2 `
    -Path $VMRoot `
    -MemoryStartupBytes $StartupRAM `
    -NewVHDPath $VHDPath `
    -NewVHDSizeBytes $DiskSize `
    -SwitchName $SwitchName

# Configuration pamieci i procesorow
Set-VM `
    -Name $VMName `
    -ProcessorCount $CPUCount `
    -DynamicMemory `
    -MemoryMinimumBytes $MinimumRAM `
    -MemoryMaximumBytes $MaximumRAM

# Attach ISO image
$DVD = Get-VMDvdDrive -VMName $VMName

if ($DVD) {
    Set-VMDvdDrive `
        -VMName $VMName `
        -Path $ISOPath
}
else {
    Add-VMDvdDrive `
        -VMName $VMName `
        -Path $ISOPath
}

# Set ISO as the first boot device
$DVD = Get-VMDvdDrive -VMName $VMName

Set-VMFirmware `
    -VMName $VMName `
    -FirstBootDevice $DVD

# Verify attached ISO image
Get-VMDvdDrive -VMName $VMName |
    Select-Object VMName, Path

# Summary
Get-VM -Name $VMName |
    Select-Object Name, State, Generation,
                  ProcessorCount, DynamicMemoryEnabled

Write-Host ""
Write-Host "Maszyna $VMName zostala utworzona." -ForegroundColor Green
Write-Host "Obraz ISO: $ISOPath"
Write-Host "Dysk VHDX: $VHDPath"

# Start virtual machine
Start-VM -Name $VMName

# Open virtual machine console
vmconnect.exe localhost $VMName
