# =============================================================
# LAB 1 Script 2 - Configure guest IPv4 addresses using PowerShell Direct
# Run on the Hyper-V HOST as Administrator (Windows PowerShell)
# This script does NOT configure network interfaces on the host.
# =============================================================

$ErrorActionPreference = 'Stop'
#Import-Module Hyper-V -ErrorAction Stop

$VMConfig = [ordered]@{
    'SEA-DC1'  = @{ IP = '10.10.10.10';  User = 'Administrator' }
    'SEA-SRV1' = @{ IP = '10.10.10.20';  User = 'Administrator' }
    'SEA-SRV2' = @{ IP = '10.10.10.30';  User = 'Administrator' }
    'SEA-CL1'  = @{ IP = '10.10.10.100'; User = 'Admin' }
}

$PrefixLength = 24
$DnsServer = '10.10.10.10'

$Results = foreach ($VMName in $VMConfig.Keys) {
    try {
        $VM = Get-VM -Name $VMName -ErrorAction Stop
        if ($VM.State -ne 'Running') {
            throw "VM $VMName is not running."
        }

        # Pre-fill the local user name; prompt separately for each VM.
        $UserName = '.\' + $VMConfig[$VMName].User
        $Credential = Get-Credential -UserName $UserName `
            -Message "Enter the password for $UserName on $VMName"
        if ($null -eq $Credential) {
            throw "Credentials not provided for $VMName."
        }

        $DesiredIP = $VMConfig[$VMName].IP
        Write-Host "Configuring $VMName ($DesiredIP) ..." -ForegroundColor Cyan

        # All guest configuration runs inside this remote script block.
        $Result = Invoke-Command -VMName $VMName -Credential $Credential `
            -ArgumentList $DesiredIP, $PrefixLength, $DnsServer `
            -ScriptBlock {
                param([string]$IPAddress, [int]$PrefixLength, [string]$DnsServer)
                $ErrorActionPreference = 'Stop'

                # Safety: require exactly one active Hyper-V synthetic NIC.
                $Adapters = @(
                    Get-NetAdapter | Where-Object {
                        $_.Status -eq 'Up' -and
                        $_.InterfaceDescription -like '*Hyper-V*'
                    }
                )
                if ($Adapters.Count -ne 1) {
                    throw "Expected one active Hyper-V adapter; found $($Adapters.Count)."
                }

                $Index = $Adapters[0].ifIndex

                # Do not alter a different interface carrying the desired address.
                $Conflicts = @(Get-NetIPAddress -AddressFamily IPv4 |
                    Where-Object {
                        $_.IPAddress -eq $IPAddress -and
                        $_.InterfaceIndex -ne $Index
                    })
                if ($Conflicts.Count -gt 0) {
                    throw "Address $IPAddress already belongs to another local adapter."
                }

                Set-NetIPInterface -InterfaceIndex $Index -AddressFamily IPv4 -Dhcp Disabled

                # Remove obsolete manual IPv4 addresses from the lab NIC.
                Get-NetIPAddress -InterfaceIndex $Index -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.PrefixOrigin -eq 'Manual' -and
                        $_.IPAddress -ne $IPAddress
                    } | Remove-NetIPAddress -Confirm:$false

                # Isolated LabSwitch network: no default gateway.
                Get-NetRoute -InterfaceIndex $Index -DestinationPrefix '0.0.0.0/0' `
                    -ErrorAction SilentlyContinue |
                    Remove-NetRoute -Confirm:$false

                $Current = Get-NetIPAddress -InterfaceIndex $Index `
                    -IPAddress $IPAddress -ErrorAction SilentlyContinue

                if (-not $Current) {
                    New-NetIPAddress -InterfaceIndex $Index -IPAddress $IPAddress `
                        -PrefixLength $PrefixLength | Out-Null
                }
                elseif ($Current.PrefixLength -ne $PrefixLength) {
                    Set-NetIPAddress -InputObject $Current -PrefixLength $PrefixLength
                }

                Set-DnsClientServerAddress -InterfaceIndex $Index -ServerAddresses $DnsServer

                $Verified = Get-NetIPAddress -InterfaceIndex $Index -IPAddress $IPAddress `
                    -ErrorAction Stop
                if ($Verified.PrefixLength -ne $PrefixLength) {
                    throw 'IPv4 prefix verification failed.'
                }

                [PSCustomObject]@{
                    GuestName = $env:COMPUTERNAME
                    Address   = $Verified.IPAddress
                    Prefix    = $Verified.PrefixLength
                    Adapter   = $Adapters[0].Name
                }
            } -ErrorAction Stop

        Write-Host "$VMName - OK: $($Result.Address)/$($Result.Prefix)" -ForegroundColor Green
        [PSCustomObject]@{
            VMName = $VMName; GuestName = $Result.GuestName
            IP = $Result.Address; Status = 'OK'; Error = ''
        }
    }
    catch {
        Write-Warning ("{0}: {1}" -f $VMName, $_.Exception.Message)
        [PSCustomObject]@{
            VMName = $VMName; GuestName = ''; IP = $VMConfig[$VMName].IP
            Status = 'FAILED'; Error = $_.Exception.Message
        }
    }
}

Write-Host "`nLAB 1 - Guest IP configuration results" -ForegroundColor Cyan
$Results | Format-Table VMName, GuestName, IP, Status, Error -AutoSize
