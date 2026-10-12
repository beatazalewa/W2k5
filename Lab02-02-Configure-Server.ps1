# ==========================================================
# LAB 2 - Script 02
# Initial Windows Server 2025 Configuration
#
# Run ONLY on Hyper-V host as Administrator
# Target VM: SEA-DC1
# Connection: PowerShell Direct
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Laboratory configuration
# ----------------------------------------------------------

$VMName = 'SEA-DC1'
$ExpectedComputerName = 'SEA-DC1'

$ExpectedIP = '10.10.10.10'
$ExpectedPrefix = 24
$ExpectedDNS = '10.10.10.10'

$LabSubnet = '10.10.10.0/24'
$LabSwitch = 'LabSwitch'

$TimeZone = 'Central European Standard Time'

$RuleName = 'LAB01-Allow-ICMPv4'
$MinimumLogSize = 64MB

$ReportPath = 'C:\LabReports'

# ----------------------------------------------------------
# 2. Prepare the host environment
# ----------------------------------------------------------

New-Item `
    -Path $ReportPath `
    -ItemType Directory `
    -Force | Out-Null

Import-Module Hyper-V -ErrorAction Stop

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V cmdlets are unavailable on this computer.'
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 2 - INITIAL SERVER CONFIGURATION"
Write-Host "=========================================="
Write-Host "Hyper-V host: $env:COMPUTERNAME"
Write-Host "Target VM: $VMName"
Write-Host ""

# ----------------------------------------------------------
# 3. Verify the VM and virtual network adapter
# ----------------------------------------------------------

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "VM $VMName is not running."
}

$LabAdapters = @(
    Get-VMNetworkAdapter -VMName $VMName |
    Where-Object {
        $_.SwitchName -eq $LabSwitch
    }
)

if ($LabAdapters.Count -ne 1) {
    throw "Expected exactly one adapter connected to $LabSwitch."
}

Write-Host "VM is running." -ForegroundColor Green
Write-Host "LabSwitch connection verified." -ForegroundColor Green

# ----------------------------------------------------------
# 4. Request guest credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName '.\Administrator' `
    -Message "Enter Administrator password for $VMName"

if ($null -eq $Credential) {
    throw 'Credentials not provided.'
}

$Session = $null

