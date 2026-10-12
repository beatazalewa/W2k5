# ============================================================
# LAB 4 - Script 03 - Verify DNS and Active Directory
# Run ONLY on the Hyper-V host in Windows PowerShell 5.1
# Target: SEA-DC1 / contoso.com
# Uses PowerShell Direct (no WinRM required)
# Read-only for guest configuration
# ============================================================

$ErrorActionPreference = 'Stop'

$VMName       = 'SEA-DC1'
$DomainName   = 'contoso.com'
$NetBIOSName  = 'CONTOSO'
$ExpectedIP   = '10.10.10.10'
$ReverseZone  = '10.10.10.in-addr.arpa'
$LabSwitch    = 'LabSwitch'
$ReportPath   = 'C:\LabReports'
$Timestamp    = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
$CsvPath  = Join-Path $ReportPath "LAB04-DNS-Verification_$Timestamp.csv"
$TxtPath  = Join-Path $ReportPath "LAB04-DNS-Verification_$Timestamp.txt"
$HtmlPath = Join-Path $ReportPath "LAB04-DNS-Verification_$Timestamp.html"
$DiagPath = Join-Path $ReportPath "LAB04-DCDIAG_$Timestamp.txt"

Import-Module Hyper-V -ErrorAction Stop
$VM = Get-VM -Name $VMName -ErrorAction Stop
if ($VM.State -ne 'Running') { throw "VM $VMName is not running." }
$NICs = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction Stop |
    Where-Object { $_.SwitchName -eq $LabSwitch })
if ($NICs.Count -ne 1) { throw "Expected exactly one adapter attached to $LabSwitch." }

