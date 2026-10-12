# =====================================================
# LAB 1 Script 2 - Configure static IPv4 addressing
# Run inside each virtual machine as Administrator
# =====================================================

$ErrorActionPreference = 'Stop'

# Define IP addresses for laboratory computers
$IPMap = @{
    'SEA-DC1'  = '10.10.10.10'
    'SEA-SRV1' = '10.10.10.20'
    'SEA-SRV2' = '10.10.10.30'
    'SEA-CL1'  = '10.10.10.100'
}

$ComputerName = $env:COMPUTERNAME.ToUpper()
$PrefixLength = 24
$DnsServer = '10.10.10.10'

# Verify computer name
if (-not $IPMap.ContainsKey($ComputerName)) {
    throw "Unknown computer name: $ComputerName"
}

$IPAddress = $IPMap[$ComputerName]

# Find active Hyper-V network adapter
$adapters = @(
    Get-NetAdapter |
    Where-Object {
        $_.Status -eq 'Up' -and
        $_.InterfaceDescription -like '*Hyper-V*'
    }
)

if ($adapters.Count -ne 1) {
    Get-NetAdapter | Format-Table Name, Status, InterfaceDescription
    throw "Expected one active Hyper-V adapter. Found $($adapters.Count)."
}

$nic = $adapters[0]
$index = $nic.ifIndex

Write-Host "Computer: $ComputerName"
Write-Host "Adapter: $($nic.Name)"
Write-Host "IP address: $IPAddress"

# Disable DHCP
Set-NetIPInterface `
    -InterfaceIndex $index `
    -AddressFamily IPv4 `
    -Dhcp Disabled

# Remove previous manual IPv4 addresses
Get-NetIPAddress `
    -InterfaceIndex $index `
    -AddressFamily IPv4 `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.PrefixOrigin -eq 'Manual' -and
        $_.IPAddress -ne $IPAddress
    } |
    Remove-NetIPAddress -Confirm:$false

# Remove default gateway from the lab interface
Get-NetRoute `
    -InterfaceIndex $index `
    -DestinationPrefix '0.0.0.0/0' `
    -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false

# Set static IP address
$current = Get-NetIPAddress `
    -InterfaceIndex $index `
    -IPAddress $IPAddress `
    -ErrorAction SilentlyContinue

if (-not $current) {

    New-NetIPAddress `
        -InterfaceIndex $index `
        -IPAddress $IPAddress `
        -PrefixLength $PrefixLength |
        Out-Null
}
elseif ($current.PrefixLength -ne $PrefixLength) {

    Set-NetIPAddress `
        -InputObject $current `
        -PrefixLength $PrefixLength
}

# Configure DNS
Set-DnsClientServerAddress `
    -InterfaceIndex $index `
    -ServerAddresses $DnsServer

Write-Host ""
Write-Host "Network configuration completed." -ForegroundColor Green

Get-NetIPConfiguration -InterfaceIndex $index
