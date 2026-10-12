# ==========================================================
# LAB 4 - Script 02 - Configure Domain DNS
#
# Run ONLY on Hyper-V host as Administrator
# Target VM: SEA-DC1
# Domain: contoso.com
# Connection: PowerShell Direct
#
# Tasks:
# - Validate Active Directory and DNS
# - Verify forward lookup zone
# - Create reverse lookup zone if missing
# - Create PTR record if missing
# - Verify A, PTR, NS, SOA and SRV records
# - Export CSV, TXT and HTML reports
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Laboratory configuration
# ----------------------------------------------------------

$VMName = 'SEA-DC1'
$DomainName = 'contoso.com'
$NetBIOSName = 'CONTOSO'

$ExpectedIP = '10.10.10.10'
$ExpectedPrefix = 24
$ExpectedDNS = '10.10.10.10'

$LabSwitch = 'LabSwitch'
$NetworkId = '10.10.10.0/24'
$ReverseZone = '10.10.10.in-addr.arpa'
$PTRName = '10'

$ReportPath = 'C:\LabReports'

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

New-Item `
    -Path $ReportPath `
    -ItemType Directory `
    -Force | Out-Null

$SummaryCSV = Join-Path $ReportPath `
    "LAB04-DNS-Configuration_$Timestamp.csv"

$ChecksCSV = Join-Path $ReportPath `
    "LAB04-DNS-Checks_$Timestamp.csv"

$ReportTXT = Join-Path $ReportPath `
    "LAB04-DNS-Configuration_$Timestamp.txt"

$ReportHTML = Join-Path $ReportPath `
    "LAB04-DNS-Configuration_$Timestamp.html"

# ----------------------------------------------------------
# 2. Verify Hyper-V host
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 4 - CONFIGURE DOMAIN DNS"
Write-Host "=========================================="
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "VM: $VMName"
Write-Host "Domain: $DomainName"
Write-Host "DNS server: $ExpectedDNS"
Write-Host "Reverse zone: $ReverseZone"
Write-Host ""

$VM = Get-VM `
    -Name $VMName `
    -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "Virtual machine $VMName is not running."
}

$LabAdapters = @(
    Get-VMNetworkAdapter `
        -VMName $VMName `
        -ErrorAction Stop |
    Where-Object {
        $_.SwitchName -eq $LabSwitch
    }
)

if ($LabAdapters.Count -ne 1) {
    throw "Expected exactly one adapter on $LabSwitch."
}

Write-Host "Hyper-V configuration verified." `
    -ForegroundColor Green

# ----------------------------------------------------------
# 3. Request domain credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName "$NetBIOSName\Administrator" `
    -Message "Enter domain Administrator password for $VMName"

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

$Session = $null

