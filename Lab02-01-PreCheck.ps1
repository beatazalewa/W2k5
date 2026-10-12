# ==========================================================
# LAB 2 - Script 01 - Server Pre-Configuration Check
# Run on Hyper-V host as Administrator
# Target: SEA-DC1
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'
$ExpectedIP = '10.10.10.10'
$ExpectedDNS = '10.10.10.10'
$ExpectedSubnet = '10.10.10.0/24'
$ExpectedSwitch = 'LabSwitch'

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "VM $VMName is not running."
}

$NIC = @(
    Get-VMNetworkAdapter -VMName $VMName |
    Where-Object SwitchName -eq $ExpectedSwitch
)

if ($NIC.Count -ne 1) {
    throw "Expected exactly one adapter on $ExpectedSwitch."
}

$Credential = Get-Credential `
    -UserName '.\Administrator' `
    -Message "Enter password for $VMName"

$Session = $null

try {

    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList $ExpectedIP, $ExpectedDNS, $ExpectedSubnet `
        -ScriptBlock {

            param(
                [string]$ExpectedIP,
                [string]$ExpectedDNS,
                [string]$ExpectedSubnet
            )

            $ErrorActionPreference = 'Stop'

            $IP = Get-NetIPAddress `
                -IPAddress $ExpectedIP `
                -AddressFamily IPv4 `
                -ErrorAction Stop

            $Index = $IP.InterfaceIndex

            $DNS = @(
                (Get-DnsClientServerAddress `
                    -InterfaceIndex $Index `
                    -AddressFamily IPv4).ServerAddresses
            )

            $Gateway = @(
                Get-NetRoute `
                    -InterfaceIndex $Index `
                    -AddressFamily IPv4 `
                    -DestinationPrefix '0.0.0.0/0' `
                    -ErrorAction SilentlyContinue
            )

            $Route = @(
                Get-NetRoute `
                    -InterfaceIndex $Index `
                    -AddressFamily IPv4 |
                Where-Object {
                    $_.DestinationPrefix -eq $ExpectedSubnet -and
                    $_.NextHop -eq '0.0.0.0'
                }
            )

            $OS = Get-CimInstance Win32_OperatingSystem

            $ADDS = Get-WindowsFeature `
                -Name AD-Domain-Services

            $DNSRole = Get-WindowsFeature `
                -Name DNS

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                OS = $OS.Caption
                IPv4 = $IP.IPAddress
                Prefix = $IP.PrefixLength
                DNS = $DNS -join ', '
                NoGateway = ($Gateway.Count -eq 0)
                LabRoute = ($Route.Count -gt 0)
                TimeZone = (Get-TimeZone).Id
                ADDSInstalled = $ADDS.Installed
                DNSInstalled = $DNSRole.Installed
            }
        } `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "LAB 2 - PRE-CONFIGURATION REPORT" `
        -ForegroundColor Cyan

    $Result |
        Format-List |
        Out-Host

    $NetworkOK = (
        $Result.ComputerName -eq $VMName -and
        $Result.IPv4 -eq $ExpectedIP -and
        $Result.Prefix -eq 24 -and
        $Result.DNS -eq $ExpectedDNS -and
        $Result.NoGateway -and
        $Result.LabRoute
    )

    Write-Host "Network configuration OK: $NetworkOK"

    if (-not $NetworkOK) {
        Write-Warning "Check network settings before LAB 2."
    }
}
finally {
    if ($null -ne $Session) {
        Remove-PSSession -Session $Session
    }
}
