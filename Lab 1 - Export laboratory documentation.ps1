# ==============================================================
# LAB 1 - Export Laboratory Documentation
# Expected vs Actual IPv4, DNS, Routing and Hyper-V
#
# Run ONLY on Hyper-V host as Administrator
# PowerShell Direct - no WinRM or network access required
# ==============================================================

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------
# 1. Configuration
# --------------------------------------------------------------

$ReportPath = 'C:\LabReports'
$LabSwitch = 'LabSwitch'
$LabSubnet = '10.10.10.0/24'
$ExpectedDNS = '10.10.10.10'
$ExpectedPrefix = 24
$ExpectedCheckpoint = 'LAB01-Network-Ready'

$VMs = [ordered]@{
    'SEA-DC1'  = @{
        IP   = '10.10.10.10'
        User = '.\Administrator'
    }
    'SEA-SRV1' = @{
        IP   = '10.10.10.20'
        User = '.\Administrator'
    }
    'SEA-SRV2' = @{
        IP   = '10.10.10.30'
        User = '.\Administrator'
    }
    'SEA-CL1'  = @{
        IP   = '10.10.10.100'
        User = '.\Admin'
    }
}

New-Item -ItemType Directory -Path $ReportPath -Force |
    Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$SummaryCSV = Join-Path $ReportPath "LAB01-Summary_$Timestamp.csv"
$NetworkCSV = Join-Path $ReportPath "LAB01-Network_$Timestamp.csv"
$CheckpointCSV = Join-Path $ReportPath "LAB01-Checkpoints_$Timestamp.csv"
$ReportTXT = Join-Path $ReportPath "LAB01-Report_$Timestamp.txt"
$ReportHTML = Join-Path $ReportPath "LAB01-Report_$Timestamp.html"

# --------------------------------------------------------------
# 2. Verify host
# --------------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw 'Get-VM is unavailable. Run on the Hyper-V host.'
}

$Switch = Get-VMSwitch -Name $LabSwitch -ErrorAction Stop

Write-Host ""
Write-Host "========================================"
Write-Host "LAB 1 - EXPORT DOCUMENTATION"
Write-Host "========================================"
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Switch: $LabSwitch"
Write-Host "Network: $LabSubnet"
Write-Host ""

# --------------------------------------------------------------
# 3. Result collections
# --------------------------------------------------------------

$Summary = [System.Collections.Generic.List[object]]::new()
$Network = [System.Collections.Generic.List[object]]::new()
$CheckpointsReport = [System.Collections.Generic.List[object]]::new()

# --------------------------------------------------------------
# 4. Process virtual machines
# --------------------------------------------------------------

