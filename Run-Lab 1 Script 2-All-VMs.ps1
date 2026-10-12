# ==========================================================
# LAB 1 - Configure IPv4 on Hyper-V virtual machines
# Run ONLY on the Hyper-V host as Administrator
# Network configuration is executed INSIDE each guest VM
# No PowerShell scripts are executed from guest disk
# ==========================================================

$ErrorActionPreference = 'Stop'

# Virtual machines and their configuration
$VMConfig = [ordered]@{
    'SEA-DC1' = @{
        IP   = '10.10.10.10'
        User = 'Administrator'
    }
    'SEA-SRV1' = @{
        IP   = '10.10.10.20'
        User = 'Administrator'
    }
    'SEA-SRV2' = @{
        IP   = '10.10.10.30'
        User = 'Administrator'
    }
    'SEA-CL1' = @{
        IP   = '10.10.10.100'
        User = 'Admin'
    }
}

$PrefixLength = 24
$DnsServer = '10.10.10.10'
$SwitchName = 'LabSwitch'

# Hyper-V module is loaded ONLY on the host
Import-Module Hyper-V -ErrorAction Stop

# Verify the laboratory switch
$Switch = Get-VMSwitch -Name $SwitchName -ErrorAction Stop

if ($Switch.SwitchType -ne 'Internal') {
    throw "LabSwitch must be an Internal switch."
}

# Process each VM separately
$Results = foreach ($VMName in $VMConfig.Keys) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "===================================="
        Write-Host "Processing VM: $VMName" -ForegroundColor Cyan
        Write-Host "===================================="

        # Verify the virtual machine
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "$VMName is not running."
        }

        # Ensure the VM uses LabSwitch
        $LabNICs = @(
            Get-VMNetworkAdapter -VMName $VMName |
            Where-Object SwitchName -eq $SwitchName
        )

        if ($LabNICs.Count -ne 1) {
            throw "Expected one adapter connected to LabSwitch."
        }

        # Prepare credentials
        $UserName = '.\' + $VMConfig[$VMName].User

        $Credential = Get-Credential `
            -UserName $UserName `
            -Message "Enter password for $UserName on $VMName"

        if ($null -eq $Credential) {
            throw "Credentials not provided."
        }

        # Establish PowerShell Direct session
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        $ExpectedIP = $VMConfig[$VMName].IP

        # Execute network commands INSIDE the VM
        $Result = Invoke-Command `
            -Session $Session `
            -ArgumentList $ExpectedIP, $PrefixLength, $DnsServer `
            -ScriptBlock {

                param(
                    [string]$IPAddress,
                    [int]$PrefixLength,
                    [string]$DnsServer
                )

                $ErrorActionPreference = 'Stop'

                # Find the active network adapter
                $Adapters = @(
                    Get-NetAdapter |
                    Where-Object Status -eq 'Up'
                )

                if ($Adapters.Count -ne 1) {
                    throw "Expected one active network adapter. Found $($Adapters.Count)."
                }

                $NIC = $Adapters[0]
                $Index = $NIC.ifIndex

                # Check for IP conflicts on other local adapters
                $Conflicts = @(
                    Get-NetIPAddress -AddressFamily IPv4 |
                    Where-Object {
                        $_.IPAddress -eq $IPAddress -and
                        $_.InterfaceIndex -ne $Index
                    }
                )

                if ($Conflicts.Count -gt 0) {
                    throw "IP address is assigned to another local adapter."
                }

                # Disable DHCP
                Set-NetIPInterface `
                    -InterfaceIndex $Index `
                    -AddressFamily IPv4 `
                    -Dhcp Disabled

                # Remove previous IPv4 addresses except desired IP
                $OldIPs = @(
                    Get-NetIPAddress `
                        -InterfaceIndex $Index `
                        -AddressFamily IPv4 |
                    Where-Object {
                        $_.IPAddress -ne $IPAddress -and
                        $_.IPAddress -notlike '169.254.*'
                    }
                )

                foreach ($OldIP in $OldIPs) {
                    Remove-NetIPAddress `
                        -InputObject $OldIP `
                        -Confirm:$false
                }

                # Remove default gateway from lab interface
                $Routes = @(
                    Get-NetRoute `
                        -InterfaceIndex $Index `
                        -DestinationPrefix '0.0.0.0/0' `
                        -ErrorAction SilentlyContinue
                )

                foreach ($Route in $Routes) {
                    Remove-NetRoute `
                        -InputObject $Route `
                        -Confirm:$false
                }

                # Configure required IPv4 address
                $CurrentIP = Get-NetIPAddress `
                    -InterfaceIndex $Index `
                    -IPAddress $IPAddress `
                    -ErrorAction SilentlyContinue

                if (-not $CurrentIP) {
                    New-NetIPAddress `
                        -InterfaceIndex $Index `
                        -IPAddress $IPAddress `
                        -PrefixLength $PrefixLength |
                        Out-Null
                }
                elseif ($CurrentIP.PrefixLength -ne $PrefixLength) {
                    Set-NetIPAddress `
                        -InputObject $CurrentIP `
                        -PrefixLength $PrefixLength
                }

                # Configure future domain DNS
                Set-DnsClientServerAddress `
                    -InterfaceIndex $Index `
                    -ServerAddresses $DnsServer

                # Verify actual configuration
                $ActualIP = Get-NetIPAddress `
                    -InterfaceIndex $Index `
                    -IPAddress $IPAddress `
                    -ErrorAction Stop

                $ActualDNS = @(
                    (Get-DnsClientServerAddress `
                        -InterfaceIndex $Index `
                        -AddressFamily IPv4).ServerAddresses
                )

                if ($IPAddress -notin @($ActualIP.IPAddress)) {
                    throw "IPv4 verification failed."
                }

                if ($DnsServer -notin $ActualDNS) {
                    throw "DNS verification failed."
                }

                # Return structured results
                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    Adapter      = $NIC.Name
                    IPAddress    = $IPAddress
                    PrefixLength = $PrefixLength
                    DNS          = $ActualDNS -join ', '
                    Status       = 'OK'
                }
            } `
            -ErrorAction Stop

        Write-Host "$VMName configured successfully." `
            -ForegroundColor Green

        [PSCustomObject]@{
            VMName       = $VMName
            ComputerName = $Result.ComputerName
            IPAddress    = $Result.IPAddress
            DNS          = $Result.DNS
            Status       = 'OK'
            Error        = ''
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message

        Write-Warning ("{0}: {1}" -f $VMName, $ErrorMessage)

        [PSCustomObject]@{
            VMName       = $VMName
            ComputerName = ''
            IPAddress    = $VMConfig[$VMName].IP
            DNS          = ''
            Status       = 'FAILED'
            Error        = $ErrorMessage
        }
    }
    finally {
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# Display final report
Write-Host ""
Write-Host "===================================="
Write-Host "LAB 1 - NETWORK CONFIGURATION REPORT"
Write-Host "===================================="

$Results |
    Format-Table VMName, ComputerName, IPAddress, DNS, Status, Error -AutoSize