try {

    # ------------------------------------------------------
    # 4. Establish PowerShell Direct session
    # ------------------------------------------------------

    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    Write-Host "PowerShell Direct connection established." `
        -ForegroundColor Green

    # ------------------------------------------------------
    # 5. Configure DNS inside the guest
    # ------------------------------------------------------

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList `
            $DomainName,
            $ExpectedIP,
            $ExpectedPrefix,
            $ExpectedDNS,
            $NetworkId,
            $ReverseZone,
            $PTRName `
        -ScriptBlock {

            param(
                [string]$DomainName,
                [string]$ExpectedIP,
                [int]$ExpectedPrefix,
                [string]$ExpectedDNS,
                [string]$NetworkId,
                [string]$ReverseZone,
                [string]$PTRName
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory -ErrorAction Stop
            Import-Module DnsServer -ErrorAction Stop

            $ComputerName = $env:COMPUTERNAME
            $FQDN = "$ComputerName.$DomainName"

            $Checks = [System.Collections.Generic.List[object]]::new()

            function Add-LabCheck {
                param(
                    [string]$Check,
                    [string]$Expected,
                    [string]$Actual,
                    [bool]$Passed
                )

                $Checks.Add(
                    [PSCustomObject]@{
                        Check = $Check
                        Expected = $Expected
                        Actual = $Actual
                        Status = if ($Passed) {
                            'PASS'
                        }
                        else {
                            'FAIL'
                        }
                    }
                )
            }

            # --------------------------------------------------
            # A. Verify Active Directory domain
            # --------------------------------------------------

            $ADDomain = Get-ADDomain -ErrorAction Stop

            if ($ADDomain.DNSRoot -ne $DomainName) {
                throw "Unexpected AD domain: $($ADDomain.DNSRoot)"
            }

            $Computer = Get-CimInstance Win32_ComputerSystem

            if ($Computer.DomainRole -notin @(4, 5)) {
                throw 'Server is not a domain controller.'
            }

            Add-LabCheck `
                'AD domain' `
                $DomainName `
                $ADDomain.DNSRoot `
                $true

            # --------------------------------------------------
            # B. Verify DNS and AD services
            # --------------------------------------------------

            foreach ($ServiceName in @(
                'DNS',
                'NTDS',
                'Netlogon',
                'KDC'
            )) {

                $Service = Get-Service `
                    -Name $ServiceName `
                    -ErrorAction Stop

                $ServiceOK = ($Service.Status -eq 'Running')

                Add-LabCheck `
                    "Service $ServiceName" `
                    'Running' `
                    ([string]$Service.Status) `
                    $ServiceOK

                if (-not $ServiceOK) {
                    throw "Required service is not running: $ServiceName"
                }
            }

            # --------------------------------------------------
            # C. Verify local IPv4 and DNS client
            # --------------------------------------------------

            $IP = Get-NetIPAddress `
                -IPAddress $ExpectedIP `
                -AddressFamily IPv4 `
                -ErrorAction Stop

            if ($IP.PrefixLength -ne $ExpectedPrefix) {
                throw 'Unexpected IPv4 prefix length.'
            }

            $InterfaceIndex = $IP.InterfaceIndex

            $ClientDNS = @(
                (Get-DnsClientServerAddress `
                    -InterfaceIndex $InterfaceIndex `
                    -AddressFamily IPv4 `
                    -ErrorAction Stop).ServerAddresses
            )

            $ClientDNSOK = (
                $ClientDNS.Count -eq 1 -and
                $ClientDNS[0] -eq $ExpectedDNS
            )

            Add-LabCheck `
                'DNS client address' `
                $ExpectedDNS `
                ($ClientDNS -join ', ') `
                $ClientDNSOK

            if (-not $ClientDNSOK) {
                throw 'DNS client address does not match LAB 4 configuration.'
            }

            # --------------------------------------------------
            # D. Verify the forward lookup zone
            # --------------------------------------------------

            $ForwardZone = Get-DnsServerZone `
                -Name $DomainName `
                -ErrorAction Stop

            $ForwardIntegrated = [bool]$ForwardZone.IsDsIntegrated
            $ForwardSecure = (
                [string]$ForwardZone.DynamicUpdate -eq 'Secure'
            )

            Add-LabCheck `
                'Forward DNS zone' `
                $DomainName `
                $ForwardZone.ZoneName `
                ($ForwardZone.ZoneName -eq $DomainName)

            Add-LabCheck `
                'Forward zone AD integration' `
                'True' `
                ([string]$ForwardIntegrated) `
                $ForwardIntegrated

            Add-LabCheck `
                'Forward zone dynamic updates' `
                'Secure' `
                ([string]$ForwardZone.DynamicUpdate) `
                $ForwardSecure

            if (-not $ForwardIntegrated -or -not $ForwardSecure) {
                throw 'Forward zone requires review before continuing.'
            }

            # --------------------------------------------------
            # E. Verify the domain controller A record
            # --------------------------------------------------

            $ARecords = @(
                Resolve-DnsName `
                    -Name $FQDN `
                    -Type A `
                    -Server $ExpectedDNS `
                    -DnsOnly `
                    -ErrorAction Stop |
                Where-Object {
                    $_.Type -eq 'A'
                }
            )

            $AAddresses = @(
                $ARecords | ForEach-Object {
                    $_.IPAddress
                }
            )

            $ARecordOK = (
                $AAddresses.Count -eq 1 -and
                $AAddresses[0] -eq $ExpectedIP
            )

            Add-LabCheck `
                'Domain controller A record' `
                $ExpectedIP `
                ($AAddresses -join ', ') `
                $ARecordOK

            if (-not $ARecordOK) {
                throw "Unexpected A record for $FQDN."
            }

            # --------------------------------------------------
            # F. Create reverse lookup zone if missing
            # --------------------------------------------------

            $ExistingReverseZone = Get-DnsServerZone `
                -Name $ReverseZone `
                -ErrorAction SilentlyContinue

            if ($null -eq $ExistingReverseZone) {

                Write-Host "Creating reverse DNS zone..." `
                    -ForegroundColor Cyan

                Add-DnsServerPrimaryZone `
                    -NetworkId $NetworkId `
                    -ReplicationScope Domain `
                    -DynamicUpdate Secure `
                    -ErrorAction Stop | Out-Null

                $ReverseZoneAction = 'CREATED'
            }
            else {

                Write-Host "Reverse DNS zone already exists." `
                    -ForegroundColor Yellow

                $ReverseZoneAction = 'EXISTS'
            }

            # --------------------------------------------------
            # G. Verify reverse zone configuration
            # --------------------------------------------------

            $ReverseZoneObject = Get-DnsServerZone `
                -Name $ReverseZone `
                -ErrorAction Stop

            $ReverseIntegrated = (
                [bool]$ReverseZoneObject.IsDsIntegrated
            )

            $ReverseSecure = (
                [string]$ReverseZoneObject.DynamicUpdate -eq 'Secure'
            )

            Add-LabCheck `
                'Reverse DNS zone' `
                $ReverseZone `
                $ReverseZoneObject.ZoneName `
                ($ReverseZoneObject.ZoneName -eq $ReverseZone)

            Add-LabCheck `
                'Reverse zone AD integration' `
                'True' `
                ([string]$ReverseIntegrated) `
                $ReverseIntegrated

            Add-LabCheck `
                'Reverse zone dynamic updates' `
                'Secure' `
                ([string]$ReverseZoneObject.DynamicUpdate) `
                $ReverseSecure

            if (-not $ReverseIntegrated -or -not $ReverseSecure) {
                throw 'Reverse zone is not configured as expected.'
            }

            # --------------------------------------------------
            # H. Create PTR record if missing
            # --------------------------------------------------

            $ExistingPTR = @(
                Get-DnsServerResourceRecord `
                    -ZoneName $ReverseZone `
                    -Name $PTRName `
                    -RRType PTR `
                    -ErrorAction SilentlyContinue
            )

            if ($ExistingPTR.Count -eq 0) {

                Write-Host "Creating PTR record..." `
                    -ForegroundColor Cyan

                Add-DnsServerResourceRecordPtr `
                    -ZoneName $ReverseZone `
                    -Name $PTRName `
                    -PtrDomainName $FQDN `
                    -ErrorAction Stop | Out-Null

                $PTRAction = 'CREATED'
            }
            else {

                $ExistingPTRTargets = @(
                    $ExistingPTR | ForEach-Object {
                        ([string]$_.RecordData.PtrDomainName).
                            TrimEnd('.')
                    }
                )

                $PTRCorrect = (
                    $ExistingPTRTargets.Count -eq 1 -and
                    $ExistingPTRTargets[0] -ieq $FQDN
                )

                if (-not $PTRCorrect) {
                    throw "Existing PTR record conflicts with $FQDN."
                }

                $PTRAction = 'EXISTS'
            }

            # --------------------------------------------------
            # I. Verify PTR record
            # --------------------------------------------------

            $PTRRecords = @(
                Resolve-DnsName `
                    -Name '10.10.10.10.in-addr.arpa' `
                    -Type PTR `
                    -Server $ExpectedDNS `
                    -DnsOnly `
                    -ErrorAction Stop |
                Where-Object {
                    $_.Type -eq 'PTR'
                }
            )

            $PTRTargets = @(
                $PTRRecords | ForEach-Object {
                    ([string]$_.NameHost).TrimEnd('.')
                }
            )

            $PTRVerified = (
                $PTRTargets.Count -eq 1 -and
                $PTRTargets[0] -ieq $FQDN
            )

            Add-LabCheck `
                'Domain controller PTR record' `
                $FQDN `
                ($PTRTargets -join ', ') `
                $PTRVerified

            # --------------------------------------------------
            # J. Verify SOA and NS records
            # --------------------------------------------------

            foreach ($RecordType in @('SOA', 'NS')) {

                try {

                    $Records = @(
                        Resolve-DnsName `
                            -Name $DomainName `
                            -Type $RecordType `
                            -Server $ExpectedDNS `
                            -DnsOnly `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.Type -eq $RecordType
                        }
                    )

                    $Targets = @(
                        foreach ($Record in $Records) {

                            if ($RecordType -eq 'SOA') {
                                $Record.PrimaryServer
                            }
                            else {
                                $Record.NameHost
                            }
                        }
                    )

                    $Targets = @(
                        $Targets | ForEach-Object {
                            ([string]$_).TrimEnd('.')
                        }
                    )

                    $RecordOK = ($FQDN -in $Targets)

                    Add-LabCheck `
                        "Domain $RecordType record" `
                        $FQDN `
                        ($Targets -join ', ') `
                        $RecordOK
                }
                catch {

                    Add-LabCheck `
                        "Domain $RecordType record" `
                        $FQDN `
                        $_.Exception.Message `
                        $false
                }
            }

            # --------------------------------------------------
            # K. Verify Active Directory SRV records
            # --------------------------------------------------

            $SRVQueries = @(
                @{
                    Name = 'LDAP DC locator'
                    Query = "_ldap._tcp.dc._msdcs.$DomainName"
                }
                @{
                    Name = 'Kerberos service'
                    Query = "_kerberos._tcp.$DomainName"
                }
            )

            foreach ($Query in $SRVQueries) {

                try {

                    $Records = @(
                        Resolve-DnsName `
                            -Name $Query.Query `
                            -Type SRV `
                            -Server $ExpectedDNS `
                            -DnsOnly `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.Type -eq 'SRV'
                        }
                    )

                    $Targets = @(
                        $Records | ForEach-Object {
                            ([string]$_.NameTarget).TrimEnd('.')
                        }
                    )

                    $SRVOK = ($FQDN -in $Targets)

                    Add-LabCheck `
                        $Query.Name `
                        $FQDN `
                        ($Targets -join ', ') `
                        $SRVOK
                }
                catch {

                    Add-LabCheck `
                        $Query.Name `
                        $FQDN `
                        $_.Exception.Message `
                        $false
                }
            }

            # --------------------------------------------------
            # L. Collect final DNS server information
            # --------------------------------------------------

            $FinalZones = @(
                Get-DnsServerZone |
                Select-Object `
                    ZoneName,
                    ZoneType,
                    IsDsIntegrated,
                    DynamicUpdate
            )

            $FailedChecks = @(
                $Checks | Where-Object {
                    $_.Status -eq 'FAIL'
                }
            ).Count

            $FinalStatus = if (
                $FailedChecks -eq 0
            ) {
                'PASS'
            }
            else {
                'MISMATCH'
            }

            # --------------------------------------------------
            # M. Return structured results to the host
            # --------------------------------------------------

            [PSCustomObject]@{
                ComputerName = $ComputerName
                DomainName = $DomainName
                FQDN = $FQDN
                DNSAddress = $ExpectedDNS
                ForwardZone = $ForwardZone.ZoneName
                ReverseZone = $ReverseZoneObject.ZoneName
                ReverseZoneAction = $ReverseZoneAction
                ReverseADIntegrated = $ReverseIntegrated
                ReverseDynamicUpdate = [string]$ReverseZoneObject.DynamicUpdate
                PTRName = $PTRName
                PTRAction = $PTRAction
                PTRVerified = $PTRVerified
                Checks = @($Checks)
                Zones = @($FinalZones)
                FailedChecks = $FailedChecks
                Status = $FinalStatus
            }
        } `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 6. Display configuration report on the host
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 4 - DNS CONFIGURATION REPORT"
    Write-Host "=========================================="

    $Result |
        Select-Object `
            ComputerName,
            DomainName,
            FQDN,
            DNSAddress,
            ForwardZone,
            ReverseZone,
            ReverseZoneAction,
            ReverseADIntegrated,
            ReverseDynamicUpdate,
            PTRName,
            PTRAction,
            PTRVerified,
            Status |
        Format-List |
        Out-Host

    Write-Host ""
    Write-Host "DNS VERIFICATION CHECKS" `
        -ForegroundColor Cyan

    $Result.Checks |
        Format-Table `
            Check,
            Expected,
            Actual,
            Status `
            -AutoSize |
        Out-Host

    Write-Host ""
    Write-Host "DNS ZONES" -ForegroundColor Cyan

    $Result.Zones |
        Format-Table `
            ZoneName,
            ZoneType,
            IsDsIntegrated,
            DynamicUpdate `
            -AutoSize |
        Out-Host

    # ------------------------------------------------------
    # 7. Export CSV reports
    # ------------------------------------------------------

    $Result |
        Select-Object `
            ComputerName,
            DomainName,
            FQDN,
            DNSAddress,
            ForwardZone,
            ReverseZone,
            ReverseZoneAction,
            ReverseADIntegrated,
            ReverseDynamicUpdate,
            PTRName,
            PTRAction,
            PTRVerified,
            FailedChecks,
            Status |
        Export-Csv `
            -Path $SummaryCSV `
            -NoTypeInformation `
            -Encoding UTF8

    $Result.Checks |
        Export-Csv `
            -Path $ChecksCSV `
            -NoTypeInformation `
            -Encoding UTF8

    # ------------------------------------------------------
    # 8. Export TXT report
    # ------------------------------------------------------

    $TextReport = @(
        'LAB 4 - DNS CONFIGURATION DOCUMENTATION'
        '=========================================='
        "Host: $env:COMPUTERNAME"
        "Server: $VMName"
        "Domain: $DomainName"
        "Date: $(Get-Date)"
        ''
        'DNS CONFIGURATION'
        '=========================================='
        (
            $Result |
            Select-Object `
                ComputerName,
                DomainName,
                FQDN,
                DNSAddress,
                ForwardZone,
                ReverseZone,
                ReverseZoneAction,
                PTRAction,
                PTRVerified,
                Status |
            Format-List |
            Out-String -Width 180
        )
        ''
        'VERIFICATION CHECKS'
        '=========================================='
        (
            $Result.Checks |
            Format-List |
            Out-String -Width 180
        )
        ''
        'DNS ZONES'
        '=========================================='
        (
            $Result.Zones |
            Format-Table -AutoSize |
            Out-String -Width 180
        )
    )

    $TextReport |
        Out-File `
            -FilePath $ReportTXT `
            -Encoding UTF8

    # ------------------------------------------------------
    # 9. Export HTML report
    # ------------------------------------------------------

    $HTMLStyle = @"