foreach ($VMName in $VMs.Keys) {

    $Session = $null
    $ExpectedIP = $VMs[$VMName].IP
    $UserName = $VMs[$VMName].User

    $ActualComputerName = ''
    $ActualIP = ''
    $ActualPrefix = ''
    $ActualDNS = ''
    $ActualGateway = ''
    $ActualLabRoute = $false
    $ActualAdapter = ''

    $VMState = ''
    $LabSwitchConnected = $false
    $CheckpointExists = $false
    $VMGeneration = ''
    $CPUCount = ''
    $MemoryGB = ''

    $Status = 'ERROR'
    $ErrorMessage = ''

    Write-Host ""
    Write-Host "========================================"
    Write-Host "Processing: $VMName" -ForegroundColor Cyan
    Write-Host "========================================"

    try {

        # ------------------------------------------------------
        # HOST: Read Hyper-V configuration
        # ------------------------------------------------------

        $VM = Get-VM -Name $VMName -ErrorAction Stop

        $VMState = [string]$VM.State
        $VMGeneration = $VM.Generation
        $CPUCount = $VM.ProcessorCount
        $MemoryGB = [math]::Round($VM.MemoryAssigned / 1GB, 2)

        if ($VM.State -ne 'Running') {
            throw "VM is not running: $VMName"
        }

        $NICs = @(
            Get-VMNetworkAdapter `
                -VMName $VMName `
                -ErrorAction Stop
        )

        $LabNICs = @(
            $NICs | Where-Object {
                $_.SwitchName -eq $LabSwitch
            }
        )

        $LabSwitchConnected = ($LabNICs.Count -eq 1)

        foreach ($NIC in $NICs) {

            $Network.Add(
                [PSCustomObject]@{
                    VMName     = $VMName
                    Adapter    = $NIC.Name
                    SwitchName = $NIC.SwitchName
                    MACAddress = $NIC.MacAddress
                    Status     = [string]$NIC.Status
                }
            )
        }

        if ($LabNICs.Count -ne 1) {
            throw "Expected exactly one adapter on $LabSwitch; found $($LabNICs.Count)."
        }

        $LabMac = $LabNICs[0].MacAddress

        # ------------------------------------------------------
        # HOST: Read checkpoint information
        # ------------------------------------------------------

        $VMCheckpoints = @(
            Get-VMSnapshot `
                -VMName $VMName `
                -ErrorAction Stop
        )

        $CheckpointExists = @(
            $VMCheckpoints | Where-Object {
                $_.Name -eq $ExpectedCheckpoint
            }
        ).Count -gt 0

        foreach ($Checkpoint in $VMCheckpoints) {

            $CheckpointsReport.Add(
                [PSCustomObject]@{
                    VMName         = $VMName
                    CheckpointName = $Checkpoint.Name
                    CreationTime   = $Checkpoint.CreationTime
                    SnapshotType   = $Checkpoint.SnapshotType
                }
            )
        }

        # ------------------------------------------------------
        # HOST: Request credentials
        # ------------------------------------------------------

        $Credential = Get-Credential `
            -UserName $UserName `
            -Message "Enter password for $VMName"

        if ($null -eq $Credential) {
            throw 'Credentials not provided.'
        }

        # ------------------------------------------------------
        # HOST: Connect to guest using PowerShell Direct
        # ------------------------------------------------------

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # ------------------------------------------------------
        # GUEST: Read actual Windows network configuration
        # ------------------------------------------------------

        $GuestResult = Invoke-Command `
            -Session $Session `
            -ArgumentList $LabMac, $LabSubnet `
            -ScriptBlock {

                param(
                    [string]$LabMac,
                    [string]$LabSubnet
                )

                $ErrorActionPreference = 'Stop'

                # Match the guest network adapter to the
                # Hyper-V adapter MAC address
                $NormalizedMac = $LabMac -replace '[^0-9A-Fa-f]', ''

                $Adapters = @(
                    Get-NetAdapter | Where-Object {
                        ($_.MacAddress -replace '[^0-9A-Fa-f]', '') -eq
                        $NormalizedMac
                    }
                )

                if ($Adapters.Count -ne 1) {
                    throw "Cannot uniquely identify laboratory adapter by MAC: $LabMac"
                }

                $Adapter = $Adapters[0]
                $Index = $Adapter.ifIndex

                # Read actual IPv4 addresses
                $Addresses = @(
                    Get-NetIPAddress `
                        -InterfaceIndex $Index `
                        -AddressFamily IPv4 `
                        -ErrorAction Stop |
                    Where-Object {
                        $_.IPAddress -notlike '169.254.*'
                    }
                )

                $ActualIPs = @(
                    $Addresses | ForEach-Object {
                        $_.IPAddress
                    }
                )

                $ActualPrefixes = @(
                    $Addresses | ForEach-Object {
                        $_.PrefixLength
                    }
                )

                # Read actual IPv4 DNS servers
                $DNSConfig = Get-DnsClientServerAddress `
                    -InterfaceIndex $Index `
                    -AddressFamily IPv4 `
                    -ErrorAction Stop

                $DNSServers = @($DNSConfig.ServerAddresses)

                # Read actual IPv4 default routes
                $DefaultRoutes = @(
                    Get-NetRoute `
                        -InterfaceIndex $Index `
                        -AddressFamily IPv4 `
                        -DestinationPrefix '0.0.0.0/0' `
                        -ErrorAction SilentlyContinue
                )

                $Gateways = @(
                    $DefaultRoutes | ForEach-Object {
                        $_.NextHop
                    }
                )

                # Verify direct route to the laboratory network
                $Routes = @(
                    Get-NetRoute `
                        -InterfaceIndex $Index `
                        -AddressFamily IPv4 `
                        -ErrorAction Stop
                )

                $LabRouteExists = @(
                    $Routes | Where-Object {
                        $_.DestinationPrefix -eq $LabSubnet -and
                        $_.NextHop -eq '0.0.0.0'
                    }
                ).Count -gt 0

                [PSCustomObject]@{
                    ComputerName   = $env:COMPUTERNAME
                    AdapterName    = $Adapter.Name
                    AdapterStatus  = [string]$Adapter.Status
                    IPv4Addresses  = @($ActualIPs)
                    PrefixLengths  = @($ActualPrefixes)
                    DNSServers     = @($DNSServers)
                    Gateways       = @($Gateways)
                    LabRouteExists = $LabRouteExists
                }
            } `
            -ErrorAction Stop

        # ------------------------------------------------------
        # HOST: Normalize actual results
        # ------------------------------------------------------

        $ActualComputerName = $GuestResult.ComputerName
        $ActualAdapter = $GuestResult.AdapterName

        $ActualIPs = @($GuestResult.IPv4Addresses)
        $ActualPrefixes = @($GuestResult.PrefixLengths)
        $ActualDNSList = @($GuestResult.DNSServers)
        $ActualGateways = @($GuestResult.Gateways)

        $ActualIP = $ActualIPs -join ', '
        $ActualPrefix = $ActualPrefixes -join ', '
        $ActualDNS = $ActualDNSList -join ', '

        if ($ActualGateways.Count -eq 0) {
            $ActualGateway = 'None'
        }
        else {
            $ActualGateway = $ActualGateways -join ', '
        }

        $ActualLabRoute = [bool]$GuestResult.LabRouteExists

        # ------------------------------------------------------
        # HOST: Compare expected vs actual
        # ------------------------------------------------------

        $NameOK = ($ActualComputerName -eq $VMName)

        $IPv4OK = (
            $ActualIPs.Count -eq 1 -and
            $ActualIPs[0] -eq $ExpectedIP
        )

        $PrefixOK = (
            $ActualPrefixes.Count -eq 1 -and
            [int]$ActualPrefixes[0] -eq $ExpectedPrefix
        )

        $DNSOK = (
            $ActualDNSList.Count -eq 1 -and
            $ActualDNSList[0] -eq $ExpectedDNS
        )

        $GatewayOK = ($ActualGateways.Count -eq 0)

        $RouteOK = $ActualLabRoute

        $SwitchOK = $LabSwitchConnected

        $AdapterOK = ($GuestResult.AdapterStatus -eq 'Up')

        if (
            $NameOK -and
            $IPv4OK -and
            $PrefixOK -and
            $DNSOK -and
            $GatewayOK -and
            $RouteOK -and
            $SwitchOK -and
            $AdapterOK
        ) {
            $Status = 'PASS'
        }
        else {
            $Status = 'MISMATCH'
        }

        # ------------------------------------------------------
        # HOST: Save per-field comparisons
        # ------------------------------------------------------

        $Summary.Add(
            [PSCustomObject]@{
                VMName           = $VMName
                ActualName       = $ActualComputerName
                NameOK           = $NameOK

                ExpectedIPv4     = $ExpectedIP
                ActualIPv4       = $ActualIP
                IPv4OK           = $IPv4OK

                ExpectedPrefix   = $ExpectedPrefix
                ActualPrefix     = $ActualPrefix
                PrefixOK         = $PrefixOK

                ExpectedDNS      = $ExpectedDNS
                ActualDNS        = $ActualDNS
                DNSOK            = $DNSOK

                ExpectedGateway  = 'None'
                ActualGateway    = $ActualGateway
                GatewayOK        = $GatewayOK

                ExpectedRoute    = $LabSubnet
                ActualRouteOK    = $ActualLabRoute

                ExpectedSwitch   = $LabSwitch
                LabSwitchOK      = $SwitchOK

                AdapterName      = $ActualAdapter
                AdapterOK        = $AdapterOK

                CheckpointName   = $ExpectedCheckpoint
                CheckpointExists = $CheckpointExists

                VMState          = $VMState
                Generation       = $VMGeneration
                ProcessorCount   = $CPUCount
                MemoryGB         = $MemoryGB

                Status           = $Status
                Error            = ''
            }
        )

        $Color = if ($Status -eq 'PASS') {
            'Green'
        }
        else {
            'Yellow'
        }

        Write-Host "$VMName : $Status" -ForegroundColor $Color
        Write-Host "  IPv4: $ActualIP"
        Write-Host "  DNS:  $ActualDNS"
        Write-Host "  Gateway: $ActualGateway"
        Write-Host "  LAB route: $ActualLabRoute"

    }
    catch {

        $ErrorMessage = $_.Exception.Message

        Write-Warning ("{0}: {1}" -f $VMName, $ErrorMessage)

        $Summary.Add(
            [PSCustomObject]@{
                VMName           = $VMName
                ActualName       = $ActualComputerName
                NameOK           = $null

                ExpectedIPv4     = $ExpectedIP
                ActualIPv4       = $ActualIP
                IPv4OK           = $null

                ExpectedPrefix   = $ExpectedPrefix
                ActualPrefix     = $ActualPrefix
                PrefixOK         = $null

                ExpectedDNS      = $ExpectedDNS
                ActualDNS        = $ActualDNS
                DNSOK            = $null

                ExpectedGateway  = 'None'
                ActualGateway    = $ActualGateway
                GatewayOK        = $null

                ExpectedRoute    = $LabSubnet
                ActualRouteOK    = $null

                ExpectedSwitch   = $LabSwitch
                LabSwitchOK      = $LabSwitchConnected

                AdapterName      = $ActualAdapter
                AdapterOK        = $null

                CheckpointName   = $ExpectedCheckpoint
                CheckpointExists = $CheckpointExists

                VMState          = $VMState
                Generation       = $VMGeneration
                ProcessorCount   = $CPUCount
                MemoryGB         = $MemoryGB

                Status           = 'ERROR'
                Error            = $ErrorMessage
            }
        )
    }
    finally {

        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# --------------------------------------------------------------
# 5. Export CSV reports
# --------------------------------------------------------------

$Summary |
    Export-Csv `
        -Path $SummaryCSV `
        -NoTypeInformation `
        -Encoding UTF8

