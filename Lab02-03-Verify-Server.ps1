# ==========================================================
# LAB 2 - Script 03
# Verify Windows Server 2025 Initial Configuration
#
# Run ONLY on Hyper-V host as Administrator
# Target VM: SEA-DC1
# Connection: PowerShell Direct
#
# Read-only verification of VM and guest configuration
# Reports: CSV, TXT, HTML
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Expected configuration
# ----------------------------------------------------------

$VMName = 'SEA-DC1'
$ExpectedIP = '10.10.10.10'
$ExpectedPrefix = 24
$ExpectedDNS = '10.10.10.10'
$ExpectedSubnet = '10.10.10.0/24'
$ExpectedSwitch = 'LabSwitch'
$ExpectedTimeZone = 'Central European Standard Time'
$ExpectedFirewallRule = 'LAB01-Allow-ICMPv4'
$MinimumLogSize = 64MB

$ReportPath = 'C:\LabReports'

New-Item `
    -Path $ReportPath `
    -ItemType Directory `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSVPath = Join-Path $ReportPath `
    "LAB02-Verification_$Timestamp.csv"

$TXTPath = Join-Path $ReportPath `
    "LAB02-Verification_$Timestamp.txt"

$HTMLPath = Join-Path $ReportPath `
    "LAB02-Verification_$Timestamp.html"

# ----------------------------------------------------------
# 2. Verify host and virtual machine
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V commands are unavailable on this host.'
}

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "Virtual machine $VMName is not running."
}

$LabAdapters = @(
    Get-VMNetworkAdapter -VMName $VMName |
    Where-Object {
        $_.SwitchName -eq $ExpectedSwitch
    }
)

$SwitchOK = ($LabAdapters.Count -eq 1)

