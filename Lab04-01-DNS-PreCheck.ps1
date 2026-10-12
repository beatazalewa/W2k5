
# ==========================================================
# LAB 4 - Script 01 - DNS PreCheck
# Run on Hyper-V host as Administrator
# Target: SEA-DC1
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'
$DomainName = 'contoso.com'
$DnsIP = '10.10.10.10'

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "$VMName is not running."
}

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message "Enter domain Administrator password for $VMName"

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

$Session = $null

try {
    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList $DomainName, $DnsIP `
        -ScriptBlock {

            param(
                [string]$DomainName,
                [string]$DnsIP
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory
            Import-Module DnsServer

            $Domain = Get-ADDomain
            $Computer = Get-CimInstance Win32_ComputerSystem
            $DnsFeature = Get-WindowsFeature DNS

            $DnsService = Get-Service DNS
            $NtdsService = Get-Service NTDS
            $NetlogonService = Get-Service Netlogon

            $IP = Get-NetIPAddress `
                -IPAddress $DnsIP `
                -AddressFamily IPv4 `
                -ErrorAction Stop

            $ClientDNS = @(
                (Get-DnsClientServerAddress `
                    -InterfaceIndex $IP.InterfaceIndex `
                    -AddressFamily IPv4).ServerAddresses
            )

            $Zones = @(
                Get-DnsServerZone |
                Select-Object ZoneName, ZoneType,
                    IsDsIntegrated, DynamicUpdate
            )

            $ForwardZone = @(
                $Zones |
                Where-Object ZoneName -eq $DomainName
            )

            $Tests = @(
                [PSCustomObject]@{
                    Check = 'Domain name'
                    Expected = $DomainName
                    Actual = $Domain.DNSRoot
                    Pass = ($Domain.DNSRoot -eq $DomainName)
                }
                [PSCustomObject]@{
                    Check = 'Domain controller role'
                    Expected = '4 or 5'
                    Actual = [string]$Computer.DomainRole
                    Pass = ($Computer.DomainRole -in @(4,5))
                }
                [PSCustomObject]@{
                    Check = 'DNS Server role'
                    Expected = 'Installed'
                    Actual = [string]$DnsFeature.Installed
                    Pass = [bool]$DnsFeature.Installed
                }
                [PSCustomObject]@{
                    Check = 'DNS service'
                    Expected = 'Running'
                    Actual = [string]$DnsService.Status
                    Pass = ($DnsService.Status -eq 'Running')
                }
                [PSCustomObject]@{
                    Check = 'NTDS service'
                    Expected = 'Running'
                    Actual = [string]$NtdsService.Status
                    Pass = ($NtdsService.Status -eq 'Running')
                }
                [PSCustomObject]@{
                    Check = 'Netlogon service'
                    Expected = 'Running'
                    Actual = [string]$NetlogonService.Status
                    Pass = ($NetlogonService.Status -eq 'Running')
                }
                [PSCustomObject]@{
                    Check = 'DNS client address'
                    Expected = $DnsIP
                    Actual = ($ClientDNS -join ', ')
                    Pass = (
                        $ClientDNS.Count -eq 1 -and
                        $ClientDNS[0] -eq $DnsIP
                    )
                }
                [PSCustomObject]@{
                    Check = 'Forward DNS zone'
                    Expected = $DomainName
                    Actual = ($ForwardZone.ZoneName -join ', ')
                    Pass = ($ForwardZone.Count -eq 1)
                }
                [PSCustomObject]@{
                    Check = 'AD-integrated forward zone'
                    Expected = 'True'
                    Actual = [string](
                        $ForwardZone.Count -eq 1 -and
                        $ForwardZone[0].IsDsIntegrated
                    )
                    Pass = (
                        $ForwardZone.Count -eq 1 -and
                        [bool]$ForwardZone[0].IsDsIntegrated
                    )
                }
            )

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Tests = @($Tests)
                Zones = @($Zones)
            }
        } `
        -ErrorAction Stop

    Write-Host "`nLAB 4 - DNS PRECHECK" -ForegroundColor Cyan

    $Result.Tests |
        Format-Table Check, Expected, Actual, Pass -AutoSize |
        Out-Host

    Write-Host "`nEXISTING DNS ZONES" -ForegroundColor Cyan

    $Result.Zones |
        Format-Table ZoneName, ZoneType,
            IsDsIntegrated, DynamicUpdate -AutoSize |
        Out-Host

    $Failed = @(
        $Result.Tests | Where-Object { -not $_.Pass }
    ).Count

    Write-Host "`nFailed checks: $Failed"

    if ($Failed -gt 0) {
        throw 'DNS precheck failed. Resolve issues before continuing.'
    }

    Write-Host 'LAB 4 - DNS PRECHECK PASSED' -ForegroundColor Green
}
finally {
    if ($null -ne $Session) {
        Remove-PSSession -Session $Session
    }
}
