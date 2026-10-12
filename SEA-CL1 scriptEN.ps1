#Requires -RunAsAdministrator
# Windows 11 Enterprise LTSC 2024 - Hyper-V lab VM
# Run on the Hyper-V host, using Windows PowerShell as Administrator.
$ErrorActionPreference = 'Stop'

$VMName     = 'SEA-CL1'
$VMRoot     = "C:\VMs\$VMName"
$VHDPath    = Join-Path $VMRoot "$VMName.vhdx"
$ISOPath    = 'F:\ISO\Windows11Enterprise.iso'
$SwitchName = 'LabSwitch'
$StartupRAM = 4GB
$DiskSize   = 128GB
$CPUCount   = 2
$StartAfterCreation = $true

Import-Module Hyper-V -ErrorAction Stop

if (-not (Test-Path -LiteralPath $ISOPath -PathType Leaf)) {
    throw "ISO not found: $ISOPath. Update ISOPath to the actual ISO file."
}

$existingVM = @(Get-VM -Name $VMName -ErrorAction SilentlyContinue)
if ($existingVM.Count -gt 0) {
    throw "VM '$VMName' already exists. Nothing has been modified."
}
if (Test-Path -LiteralPath $VHDPath) {
    throw "VHDX already exists: $VHDPath. Nothing has been modified."
}

$switches = @(Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)
if ($switches.Count -ne 1) {
    throw "Expected exactly one virtual switch named '$SwitchName'; found $($switches.Count)."
}

New-Item -ItemType Directory -Path $VMRoot -Force | Out-Null

try {
    # Keep VM creation separate from disk and network assignment.
    New-VM -Name $VMName -Generation 2 -Path $VMRoot -MemoryStartupBytes $StartupRAM -NoVHD -ErrorAction Stop | Out-Null

    Set-VMProcessor -VMName $VMName -Count $CPUCount -ErrorAction Stop
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false -StartupBytes $StartupRAM -ErrorAction Stop

    New-VHD -Path $VHDPath -SizeBytes $DiskSize -Dynamic -ErrorAction Stop | Out-Null
    Add-VMHardDiskDrive -VMName $VMName -ControllerType SCSI -Path $VHDPath -ErrorAction Stop

    $adapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop)
    if ($adapters.Count -eq 0) {
        Add-VMNetworkAdapter -VMName $VMName -Name 'Network Adapter' -ErrorAction Stop
        $adapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop)
    }
    if ($adapters.Count -ne 1) {
        throw "Expected one VM network adapter; found $($adapters.Count)."
    }
    $adapters[0] | Connect-VMNetworkAdapter -VMSwitch $switches[0] -ErrorAction Stop

    $drives = @(Get-VMDvdDrive -VMName $VMName -ErrorAction Stop)
    if ($drives.Count -eq 0) {
        Add-VMDvdDrive -VMName $VMName -Path $ISOPath -ErrorAction Stop
    }
    elseif ($drives.Count -eq 1) {
        Set-VMDvdDrive -VMName $VMName -ControllerNumber $drives[0].ControllerNumber -ControllerLocation $drives[0].ControllerLocation -Path $ISOPath -ErrorAction Stop
    }
    else {
        throw "Expected zero or one DVD drive; found $($drives.Count)."
    }

    $dvd = @(Get-VMDvdDrive -VMName $VMName -ErrorAction Stop)
    if ($dvd.Count -ne 1) { throw 'Cannot uniquely identify ISO boot device.' }
    Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate 'MicrosoftWindows' -FirstBootDevice $dvd[0] -ErrorAction Stop

    # Virtual TPM 2.0 is required for a standard Windows 11 installation.
    Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector -ErrorAction Stop
    Enable-VMTPM -VMName $VMName -ErrorAction Stop

    Write-Host "VM created: $VMName" -ForegroundColor Green
    Get-VM -Name $VMName | Select-Object Name, State, Generation, ProcessorCount, MemoryStartup, DynamicMemoryEnabled | Format-List
    Get-VMFirmware -VMName $VMName | Select-Object SecureBoot, SecureBootTemplate, FirstBootDevice | Format-List
    Get-VMSecurity -VMName $VMName | Select-Object TpmEnabled | Format-List
    Get-VMDvdDrive -VMName $VMName | Select-Object VMName, Path | Format-Table

    if ($StartAfterCreation) {
        Start-VM -Name $VMName -ErrorAction Stop
        Write-Host 'If prompted, press any key in the VM console to boot from ISO.' -ForegroundColor Yellow
        & vmconnect.exe localhost $VMName
    }
}
catch {
    Write-Error "VM setup failed: $($_.Exception.Message). Existing VM/VHDX was not deleted."
    throw
}
