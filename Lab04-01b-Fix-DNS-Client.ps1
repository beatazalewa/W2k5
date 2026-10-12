# ==========================================================
# LAB 4 - Fix DNS Client Configuration
# Run ONLY on Hyper-V host as Administrator
# Target: SEA-DC1
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'
$ExpectedIP = '10.10.10.10'
$ExpectedDNS = '10.10.10.10'

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "VM $VMName is not running."
}

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
        -ArgumentList $ExpectedIP, $ExpectedDNS `
        -ScriptBlock {

            param(
                [string]$ExpectedIP,
                [string]$ExpectedDNS
            )

            $ErrorActionPreference = 'Stop'

            # Identify the laboratory interface
            $IP = Get-NetIPAddress `
                -IPAddress $ExpectedIP `
                -AddressFamily IPv4 `
                -ErrorAction Stop

            $InterfaceIndex = $IP.InterfaceIndex

            # Read current DNS settings
            $CurrentDNS = @(
                (Get-DnsClientServerAddress `
                    -InterfaceIndex $InterfaceIndex `
                    -AddressFamily IPv4 `
                    -ErrorAction Stop).ServerAddresses
            )

            $BeforeDNS = $CurrentDNS -join ', '

            # Change DNS only if necessary
            if (
                $CurrentDNS.Count -ne 1 -or
                $CurrentDNS[0] -ne $ExpectedDNS
            ) {

                Set-DnsClientServerAddress `
                    -InterfaceIndex $InterfaceIndex `
                    -ServerAddresses $ExpectedDNS `
                    -ErrorAction Stop

                $Action = 'UPDATED'
            }
            else {
                $Action = 'UNCHANGED'
            }

            # Read DNS settings after configuration
            $FinalDNS = @(
                (Get-DnsClientServerAddress `
                    -InterfaceIndex $InterfaceIndex `
                    -AddressFamily IPv4 `
                    -ErrorAction Stop).ServerAddresses
            )

            $DNSOK = (
                $FinalDNS.Count -eq 1 -and
                $FinalDNS[0] -eq $ExpectedDNS
            )

            if (-not $DNSOK) {
                throw 'DNS client configuration verification failed.'
            }

            # Clear local DNS client cache
            Clear-DnsClientCache

            # Verify domain controller name resolution
            $DNSResult = @(
                Resolve-DnsName `
                    -Name 'SEA-DC1.contoso.com' `
                    -Type A `
                    -Server $ExpectedDNS `
                    -ErrorAction Stop |
                Where-Object Type -eq 'A'
            )

            $ResolutionOK = (
                $ExpectedIP -in @($DNSResult.IPAddress)
            )

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                Interface = $IP.InterfaceAlias
                IPv4 = $IP.IPAddress
                DNSBefore = $BeforeDNS
                DNSAfter = $FinalDNS -join ', '
                Action = $Action
                DNSConfigurationOK = $DNSOK
                DNSResolutionOK = $ResolutionOK
                Status = if ($DNSOK -and $ResolutionOK) {
                    'PASS'
                }
                else {
                    'FAIL'
                }
            }
        } `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "========================================"
    Write-Host "LAB 4 - DNS CLIENT FIX REPORT"
    Write-Host "========================================"

    $Result | Format-List | Out-Host
}
finally {

    if ($null -ne $Session) {
        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}