$Credential = Get-Credential -UserName "$NetBIOSName\Administrator" `
    -Message "Enter the domain Administrator password for $VMName"
if ($null -eq $Credential) { throw 'Credentials were not provided.' }

$Session = $null
try {
    $Session = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
    $Result = Invoke-Command -Session $Session `
        -ArgumentList $DomainName, $NetBIOSName, $ExpectedIP, $ReverseZone `
        -ScriptBlock {
            param([string]$DomainName, [string]$NetBIOSName,
                  [string]$ExpectedIP, [string]$ReverseZone)

            $ErrorActionPreference = 'Stop'
            Import-Module ActiveDirectory -ErrorAction Stop
            Import-Module DnsServer -ErrorAction Stop

            $Checks = New-Object 'System.Collections.Generic.List[object]'
            $FQDN = "$env:COMPUTERNAME.$DomainName"

            function Add-Check {
                param([string]$Category, [string]$Name, [string]$Expected,
                      [string]$Actual, [bool]$Pass, [string]$Details = '')
                $Checks.Add([PSCustomObject]@{
                    Category = $Category; Check = $Name; Expected = $Expected
                    Actual = $Actual; Status = $(if ($Pass) { 'PASS' } else { 'FAIL' })
                    Details = $Details
                })
            }

            # Domain and controller identity
            try {
                $Domain = Get-ADDomain -ErrorAction Stop
                Add-Check 'AD' 'Domain DNS name' $DomainName ([string]$Domain.DNSRoot) `
                    ($Domain.DNSRoot -ieq $DomainName)
                Add-Check 'AD' 'Domain NetBIOS name' $NetBIOSName ([string]$Domain.NetBIOSName) `
                    ($Domain.NetBIOSName -ieq $NetBIOSName)
            } catch {
                Add-Check 'AD' 'Domain query' 'Available' 'ERROR' $false $_.Exception.Message
            }
            $CS = Get-CimInstance Win32_ComputerSystem
            Add-Check 'AD' 'Domain controller role' '4 or 5' ([string]$CS.DomainRole) `
                ($CS.DomainRole -in @(4,5))

            # Required services
            foreach ($Name in @('DNS','NTDS','Netlogon','KDC','DFSR')) {
                $Service = Get-Service -Name $Name -ErrorAction SilentlyContinue
                $State = if ($null -ne $Service) { [string]$Service.Status } else { 'MISSING' }
                Add-Check 'Services' $Name 'Running' $State ($State -eq 'Running')
            }

            # Domain and reverse zones
            foreach ($ZoneName in @($DomainName, $ReverseZone, "_msdcs.$DomainName")) {
                try {
                    $Zone = Get-DnsServerZone -Name $ZoneName -ErrorAction Stop
                    $ZoneOK = ([bool]$Zone.IsDsIntegrated -and [string]$Zone.ZoneType -eq 'Primary')
                    Add-Check 'Zones' $ZoneName 'Primary, AD-integrated' `
                        ("{0}, AD-integrated={1}" -f $Zone.ZoneType,$Zone.IsDsIntegrated) $ZoneOK
                    if ($ZoneName -eq $DomainName -or $ZoneName -eq $ReverseZone) {
                        Add-Check 'Zones' "$ZoneName dynamic updates" 'Secure' `
                            ([string]$Zone.DynamicUpdate) ([string]$Zone.DynamicUpdate -eq 'Secure')
                    }
                } catch {
                    Add-Check 'Zones' $ZoneName 'Present' 'ERROR' $false $_.Exception.Message
                }
            }

            # Verify DNS client on the interface owning the DC IPv4 address
            try {
                $IP = Get-NetIPAddress -IPAddress $ExpectedIP -AddressFamily IPv4 -ErrorAction Stop
                $Servers = @((Get-DnsClientServerAddress -InterfaceIndex $IP.InterfaceIndex `
                    -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
                Add-Check 'Network' 'DNS client IPv4 server' $ExpectedIP ($Servers -join ', ') `
                    ($Servers.Count -eq 1 -and $Servers[0] -eq $ExpectedIP)
                Add-Check 'Network' 'IPv4 prefix length' '24' ([string]$IP.PrefixLength) `
                    ($IP.PrefixLength -eq 24)
            } catch {
                Add-Check 'Network' 'DC IPv4 configuration' $ExpectedIP 'ERROR' $false $_.Exception.Message
            }

            # DNS queries; accept at least one matching answer, reject neither missing nor wrong targets
            $Queries = @(
                @{ Label='DC host A'; Name=$FQDN; Type='A'; Expected=$ExpectedIP; Property='IPAddress' },
                @{ Label='DC reverse PTR'; Name='10.10.10.10.in-addr.arpa'; Type='PTR'; Expected=$FQDN; Property='NameHost' },
                @{ Label='Domain NS'; Name=$DomainName; Type='NS'; Expected=$FQDN; Property='NameHost' },
                @{ Label='Domain SOA'; Name=$DomainName; Type='SOA'; Expected=$FQDN; Property='PrimaryServer' },
                @{ Label='DC locator SRV'; Name="_ldap._tcp.dc._msdcs.$DomainName"; Type='SRV'; Expected=$FQDN; Property='NameTarget' },
                @{ Label='Kerberos SRV'; Name="_kerberos._tcp.$DomainName"; Type='SRV'; Expected=$FQDN; Property='NameTarget' }
            )
            foreach ($Query in $Queries) {
                try {
                    $Answers = @(Resolve-DnsName -Name $Query.Name -Type $Query.Type `
                        -Server $ExpectedIP -DnsOnly -ErrorAction Stop |
                        Where-Object { [string]$_.Type -eq $Query.Type })
                    $Values = @($Answers | ForEach-Object {
                        ([string]($_.($Query.Property))).TrimEnd('.')
                    } | Where-Object { $_ })
                    $Expected = ([string]$Query.Expected).TrimEnd('.')
                    Add-Check 'DNS records' $Query.Label $Expected ($Values -join ', ') `
                        ($Expected -in $Values)
                } catch {
                    Add-Check 'DNS records' $Query.Label ([string]$Query.Expected) 'ERROR' `
                        $false $_.Exception.Message
                }
            }

            # AD shares
            try {
                $ShareNames = @(Get-SmbShare -ErrorAction Stop | Select-Object -ExpandProperty Name)
                foreach ($Share in @('SYSVOL','NETLOGON')) {
                    $Present = $Share -in $ShareNames
                    Add-Check 'AD shares' $Share 'Exists' `
                        $(if ($Present) {'Exists'} else {'Missing'}) $Present
                }
            } catch {
                Add-Check 'AD shares' 'Share enumeration' 'Available' 'ERROR' $false $_.Exception.Message
            }

            # dcdiag is diagnostic output; warnings should be reviewed, not blindly treated as fatal
            $DiagLines = @()
            $DiagExitCode = $null
            try {
                $DiagLines += '===== DCDIAG: DNS ====='
                $DiagLines += @(& dcdiag.exe "/s:$env:COMPUTERNAME" /test:DNS /v 2>&1 |
                    ForEach-Object { [string]$_ })
                $DnsDiagExit = $LASTEXITCODE
                $DiagLines += "DNS test exit code: $DnsDiagExit"
                $DiagLines += ''
                $DiagLines += '===== DCDIAG: ADVERTISING ====='
                $DiagLines += @(& dcdiag.exe "/s:$env:COMPUTERNAME" /test:Advertising /v 2>&1 |
                    ForEach-Object { [string]$_ })
                $AdvertisingExit = $LASTEXITCODE
                $DiagLines += "Advertising test exit code: $AdvertisingExit"
                $DiagExitCode = "DNS=$DnsDiagExit; Advertising=$AdvertisingExit"
            } catch {
                $DiagLines += "DCDIAG command failed: $($_.Exception.Message)"
                $DiagExitCode = 'ERROR'
            }

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                DomainName = $DomainName
                Checks = @($Checks.ToArray())
                DCDIAGStatus = $DiagExitCode
                DCDIAGText = ($DiagLines -join "`r`n")
            }
        } -ErrorAction Stop

    $Checks = @($Result.Checks)
    $Passed = @($Checks | Where-Object Status -eq 'PASS').Count
    $Failed = @($Checks | Where-Object Status -eq 'FAIL').Count

    # Export only data objects, never Format-Table output
    $Checks | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    @(
        'LAB 4 - DNS AND AD DS VERIFICATION'
        '========================================'
        "Host: $env:COMPUTERNAME"
        "Guest: $($Result.ComputerName)"
        "Domain: $($Result.DomainName)"
        "Date: $(Get-Date)"
        "Passed: $Passed; Failed: $Failed"
        "DCDIAG: $($Result.DCDIAGStatus)"
        ''
        ($Checks | Format-List | Out-String -Width 200)
    ) | Out-File -FilePath $TxtPath -Encoding UTF8
    $Result.DCDIAGText | Out-File -FilePath $DiagPath -Encoding UTF8

    $Css = @'
<meta charset="utf-8">
<style>
body{font-family:Arial,sans-serif;background:#f5f9fb;color:#294554;margin:32px}
h1,h2{color:#146393} h1{border-bottom:3px solid #146393;padding-bottom:12px}
table{border-collapse:collapse;width:100%;background:white;font-size:13px}
th{background:#146393;color:white;text-align:left;padding:10px}
td{border:1px solid #dce6eb;padding:9px;vertical-align:top}
tr:nth-child(even){background:#f5f9fb}
</style>
'@
    $Body = @(
        '<h1>LAB 4 - DNS and AD DS Verification</h1>'
        "<p>Host: $env:COMPUTERNAME | VM: $VMName | Domain: $DomainName</p>"
        "<p>Passed: $Passed | Failed: $Failed</p>"
        '<h2>Expected vs Actual</h2>'
        ($Checks | ConvertTo-Html -Fragment | Out-String)
        '<p>Detailed DCDIAG output is saved in a separate TXT file.</p>'
    ) -join "`n"
    ConvertTo-Html -Title 'LAB 4 - DNS Verification' -Head $Css -Body $Body |
        Out-File -FilePath $HtmlPath -Encoding UTF8

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host 'LAB 4 - DNS AND AD DS VERIFICATION' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    $Checks | Format-Table Category, Check, Status, Actual -AutoSize | Out-Host
    Write-Host "Passed: $Passed" -ForegroundColor Green
    Write-Host "Failed: $Failed" -ForegroundColor $(if ($Failed) {'Yellow'} else {'Green'})
    Write-Host "DCDIAG: $($Result.DCDIAGStatus)"
    Write-Host "CSV:  $CsvPath"
    Write-Host "TXT:  $TxtPath"
    Write-Host "HTML: $HtmlPath"
    Write-Host "DCDIAG: $DiagPath"

    if ($Failed -eq 0) {
        Write-Host 'LAB 4 - STRUCTURED VERIFICATION PASSED' -ForegroundColor Green
        Write-Host 'Review DCDIAG separately for diagnostic warnings.' -ForegroundColor Yellow
    } else {
        Write-Warning 'LAB 4 - Some verification checks failed. Review the reports.'
    }
}
finally {
    if ($null -ne $Session) {
        Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
    }
}