try {

    # ------------------------------------------------------
    # 5. Connect using PowerShell Direct
    # ------------------------------------------------------

    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    Write-Host "PowerShell Direct connection established." `
        -ForegroundColor Green

    # ------------------------------------------------------
    # 6. Configure the guest operating system
    # ------------------------------------------------------

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList `
            $ExpectedComputerName,
            $ExpectedIP,
            $ExpectedPrefix,
            $ExpectedDNS,
            $LabSubnet,
            $TimeZone,
            $RuleName,
            $MinimumLogSize `
        -ScriptBlock {

            param(
                [string]$ExpectedComputerName,
                [string]$ExpectedIP,
                [int]$ExpectedPrefix,
                [string]$ExpectedDNS,
                [string]$LabSubnet,
                [string]$TimeZone,
                [string]$RuleName,
                [long]$MinimumLogSize
            )

            $ErrorActionPreference = 'Stop'

            # --------------------------------------------------
            # A. Verify the computer name
            # --------------------------------------------------

            if ($env:COMPUTERNAME -ne $ExpectedComputerName) {
                throw "Unexpected computer name: $env:COMPUTERNAME"
            }

            # --------------------------------------------------
            # B. Verify IPv4 configuration
            # --------------------------------------------------

            $IPConfig = Get-NetIPAddress `
                -IPAddress $ExpectedIP `
                -AddressFamily IPv4 `
                -ErrorAction Stop

            if ($IPConfig.PrefixLength -ne $ExpectedPrefix) {
                throw "Unexpected IPv4 prefix length."
            }

            $InterfaceIndex = $IPConfig.InterfaceIndex

            # Verify DNS server
            $DNSConfig = Get-DnsClientServerAddress `
                -InterfaceIndex $InterfaceIndex `
                -AddressFamily IPv4 `
                -ErrorAction Stop

            $ActualDNS = @($DNSConfig.ServerAddresses)

            if (
                $ActualDNS.Count -ne 1 -or
                $ActualDNS[0] -ne $ExpectedDNS
            ) {
                throw "Unexpected DNS configuration: $($ActualDNS -join ', ')"
            }

            # Verify no IPv4 default gateway
            $DefaultRoutes = @(
                Get-NetRoute `
                    -AddressFamily IPv4 `
                    -DestinationPrefix '0.0.0.0/0' `
                    -ErrorAction SilentlyContinue
            )

            if ($DefaultRoutes.Count -gt 0) {
                throw 'Unexpected IPv4 default gateway.'
            }

            # --------------------------------------------------
            # C. Verify laboratory route
            # --------------------------------------------------

            $LabRoutes = @(
                Get-NetRoute `
                    -InterfaceIndex $InterfaceIndex `
                    -AddressFamily IPv4 |
                Where-Object {
                    $_.DestinationPrefix -eq $LabSubnet -and
                    $_.NextHop -eq '0.0.0.0'
                }
            )

            if ($LabRoutes.Count -eq 0) {
                throw "Missing direct route to $LabSubnet."
            }

            # --------------------------------------------------
            # D. Configure the Windows time zone
            # --------------------------------------------------

            $CurrentTimeZone = (Get-TimeZone).Id

            if ($CurrentTimeZone -ne $TimeZone) {

                Set-TimeZone `
                    -Id $TimeZone `
                    -ErrorAction Stop
            }

            # --------------------------------------------------
            # E. Configure the ICMPv4 firewall rule
            # --------------------------------------------------

            $ExistingRule = Get-NetFirewallRule `
                -Name $RuleName `
                -ErrorAction SilentlyContinue

            if (-not $ExistingRule) {

                New-NetFirewallRule `
                    -Name $RuleName `
                    -DisplayName 'LAB 1 - Allow ICMPv4' `
                    -Direction Inbound `
                    -Protocol ICMPv4 `
                    -IcmpType 8 `
                    -RemoteAddress $LabSubnet `
                    -Action Allow `
                    -Profile Any `
                    -Enabled True `
                    -ErrorAction Stop | Out-Null

                $FirewallAction = 'CREATED'
            }
            else {

                Set-NetFirewallRule `
                    -Name $RuleName `
                    -Enabled True `
                    -Direction Inbound `
                    -Action Allow `
                    -Profile Any `
                    -ErrorAction Stop

                $ExistingRule |
                    Get-NetFirewallAddressFilter |
                    Set-NetFirewallAddressFilter `
                        -RemoteAddress $LabSubnet `
                        -ErrorAction Stop

                $ExistingRule |
                    Get-NetFirewallPortFilter |
                    Set-NetFirewallPortFilter `
                        -Protocol ICMPv4 `
                        -IcmpType 8 `
                        -ErrorAction Stop

                $FirewallAction = 'UPDATED'
            }

            # --------------------------------------------------
            # F. Configure Windows event log sizes
            # --------------------------------------------------

            $LogNames = @(
                'Application',
                'System',
                'Security'
            )

            $LogResults = @(
                foreach ($LogName in $LogNames) {

                    $Log = Get-WinEvent `
                        -ListLog $LogName `
                        -ErrorAction Stop

                    $PreviousSize = $Log.MaximumSizeInBytes

                    if ($PreviousSize -lt $MinimumLogSize) {

                        & wevtutil.exe sl $LogName "/ms:$MinimumLogSize"

                        if ($LASTEXITCODE -ne 0) {
                            throw "Failed to configure event log: $LogName"
                        }

                        $LogAction = 'INCREASED'
                    }
                    else {
                        $LogAction = 'UNCHANGED'
                    }

                    $UpdatedLog = Get-WinEvent `
                        -ListLog $LogName `
                        -ErrorAction Stop

                    [PSCustomObject]@{
                        LogName = $LogName
                        PreviousMB = [math]::Round(
                            $PreviousSize / 1MB, 0
                        )
                        CurrentMB = [math]::Round(
                            $UpdatedLog.MaximumSizeInBytes / 1MB, 0
                        )
                        CurrentBytes = [long]$UpdatedLog.MaximumSizeInBytes
                        Action = $LogAction
                    }
                }
            )

            # --------------------------------------------------
            # G. Verify the final configuration
            # --------------------------------------------------

            $FinalTimeZone = (Get-TimeZone).Id

            $FinalRule = Get-NetFirewallRule `
                -Name $RuleName `
                -ErrorAction Stop

            $FinalAddressFilter = $FinalRule |
                Get-NetFirewallAddressFilter

            $FinalPortFilter = $FinalRule |
                Get-NetFirewallPortFilter

            # Protocol 1 corresponds to ICMPv4
            $ProtocolOK = (
                [string]$FinalPortFilter.Protocol -in @(
                    'ICMPv4',
                    '1'
                )
            )

            # ICMP type 8 is Echo Request
            $IcmpTypeOK = (
                [string]$FinalPortFilter.IcmpType -eq '8'
            )

            # Accept CIDR and dotted-mask representations
            $AcceptedSubnets = @(
                '10.10.10.0/24',
                '10.10.10.0/255.255.255.0'
            )

            $RemoteAddresses = @(
                $FinalAddressFilter.RemoteAddress
            )

            $AddressOK = (
                $RemoteAddresses.Count -eq 1 -and
                [string]$RemoteAddresses[0] -in $AcceptedSubnets
            )

            $FirewallOK = (
                [string]$FinalRule.Enabled -eq 'True' -and
                [string]$FinalRule.Action -eq 'Allow' -and
                [string]$FinalRule.Direction -eq 'Inbound' -and
                [string]$FinalRule.Profile -eq 'Any' -and
                $ProtocolOK -and
                $IcmpTypeOK -and
                $AddressOK
            )

            # Verify event logs using exact byte values
            $LogsOK = (
                @(
                    $LogResults |
                    Where-Object {
                        $_.CurrentBytes -lt $MinimumLogSize
                    }
                ).Count -eq 0
            )

            $TimeZoneOK = (
                $FinalTimeZone -eq $TimeZone
            )

            # --------------------------------------------------
            # H. Display detailed firewall verification
            # --------------------------------------------------

            Write-Host ""
            Write-Host "FIREWALL VERIFICATION" -ForegroundColor Cyan

            [PSCustomObject]@{
                RuleName = $FinalRule.Name
                Enabled = $FinalRule.Enabled
                Direction = $FinalRule.Direction
                Action = $FinalRule.Action
                Profile = $FinalRule.Profile
                Protocol = $FinalPortFilter.Protocol
                ProtocolOK = $ProtocolOK
                IcmpType = $FinalPortFilter.IcmpType
                IcmpTypeOK = $IcmpTypeOK
                RemoteAddress = $RemoteAddresses -join ', '
                AddressOK = $AddressOK
                FirewallOK = $FirewallOK
            } | Format-List | Out-Host

            # --------------------------------------------------
            # I. Determine final status
            # --------------------------------------------------

            $Status = if (
                $FirewallOK -and
                $LogsOK -and
                $TimeZoneOK
            ) {
                'PASS'
            }
            else {
                'MISMATCH'
            }

            # --------------------------------------------------
            # J. Return structured results to the host
            # --------------------------------------------------

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                IPv4 = $IPConfig.IPAddress
                PrefixLength = $IPConfig.PrefixLength
                DNS = $ActualDNS -join ', '
                Gateway = 'None'
                LabRoute = $LabSubnet
                TimeZone = $FinalTimeZone
                TimeZoneOK = $TimeZoneOK
                FirewallRule = $FinalRule.Name
                FirewallAction = $FirewallAction
                FirewallProtocol = $FinalPortFilter.Protocol
                FirewallIcmpType = $FinalPortFilter.IcmpType
                FirewallRemoteAddress = $RemoteAddresses -join ', '
                ProtocolOK = $ProtocolOK
                IcmpTypeOK = $IcmpTypeOK
                AddressOK = $AddressOK
                FirewallOK = $FirewallOK
                EventLogsOK = $LogsOK
                LogDetails = @($LogResults)
                Status = $Status
            }

        } `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 7. Display the configuration report
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 2 - CONFIGURATION REPORT"
    Write-Host "=========================================="

    $Result |
        Select-Object `
            ComputerName,
            IPv4,
            PrefixLength,
            DNS,
            Gateway,
            LabRoute,
            TimeZone,
            TimeZoneOK,
            FirewallRule,
            FirewallAction,
            FirewallProtocol,
            FirewallIcmpType,
            FirewallRemoteAddress,
            ProtocolOK,
            IcmpTypeOK,
            AddressOK,
            FirewallOK,
            EventLogsOK,
            Status |
        Format-List |
        Out-Host

    Write-Host ""
    Write-Host "EVENT LOG CONFIGURATION" -ForegroundColor Cyan

    $Result.LogDetails |
        Format-Table `
            LogName,
            PreviousMB,
            CurrentMB,
            Action `
            -AutoSize |
        Out-Host

    # ------------------------------------------------------
    # 8. Export CSV documentation
    # ------------------------------------------------------

    $Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

    $SummaryCSV = Join-Path `
        $ReportPath `
        "LAB02-Configuration_$Timestamp.csv"

    $LogsCSV = Join-Path `
        $ReportPath `
        "LAB02-EventLogs_$Timestamp.csv"

    $Result |
        Select-Object `
            ComputerName,
            IPv4,
            PrefixLength,
            DNS,
            Gateway,
            LabRoute,
            TimeZone,
            TimeZoneOK,
            FirewallRule,
            FirewallAction,
            FirewallProtocol,
            FirewallIcmpType,
            FirewallRemoteAddress,
            ProtocolOK,
            IcmpTypeOK,
            AddressOK,
            FirewallOK,
            EventLogsOK,
            Status |
        Export-Csv `
            -Path $SummaryCSV `
            -NoTypeInformation `
            -Encoding UTF8

    $Result.LogDetails |
        Select-Object `
            LogName,
            PreviousMB,
            CurrentMB,
            Action |
        Export-Csv `
            -Path $LogsCSV `
            -NoTypeInformation `
            -Encoding UTF8

    # ------------------------------------------------------
    # 9. Final report
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 2 - FINAL RESULT"
    Write-Host "=========================================="

    Write-Host "Computer: $($Result.ComputerName)"
    Write-Host "IPv4: $($Result.IPv4)"
    Write-Host "DNS: $($Result.DNS)"
    Write-Host "Time zone: $($Result.TimeZone)"
    Write-Host "Firewall OK: $($Result.FirewallOK)"
    Write-Host "Event logs OK: $($Result.EventLogsOK)"

    Write-Host ""
    Write-Host "Reports exported:"
    Write-Host $SummaryCSV
    Write-Host $LogsCSV

    if ($Result.Status -eq 'PASS') {

        Write-Host ""
        Write-Host "LAB 2 - SERVER CONFIGURATION PASSED" `
            -ForegroundColor Green
    }
    else {

        Write-Warning "LAB 2 - Configuration requires attention."
    }

}
catch {

    Write-Host ""
    Write-Host "LAB 2 - CONFIGURATION FAILED" `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    throw
}
finally {

    # ------------------------------------------------------
    # 10. Close the PowerShell Direct session
    # ------------------------------------------------------

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

