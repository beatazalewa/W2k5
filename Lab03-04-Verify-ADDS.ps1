# ==========================================================
# LAB 3 - Script 04 - Verify Active Directory and DNS
# Run on Hyper-V host as Administrator
# Target: SEA-DC1
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'
$DomainName = 'contoso.com'
$ExpectedIP = '10.10.10.10'
$ReportPath = 'C:\LabReports'

New-Item -ItemType Directory -Path $ReportPath -Force |
    Out-Null

Import-Module Hyper-V -ErrorAction Stop

if ((Get-VM -Name $VMName -ErrorAction Stop).State -ne 'Running') {
    throw "$VMName is not running."
}

# Use domain credentials after promotion
$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message "Enter domain Administrator password for $VMName"

$Session = $null

try {
    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList $DomainName, $ExpectedIP `
        -ScriptBlock {

            param(
                [string]$DomainName,
                [string]$ExpectedIP
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory -ErrorAction Stop
            Import-Module DnsServer -ErrorAction Stop

            $Domain = Get-ADDomain -ErrorAction Stop
            $Forest = Get-ADForest -ErrorAction Stop
            $DC = Get-ADDomainController -Identity $env:COMPUTERNAME

            $Services = @(
                'NTDS',
                'DNS',
                'Netlogon',
                'KDC',
                'DFSR'
            )

            $ServiceResults = @(
                foreach ($ServiceName in $Services) {
                    $Service = Get-Service `
                        -Name $ServiceName `
                        -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        Name = $ServiceName
                        State = if ($Service) {
                            [string]$Service.Status
                        } else {
                            'MISSING'
                        }
                    }
                }
            )

            $Shares = @(
                Get-SmbShare -ErrorAction Stop |
                Select-Object -ExpandProperty Name
            )

            $HostRecords = @(
                Resolve-DnsName `
                    -Name "$env:COMPUTERNAME.$DomainName" `
                    -Type A `
                    -Server $ExpectedIP `
                    -ErrorAction Stop |
                Where-Object Type -eq 'A'
            )

            $SRVRecords = @(
                Resolve-DnsName `
                    -Name "_ldap._tcp.dc._msdcs.$DomainName" `
                    -Type SRV `
                    -Server $ExpectedIP `
                    -ErrorAction Stop
            )

            $Zone = Get-DnsServerZone `
                -Name $DomainName `
                -ErrorAction Stop

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                DomainName = $Domain.DNSRoot
                ForestName = $Forest.Name
                NetBIOSName = $Domain.NetBIOSName
                DomainMode = [string]$Domain.DomainMode
                ForestMode = [string]$Forest.ForestMode
                DomainController = $DC.HostName
                GlobalCatalog = [bool]$DC.IsGlobalCatalog
                DNSZone = $Zone.ZoneName
                DNSZoneADIntegrated = [bool]$Zone.IsDsIntegrated
                DNSHostRecordOK = (
                    @($HostRecords.IPAddress) -contains $ExpectedIP
                )
                DNSSRVRecordOK = ($SRVRecords.Count -gt 0)
                SYSVOL = ($Shares -contains 'SYSVOL')
                NETLOGON = ($Shares -contains 'NETLOGON')
                Services = @($ServiceResults)
            }
        } `
        -ErrorAction Stop

    $Checks = [System.Collections.Generic.List[object]]::new()

    # Build a structured test report on the host
    $ExpectedChecks = [ordered]@{
        'Domain name' = @{
            Expected = $DomainName
            Actual = $Result.DomainName
            Pass = ($Result.DomainName -eq $DomainName)
        }
        'Forest name' = @{
            Expected = $DomainName
            Actual = $Result.ForestName
            Pass = ($Result.ForestName -eq $DomainName)
        }
        'NetBIOS name' = @{
            Expected = 'CONTOSO'
            Actual = $Result.NetBIOSName
            Pass = ($Result.NetBIOSName -eq 'CONTOSO')
        }
        'Domain functional level' = @{
            Expected = 'Windows2025Domain'
            Actual = $Result.DomainMode
            Pass = ($Result.DomainMode -eq 'Windows2025Domain')
        }
        'Forest functional level' = @{
            Expected = 'Windows2025Forest'
            Actual = $Result.ForestMode
            Pass = ($Result.ForestMode -eq 'Windows2025Forest')
        }
        'Global Catalog' = @{
            Expected = 'True'
            Actual = [string]$Result.GlobalCatalog
            Pass = $Result.GlobalCatalog
        }
        'DNS zone' = @{
            Expected = $DomainName
            Actual = $Result.DNSZone
            Pass = ($Result.DNSZone -eq $DomainName)
        }
        'AD-integrated DNS zone' = @{
            Expected = 'True'
            Actual = [string]$Result.DNSZoneADIntegrated
            Pass = $Result.DNSZoneADIntegrated
        }
        'DNS host A record' = @{
            Expected = 'True'
            Actual = [string]$Result.DNSHostRecordOK
            Pass = $Result.DNSHostRecordOK
        }
        'DNS LDAP SRV record' = @{
            Expected = 'True'
            Actual = [string]$Result.DNSSRVRecordOK
            Pass = $Result.DNSSRVRecordOK
        }
        'SYSVOL share' = @{
            Expected = 'True'
            Actual = [string]$Result.SYSVOL
            Pass = $Result.SYSVOL
        }
        'NETLOGON share' = @{
            Expected = 'True'
            Actual = [string]$Result.NETLOGON
            Pass = $Result.NETLOGON
        }
    }

    foreach ($Key in $ExpectedChecks.Keys) {
        $Entry = $ExpectedChecks[$Key]

        $Checks.Add(
            [PSCustomObject]@{
                Check = $Key
                Expected = $Entry.Expected
                Actual = $Entry.Actual
                Status = if ($Entry.Pass) { 'PASS' } else { 'FAIL' }
            }
        )
    }

    foreach ($Service in $Result.Services) {
        $Checks.Add(
            [PSCustomObject]@{
                Check = "Service: $($Service.Name)"
                Expected = 'Running'
                Actual = $Service.State
                Status = if ($Service.State -eq 'Running') {
                    'PASS'
                } else {
                    'FAIL'
                }
            }
        )
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Host "LAB 3 - AD DS AND DNS VERIFICATION"
    Write-Host "========================================"

    $Checks |
        Format-Table Check, Expected, Actual, Status -AutoSize |
        Out-Host

    $Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $CSV = Join-Path $ReportPath "LAB03-Verification_$Timestamp.csv"
    $TXT = Join-Path $ReportPath "LAB03-Verification_$Timestamp.txt"

    $Checks |
        Export-Csv -Path $CSV `
        -NoTypeInformation -Encoding UTF8

    $Checks |
        Format-Table -AutoSize |
        Out-String -Width 180 |
        Out-File -FilePath $TXT -Encoding UTF8

    $Passed = @($Checks | Where-Object Status -eq 'PASS').Count
    $Failed = @($Checks | Where-Object Status -eq 'FAIL').Count

    Write-Host ""
    Write-Host "Passed: $Passed" -ForegroundColor Green
    Write-Host "Failed: $Failed" -ForegroundColor Yellow
    Write-Host "CSV: $CSV"
    Write-Host "TXT: $TXT"

    if ($Failed -eq 0) {
        Write-Host "LAB 3 - ALL CHECKS PASSED" `
            -ForegroundColor Green
    } else {
        Write-Warning "LAB 3 - Verification requires attention."
    }
}
finally {
    if ($null -ne $Session) {
        Remove-PSSession $Session
    }
}
