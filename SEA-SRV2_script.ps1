
# ============================================================
# Tworzenie maszyny SEA-SRV2
# System: Windows Server 2025
# Hyper-V / Generation 2 / ISO
# ============================================================

$ErrorActionPreference = 'Stop'

# Konfiguracja
$VMName     = 'SEA-SRV2'
$VMRoot     = "C:\VMs\$VMName"
$VHDPath    = Join-Path $VMRoot "$VMName.vhdx"
$ISOPath    = 'F:\ISO\WindowsServer2025.iso'
$SwitchName = 'LabSwitch'

$StartupRAM = 4GB
$MinimumRAM = 2GB
$MaximumRAM = 4GB
$DiskSize   = 128GB
$CPUCount   = 2

# Sprawdzenie uprawnien administratora
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw "Uruchom PowerShell jako administrator."
}

# Zaladowanie modulu Hyper-V
Import-Module Hyper-V -ErrorAction Stop

# Sprawdzenie ISO
if (-not (Test-Path -LiteralPath $ISOPath -PathType Leaf)) {
    throw "Nie znaleziono obrazu ISO: $ISOPath"
}

# Sprawdzenie przelacznika wirtualnego
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

if (-not $switch) {
    throw "Nie znaleziono przelacznika Hyper-V: $SwitchName"
}

# Sprawdzenie maszyny VM
if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
    throw "Maszyna $VMName juz istnieje."
}

# Sprawdzenie dysku
if (Test-Path -LiteralPath $VHDPath) {
    throw "Dysk VHDX juz istnieje: $VHDPath"
}

# Utworzenie katalogu
New-Item -ItemType Directory -Path $VMRoot -Force |
    Out-Null

# Utworzenie maszyny
New-VM `
    -Name $VMName `
    -Generation 2 `
    -Path $VMRoot `
    -MemoryStartupBytes $StartupRAM `
    -NewVHDPath $VHDPath `
    -NewVHDSizeBytes $DiskSize `
    -SwitchName $SwitchName

# Konfiguracja pamieci i procesorow
Set-VM `
    -Name $VMName `
    -ProcessorCount $CPUCount `
    -DynamicMemory `
    -MemoryMinimumBytes $MinimumRAM `
    -MemoryMaximumBytes $MaximumRAM

# Podlaczenie obrazu ISO
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

# Ustawienie startu z ISO
$DVD = Get-VMDvdDrive -VMName $VMName

Set-VMFirmware `
    -VMName $VMName `
    -FirstBootDevice $DVD

# Weryfikacja podlaczonego ISO
Get-VMDvdDrive -VMName $VMName |
    Select-Object VMName, Path

# Podsumowanie
Get-VM -Name $VMName |
    Select-Object Name, State, Generation,
                  ProcessorCount, DynamicMemoryEnabled

Write-Host ""
Write-Host "Maszyna $VMName zostala utworzona." -ForegroundColor Green
Write-Host "Obraz ISO: $ISOPath"
Write-Host "Dysk VHDX: $VHDPath"

# Uruchomienie VM
Start-VM -Name $VMName

# Otwarcie konsoli VM
vmconnect.exe localhost $VMName