if ($Network.Count -gt 0) {
    $Network |
        Export-Csv `
            -Path $NetworkCSV `
            -NoTypeInformation `
            -Encoding UTF8
}

if ($CheckpointsReport.Count -gt 0) {
    $CheckpointsReport |
        Export-Csv `
            -Path $CheckpointCSV `
            -NoTypeInformation `
            -Encoding UTF8
}

# --------------------------------------------------------------
# 6. Export TXT report
# --------------------------------------------------------------

$TXT = @()

$TXT += 'LAB 1 - NETWORK CONFIGURATION DOCUMENTATION'
$TXT += '==========================================='
$TXT += "Host: $env:COMPUTERNAME"
$TXT += "Date: $(Get-Date)"
$TXT += "Switch: $LabSwitch"
$TXT += "Subnet: $LabSubnet"
$TXT += ''

$TXT += 'EXPECTED VS ACTUAL CONFIGURATION'
$TXT += '==========================================='

$TXT += (
    $Summary |
    Format-List |
    Out-String -Width 180
)

$TXT += ''
$TXT += 'NETWORK ADAPTERS'
$TXT += '==========================================='

$TXT += (
    $Network |
    Format-Table -AutoSize |
    Out-String -Width 180
)

$TXT += ''
$TXT += 'CHECKPOINTS'
$TXT += '==========================================='