<meta charset="utf-8">
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    color: #294554;
    background-color: #f5f9fb;
}
h1, h2 {
    color: #146393;
}
h1 {
    border-bottom: 3px solid #146393;
    padding-bottom: 12px;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin: 20px 0 30px 0;
    background-color: #ffffff;
    font-size: 13px;
}
th {
    background-color: #146393;
    color: white;
    padding: 10px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 9px;
}
tr:nth-child(even) {
    background-color: #f5f9fb;
}
p {
    line-height: 1.6;
}
</style>
"@

    $HTMLBody = @()

    $HTMLBody += '<h1>LAB 4 - DNS Configuration</h1>'
    $HTMLBody += "<p><strong>Host:</strong> $env:COMPUTERNAME</p>"
    $HTMLBody += "<p><strong>Server:</strong> $VMName</p>"
    $HTMLBody += "<p><strong>Domain:</strong> $DomainName</p>"
    $HTMLBody += "<p><strong>Date:</strong> $(Get-Date)</p>"

    $HTMLBody += '<h2>Configuration Summary</h2>'

    $HTMLBody += (
        $Result |
        Select-Object `
            ComputerName,
            DomainName,
            FQDN,
            DNSAddress,
            ForwardZone,
            ReverseZone,
            ReverseZoneAction,
            PTRAction,
            PTRVerified,
            Status |
        ConvertTo-Html -Fragment
    )

    $HTMLBody += '<h2>Expected vs Actual</h2>'

    $HTMLBody += (
        $Result.Checks |
        ConvertTo-Html -Fragment
    )

    $HTMLBody += '<h2>DNS Zones</h2>'

    $HTMLBody += (
        $Result.Zones |
        ConvertTo-Html -Fragment
    )

    ConvertTo-Html `
        -Title 'LAB 4 - DNS Configuration' `
        -Head $HTMLStyle `
        -Body ($HTMLBody -join "`n") |
        Out-File `
            -FilePath $ReportHTML `
            -Encoding UTF8

    # ------------------------------------------------------
    # 10. Final result
    # ------------------------------------------------------

    $Passed = @(
        $Result.Checks |
        Where-Object Status -eq 'PASS'
    ).Count

    $Failed = @(
        $Result.Checks |
        Where-Object Status -eq 'FAIL'
    ).Count

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 4 - FINAL RESULT"
    Write-Host "=========================================="

    Write-Host "Passed: $Passed" -ForegroundColor Green
    Write-Host "Failed: $Failed" -ForegroundColor Yellow
    Write-Host "Status: $($Result.Status)"

    Write-Host ""
    Write-Host "Reports exported:"
    Write-Host $SummaryCSV
    Write-Host $ChecksCSV
    Write-Host $ReportTXT
    Write-Host $ReportHTML

    if ($Result.Status -eq 'PASS') {

        Write-Host ""
        Write-Host "LAB 4 - DNS CONFIGURATION PASSED" `
            -ForegroundColor Green
    }
    else {

        Write-Warning "LAB 4 - DNS configuration requires attention."
    }
}
catch {

    Write-Host ""
    Write-Host "LAB 4 - DNS CONFIGURATION FAILED" `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red

    throw
}
finally {

    # ------------------------------------------------------
    # 11. Close PowerShell Direct session
    # ------------------------------------------------------

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}