# ----------------------------------------------------------
# 3. Connect using PowerShell Direct
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName '.\Administrator' `
    -Message "Enter password for $VMName"

if ($null -eq $Credential) {
    throw 'Credentials not provided.'
}

$Session = $null

try {

    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 2 - SERVER VERIFICATION"
    Write-Host "=========================================="
    Write-Host "Host: $env:COMPUTERNAME"
    Write-Host "Target: $VMName"
    Write-Host ""

    # ------------------------------------------------------
    # 4. Collect actual guest configuration
    # ------------------------------------------------------

    $Actual = Invoke-Command `
        -Session $Session `
        -ArgumentList $ExpectedFirewallRule `
        -ScriptBlock {

            param([string]$FirewallRuleName)

            $ErrorActionPreference = 'Stop'

            # Operating system and computer identity
            $OS = Get-CimInstance Win32_OperatingSystem
            $Computer = Get-CimInstance Win32_ComputerSystem

            # Read active network adapters
            $Adapters = @(
                Get-NetAdapter |
                Where-Object Status -eq 'Up'
            )

            $NetworkData = @(
                foreach ($Adapter in $Adapters) {

                    $Index = $Adapter.ifIndex

                    $Addresses = @(
                        Get-NetIPAddress `
                            -InterfaceIndex $Index `
                            -AddressFamily IPv4 `
                            -ErrorAction SilentlyContinue |
                        Where-Object {
                            $_.IPAddress -notlike '169.254.*'
                        }
                    )

                    $DNS = @(
                        (Get-DnsClientServerAddress `
                            -InterfaceIndex $Index `
                            -AddressFamily IPv4).ServerAddresses
                    )

                    [PSCustomObject]@{
                        InterfaceIndex = $Index
                        InterfaceAlias = $Adapter.Name
                        IPv4 = @(
                            $Addresses |
                            ForEach-Object IPAddress
                        )
                        Prefix = @(
                            $Addresses |
                            ForEach-Object PrefixLength
                        )
                        DNS = @($DNS)
                    }
                }
            )

            # Read all IPv4 routes
            $Routes = @(
                Get-NetRoute -AddressFamily IPv4 |
                Select-Object `
                    InterfaceIndex,
                    DestinationPrefix,
                    NextHop
            )

            # Read firewall configuration
            $Rule = Get-NetFirewallRule `
                -Name $FirewallRuleName `
                -ErrorAction SilentlyContinue

            $Firewall = $null

            if ($null -ne $Rule) {

                $PortFilter = $Rule |
                    Get-NetFirewallPortFilter

                $AddressFilter = $Rule |
                    Get-NetFirewallAddressFilter

                $Firewall = [PSCustomObject]@{
                    Name = $Rule.Name
                    Enabled = [string]$Rule.Enabled
                    Direction = [string]$Rule.Direction
                    Action = [string]$Rule.Action
                    Profile = [string]$Rule.Profile
                    Protocol = [string]$PortFilter.Protocol
                    IcmpType = [string]$PortFilter.IcmpType
                    RemoteAddress = @(
                        $AddressFilter.RemoteAddress
                    )
                }
            }

            # Read event log settings
            $LogNames = @(
                'Application',
                'System',
                'Security'
            )

            $EventLogs = @(
                foreach ($LogName in $LogNames) {

                    $Log = Get-WinEvent `
                        -ListLog $LogName `
                        -ErrorAction Stop

                    [PSCustomObject]@{
                        Name = $LogName
                        MaximumBytes = [long]$Log.MaximumSizeInBytes
                    }
                }
            )

            # Read server roles
            $ADDS = Get-WindowsFeature `
                -Name AD-Domain-Services

            $DNSRole = Get-WindowsFeature `
                -Name DNS

            # Return structured data
            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                OperatingSystem = $OS.Caption
                OSVersion = $OS.Version
                DomainRole = [int]$Computer.DomainRole
                TimeZone = (Get-TimeZone).Id
                NetworkData = @($NetworkData)
                Routes = @($Routes)
                Firewall = $Firewall
                EventLogs = @($EventLogs)
                ADDSInstalled = [bool]$ADDS.Installed
                DNSInstalled = [bool]$DNSRole.Installed
            }
        } `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 5. Identify the laboratory network interface
    # ------------------------------------------------------

    # Locate the interface using the expected IPv4 address.
    # Do not assume that the interface index is always 10.

    $LabNetwork = @(
        $Actual.NetworkData |
        Where-Object {
            @($_.IPv4) -contains $ExpectedIP
        }
    )

    $LabNetworkFound = ($LabNetwork.Count -eq 1)

    $ActualIP = ''
    $ActualPrefix = ''
    $ActualDNS = ''
    $InterfaceIndex = -1

    if ($LabNetworkFound) {

        $LabInterface = $LabNetwork[0]
        $InterfaceIndex = [int]$LabInterface.InterfaceIndex

        $ActualIP = @($LabInterface.IPv4) -join ', '
        $ActualPrefix = @($LabInterface.Prefix) -join ', '
        $ActualDNS = @($LabInterface.DNS) -join ', '
    }

    # ------------------------------------------------------
    # 6. Verify routing
    # ------------------------------------------------------

    $DefaultRoutes = @(
        $Actual.Routes |
        Where-Object {
            $_.DestinationPrefix -eq '0.0.0.0/0'
        }
    )

    $NoDefaultGateway = ($DefaultRoutes.Count -eq 0)

    $LabRoutes = @(
        $Actual.Routes |
        Where-Object {
            $_.InterfaceIndex -eq $InterfaceIndex -and
            $_.DestinationPrefix -eq $ExpectedSubnet -and
            $_.NextHop -eq '0.0.0.0'
        }
    )

    $LabRouteOK = (
        $LabNetworkFound -and
        $LabRoutes.Count -gt 0
    )

    # ------------------------------------------------------
    # 7. Verify firewall rule
    # ------------------------------------------------------

    $Firewall = $Actual.Firewall

    $FirewallOK = $false
    $FirewallDescription = 'Rule not found'

    if ($null -ne $Firewall) {

        # Windows may show protocol by name or number
        $ProtocolOK = (
            [string]$Firewall.Protocol -in @('ICMPv4', '1')
        )

        $IcmpTypeOK = (
            [string]$Firewall.IcmpType -eq '8'
        )

        # The firewall may normalize CIDR notation
        $AcceptedSubnets = @(
            '10.10.10.0/24',
            '10.10.10.0/255.255.255.0'
        )

        $RemoteAddresses = @($Firewall.RemoteAddress)

        $AddressOK = (
            $RemoteAddresses.Count -eq 1 -and
            [string]$RemoteAddresses[0] -in $AcceptedSubnets
        )

        $FirewallOK = (
            [string]$Firewall.Enabled -eq 'True' -and
            [string]$Firewall.Direction -eq 'Inbound' -and
            [string]$Firewall.Action -eq 'Allow' -and
            [string]$Firewall.Profile -eq 'Any' -and
            $ProtocolOK -and
            $IcmpTypeOK -and
            $AddressOK
        )

        $FirewallDescription = (
            "Enabled={0}; Protocol={1}; ICMP={2}; Remote={3}" -f
            $Firewall.Enabled,
            $Firewall.Protocol,
            $Firewall.IcmpType,
            ($RemoteAddresses -join ', ')
        )
    }

    # ------------------------------------------------------
    # 8. Create expected vs actual checks
    # ------------------------------------------------------

    $Checks = [System.Collections.Generic.List[object]]::new()

    function Add-LabCheck {

        param(
            [string]$Category,
            [string]$Check,
            [string]$Expected,
            [string]$ActualValue,
            [bool]$Passed
        )

        $Checks.Add(
            [PSCustomObject]@{
                Category = $Category
                Check = $Check
                Expected = $Expected
                Actual = $ActualValue
                Status = if ($Passed) { 'PASS' } else { 'FAIL' }
            }
        )
    }

    # Computer identity
    Add-LabCheck `
        'System' `
        'Computer name' `
        $VMName `
        $Actual.ComputerName `
        ($Actual.ComputerName -eq $VMName)

    Add-LabCheck `
        'System' `
        'Operating system' `
        'Windows Server 2025' `
        $Actual.OperatingSystem `
        ($Actual.OperatingSystem -like '*Windows Server 2025*')

    # Hyper-V switch
    Add-LabCheck `
        'Hyper-V' `
        'LabSwitch connection' `
        'One adapter on LabSwitch' `
        "Adapters found: $($LabAdapters.Count)" `
        $SwitchOK

    # IPv4
    Add-LabCheck `
        'Network' `
        'IPv4 address' `
        $ExpectedIP `
        $ActualIP `
        (
            $LabNetworkFound -and
            @($LabInterface.IPv4).Count -eq 1 -and
            $ActualIP -eq $ExpectedIP
        )

    Add-LabCheck `
        'Network' `
        'IPv4 prefix' `
        "$ExpectedPrefix" `
        $ActualPrefix `
        (
            $LabNetworkFound -and
            @($LabInterface.Prefix).Count -eq 1 -and
            $ActualPrefix -eq "$ExpectedPrefix"
        )

    # DNS
    Add-LabCheck `
        'Network' `
        'DNS server' `
        $ExpectedDNS `
        $ActualDNS `
        (
            $LabNetworkFound -and
            @($LabInterface.DNS).Count -eq 1 -and
            $ActualDNS -eq $ExpectedDNS
        )

    # Routing
    Add-LabCheck `
        'Routing' `
        'Default gateway' `
        'None' `
        $(if ($NoDefaultGateway) {
            'None'
        } else {
            $DefaultRoutes.NextHop -join ', '
        }) `
        $NoDefaultGateway

    Add-LabCheck `
        'Routing' `
        'Direct laboratory route' `
        "$ExpectedSubnet via local interface" `
        $(if ($LabRouteOK) {
            "$ExpectedSubnet via local interface"
        } else {
            'Missing'
        }) `
        $LabRouteOK

    # Time zone
    Add-LabCheck `
        'System' `
        'Time zone' `
        $ExpectedTimeZone `
        $Actual.TimeZone `
        ($Actual.TimeZone -eq $ExpectedTimeZone)

    # Firewall
    Add-LabCheck `
        'Security' `
        'ICMPv4 firewall rule' `
        'Inbound Allow; ICMPv4 type 8; 10.10.10.0/24' `
        $FirewallDescription `
        $FirewallOK

    # Event logs
    foreach ($LogName in @('Application', 'System', 'Security')) {

        $Log = @(
            $Actual.EventLogs |
            Where-Object Name -eq $LogName
        ) | Select-Object -First 1

        $CurrentBytes = 0L

        if ($null -ne $Log) {
            $CurrentBytes = [long]$Log.MaximumBytes
        }

        $CurrentMB = [math]::Round($CurrentBytes / 1MB, 2)

        Add-LabCheck `
            'Event Logs' `
            "$LogName log size" `
            'At least 64 MB' `
            "$CurrentMB MB" `
            ($CurrentBytes -ge $MinimumLogSize)
    }

    # Domain controller readiness
    $IsDomainController = (
        $Actual.DomainRole -in @(4, 5)
    )

    Add-LabCheck `
        'Active Directory' `
        'Not yet a domain controller' `
        'True' `
        "$(-not $IsDomainController)" `
        (-not $IsDomainController)

    # ------------------------------------------------------
    # 9. Display console report
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 2 - EXPECTED VS ACTUAL"
    Write-Host "=========================================="

    $Checks |
        Format-Table `
            Category, Check, Expected, Actual, Status `
            -AutoSize |
        Out-Host

    Write-Host ""
    Write-Host "SERVER ROLES" -ForegroundColor Cyan
    Write-Host "AD DS installed: $($Actual.ADDSInstalled)"
    Write-Host "DNS installed:   $($Actual.DNSInstalled)"
    Write-Host "Domain role:     $($Actual.DomainRole)"

    # ------------------------------------------------------
    # 10. Export CSV
    # ------------------------------------------------------

    $Checks |
        Export-Csv `
            -Path $CSVPath `
            -NoTypeInformation `
            -Encoding UTF8

    # ------------------------------------------------------
    # 11. Export TXT
    # ------------------------------------------------------

    $TXT = @(
        'LAB 2 - WINDOWS SERVER 2025 VERIFICATION'
        '=========================================='
        "Host: $env:COMPUTERNAME"
        "VM: $VMName"
        "Date: $(Get-Date)"
        "OS: $($Actual.OperatingSystem)"
        "OS version: $($Actual.OSVersion)"
        "AD DS installed: $($Actual.ADDSInstalled)"
        "DNS installed: $($Actual.DNSInstalled)"
        "Domain role: $($Actual.DomainRole)"
        ''
        'EXPECTED VS ACTUAL'
        '=========================================='
        (
            $Checks |
            Format-List |
            Out-String -Width 200
        )
    )

    $TXT |
        Out-File `
            -FilePath $TXTPath `
            -Encoding UTF8

    # ------------------------------------------------------
    # 12. Export HTML
    # ------------------------------------------------------

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
    background: #ffffff;
    margin: 20px 0;
}
th {
    background: #146393;
    color: white;
    padding: 10px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 9px;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
</style>
"@

    $HTMLBody = @()

    $HTMLBody += '<h1>LAB 2 - Server Verification</h1>'
    $HTMLBody += "<p><strong>Host:</strong> $env:COMPUTERNAME</p>"
    $HTMLBody += "<p><strong>VM:</strong> $VMName</p>"
    $HTMLBody += "<p><strong>Date:</strong> $(Get-Date)</p>"

    $HTMLBody += '<h2>Expected vs Actual</h2>'

    $HTMLBody += (
        $Checks |
        ConvertTo-Html -Fragment
    )

    $HTMLBody += '<h2>Server Roles</h2>'

    $HTMLBody += "<p>AD DS installed: $($Actual.ADDSInstalled)</p>"
    $HTMLBody += "<p>DNS installed: $($Actual.DNSInstalled)</p>"
    $HTMLBody += "<p>Domain role: $($Actual.DomainRole)</p>"

    ConvertTo-Html `
        -Head $HTMLStyle `
        -Body ($HTMLBody -join "`n") `
        -Title 'LAB 2 - Server Verification' |
        Out-File `
            -FilePath $HTMLPath `
            -Encoding UTF8

    # ------------------------------------------------------
    # 13. Final result
    # ------------------------------------------------------

    $Passed = @(
        $Checks | Where-Object Status -eq 'PASS'
    ).Count

    $Failed = @(
        $Checks | Where-Object Status -eq 'FAIL'
    ).Count

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 2 - FINAL VERIFICATION REPORT"
    Write-Host "=========================================="

    Write-Host "Passed: $Passed" -ForegroundColor Green
    Write-Host "Failed: $Failed" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Reports:"
    Write-Host $CSVPath
    Write-Host $TXTPath
    Write-Host $HTMLPath

    if ($Failed -eq 0) {

        Write-Host ""
        Write-Host "LAB 2 - ALL VERIFICATION CHECKS PASSED" `
            -ForegroundColor Green
    }
    else {

        Write-Warning "LAB 2 - Some verification checks failed."
    }
}
finally {

    if ($null -ne $Session) {
        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