if ($CheckpointsReport.Count -gt 0) {
    $TXT += (
        $CheckpointsReport |
        Format-Table -AutoSize |
        Out-String -Width 180
    )
}
else {
    $TXT += 'No checkpoints found.'
}

$TXT |
    Out-File -FilePath $ReportTXT -Encoding UTF8

# --------------------------------------------------------------
# 7. Export HTML report
# --------------------------------------------------------------

$HTMLStyle = @"
<meta charset="utf-8">
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    background: #f5f9fb;
    color: #294554;
}
h1, h2 {
    color: #146393;
}
h1 {
    padding-bottom: 12px;
    border-bottom: 3px solid #146393;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin: 20px 0 35px 0;
    background: white;
    font-size: 13px;
}
th {
    background: #146393;
    color: white;
    padding: 10px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 8px;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
</style>
"@

$HTMLBody = @()

$HTMLBody += '<h1>LAB 1 - Laboratory Documentation</h1>'
$HTMLBody += "<p><strong>Host:</strong> $env:COMPUTERNAME</p>"
$HTMLBody += "<p><strong>Date:</strong> $(Get-Date)</p>"
$HTMLBody += "<p><strong>Network:</strong> $LabSubnet</p>"
$HTMLBody += "<p><strong>Switch:</strong> $LabSwitch</p>"

$HTMLBody += '<h2>Expected vs Actual Configuration</h2>'

$HTMLBody += (
    $Summary |
    Select-Object `
        VMName,
        ExpectedIPv4,
        ActualIPv4,
        IPv4OK,
        ExpectedPrefix,
        ActualPrefix,
        PrefixOK,
        ExpectedDNS,
        ActualDNS,
        DNSOK,
        ExpectedGateway,
        ActualGateway,
        GatewayOK,
        ActualRouteOK,
        LabSwitchOK,
        CheckpointExists,
        Status,
        Error |
    ConvertTo-Html -Fragment
)

$HTMLBody += '<h2>Hyper-V Network Adapters</h2>'

$HTMLBody += (
    $Network |
    ConvertTo-Html -Fragment
)

$HTMLBody += '<h2>Checkpoints</h2>'

if ($CheckpointsReport.Count -gt 0) {
    $HTMLBody += (
        $CheckpointsReport |
        ConvertTo-Html -Fragment
    )
}
else {
    $HTMLBody += '<p>No checkpoints found.</p>'
}

ConvertTo-Html `
    -Title 'LAB 1 - Laboratory Documentation' `
    -Head $HTMLStyle `
    -Body ($HTMLBody -join "`n") |
    Out-File `
        -FilePath $ReportHTML `
        -Encoding UTF8

# --------------------------------------------------------------
# 8. Final report
# --------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host "LAB 1 - EXPECTED VS ACTUAL REPORT"
Write-Host "========================================"

$Summary |
    Format-Table `
        VMName,
        ExpectedIPv4,
        ActualIPv4,
        IPv4OK,
        ActualDNS,
        DNSOK,
        GatewayOK,
        ActualRouteOK,
        Status `
        -AutoSize |
    Out-Host

$Passed = @($Summary | Where-Object Status -eq 'PASS').Count
$Mismatch = @($Summary | Where-Object Status -eq 'MISMATCH').Count
$Errors = @($Summary | Where-Object Status -eq 'ERROR').Count

Write-Host ""
Write-Host "Passed:   $Passed" -ForegroundColor Green
Write-Host "Mismatch: $Mismatch" -ForegroundColor Yellow
Write-Host "Errors:   $Errors" -ForegroundColor Red

Write-Host ""
Write-Host "Reports saved to: $ReportPath" -ForegroundColor Cyan

Write-Host $SummaryCSV
Write-Host $NetworkCSV
Write-Host $ReportTXT
Write-Host $ReportHTML

if ($CheckpointsReport.Count -gt 0) {
    Write-Host $CheckpointCSV
}

if ($Passed -eq $VMs.Count) {
    Write-Host ""
    Write-Host "LAB 1 - ALL CONFIGURATIONS VERIFIED" `
        -ForegroundColor Green
}
else {
    Write-Warning 'Some VM configurations require attention.'
}
