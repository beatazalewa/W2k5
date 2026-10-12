# ==========================================================
# LAB 1 - Verify ARP and routing on all Hyper-V VMs
# Run on Hyper-V HOST as Administrator
# Uses PowerShell Direct
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMs = [ordered]@{
    'SEA-DC1'  = '10.10.10.10'
    'SEA-SRV1' = '10.10.10.20'
    'SEA-SRV2' = '10.10.10.30'
    'SEA-CL1'  = '10.10.10.100'
}

Import-Module Hyper-V -ErrorAction Stop

$Results = [System.Collections.Generic.List[object]]::new()

foreach ($VMName in $VMs.Keys) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "===================================="
        Write-Host "Checking VM: $VMName" -ForegroundColor Cyan
        Write-Host "===================================="

        # Verify VM state on the host
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "$VMName is not running."
        }

        # Pre-fill the local administrator username
        $UserName = if ($VMName -eq 'SEA-CL1') {
            '.\Admin'
        }
        else {
            '.\Administrator'
        }

        $Credential = Get-Credential `
            -UserName $UserName `
            -Message "Enter password for $VMName"

        if ($null -eq $Credential) {
            throw "Credentials not provided."
        }

        # Connect using PowerShell Direct
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        $GuestResult = Invoke-Command `
            -Session $Session `
            -ArgumentList $VMName, $VMs `
            -ScriptBlock {

                param($SourceVM, $Computers)

                $ErrorActionPreference = 'Stop'

                # Generate ARP traffic to other VMs
                foreach ($Target in $Computers.Keys) {

                    if ($Target -ne $SourceVM) {
                        Test-Connection `
                            -ComputerName $Computers[$Target] `
                            -Count 1 `
                            -Quiet `
                            -ErrorAction SilentlyContinue |
                            Out-Null
                    }
                }

                # Find the laboratory IPv4 interface
                $LabIP = $Computers[$SourceVM]

                $IPConfig = Get-NetIPAddress `
                    -IPAddress $LabIP `
                    -AddressFamily IPv4 `
                    -ErrorAction Stop

                $Index = $IPConfig.InterfaceIndex

                # Collect ARP neighbor information
                $Neighbors = @(
                    Get-NetNeighbor `
                        -InterfaceIndex $Index `
                        -AddressFamily IPv4 |
                    Where-Object {
                        $_.IPAddress -in @($Computers.Values)
                    } |
                    Select-Object IPAddress, LinkLayerAddress, State
                )

                # Collect routes for the lab interface
                $Routes = @(
                    Get-NetRoute `
                        -InterfaceIndex $Index `
                        -AddressFamily IPv4 |
                    Select-Object DestinationPrefix, NextHop, InterfaceAlias
                )

                # Verify route to the laboratory subnet
                $LabRoute = @(
                    $Routes |
                    Where-Object {
                        $_.DestinationPrefix -eq '10.10.10.0/24' -and
                        $_.NextHop -eq '0.0.0.0'
                    }
                )

                # Verify absence of default route
                $DefaultRoute = @(
                    Get-NetRoute `
                        -AddressFamily IPv4 `
                        -DestinationPrefix '0.0.0.0/0' `
                        -ErrorAction SilentlyContinue
                )

                [PSCustomObject]@{
                    VMName          = $SourceVM
                    ComputerName    = $env:COMPUTERNAME
                    IPAddress       = $LabIP
                    ARPEntries      = $Neighbors
                    Routes          = $Routes
                    LabRouteOK      = ($LabRoute.Count -gt 0)
                    NoDefaultRoute  = ($DefaultRoute.Count -eq 0)
                }
            } `
            -ErrorAction Stop

        # Display individual VM results
        Write-Host "ARP entries:" -ForegroundColor Yellow
        $GuestResult.ARPEntries |
            Format-Table IPAddress, LinkLayerAddress, State -AutoSize |
            Out-Host

        Write-Host "Routing table:" -ForegroundColor Yellow
        $GuestResult.Routes |
            Format-Table DestinationPrefix, NextHop, InterfaceAlias -AutoSize |
            Out-Host

        # Store structured summary
        $Results.Add(
            [PSCustomObject]@{
                VMName         = $VMName
                IPAddress      = $GuestResult.IPAddress
                ARPCount       = @($GuestResult.ARPEntries).Count
                LabRouteOK     = $GuestResult.LabRouteOK
                NoDefaultRoute = $GuestResult.NoDefaultRoute
                Status         = 'OK'
            }
        )
    }
    catch {
        Write-Warning ("{0}: {1}" -f $VMName, $_.Exception.Message)

        $Results.Add(
            [PSCustomObject]@{
                VMName         = $VMName
                IPAddress      = $VMs[$VMName]
                ARPCount       = 0
                LabRouteOK     = $false
                NoDefaultRoute = $false
                Status         = 'ERROR'
            }
        )
    }
    finally {
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# Final report
Write-Host ""
Write-Host "===================================="
Write-Host "LAB 1 - ARP AND ROUTING REPORT"
Write-Host "===================================="

$Results |
    Format-Table VMName, IPAddress, ARPCount,
        LabRouteOK, NoDefaultRoute, Status -AutoSize |
    Out-Host
