# ==========================================================
# LAB 3 - Script 01 - Active Directory PreCheck
# Run on Hyper-V host as Administrator
# ==========================================================

$ErrorActionPreference = 'Stop'
$VMName = 'SEA-DC1'
$SwitchName = 'LabSwitch'

Import-Module Hyper-V -ErrorAction Stop

$VM = Get-VM -Name $VMName -ErrorAction Stop
if ($VM.State -ne 'Running') {
    throw "$VMName is not running."
}

$Adapters = @(
    Get-VMNetworkAdapter -VMName $VMName |
    Where-Object SwitchName -eq $SwitchName
)

if ($Adapters.Count -ne 1) {
    throw "Expected one network adapter on $SwitchName."
}

$Credential = Get-Credential `
    -UserName '.\Administrator' `
    -Message "Enter local Administrator password for $VMName"

$Session = $null

try {
    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    $Result = Invoke-Command -Session $Session -ScriptBlock {

        $ErrorActionPreference = 'Stop'

        $ExpectedIP = '10.10.10.10'
        $IP = Get-NetIPAddress `
            -IPAddress $ExpectedIP `
            -AddressFamily IPv4 `
            -ErrorAction Stop

        $DNS = @(
            (Get-DnsClientServerAddress `
                -InterfaceIndex $IP.InterfaceIndex `
                -AddressFamily IPv4).ServerAddresses
        )

        $DefaultRoutes = @(
            Get-NetRoute `
                -AddressFamily IPv4 `
                -DestinationPrefix '0.0.0.0/0' `
                -ErrorAction SilentlyContinue
        )

        $Computer = Get-CimInstance Win32_ComputerSystem
        $OS = Get-CimInstance Win32_OperatingSystem

        $ADDS = Get-WindowsFeature AD-Domain-Services

        $Checks = @(
            [PSCustomObject]@{
                Check = 'Computer name'
                Pass = ($env:COMPUTERNAME -eq 'SEA-DC1')
            }
            [PSCustomObject]@{
                Check = 'Windows Server 2025'
                Pass = ($OS.Caption -like '*Windows Server 2025*')
            }
            [PSCustomObject]@{
                Check = 'IPv4 address'
                Pass = (
                    $IP.IPAddress -eq $ExpectedIP -and
                    $IP.PrefixLength -eq 24
                )
            }
            [PSCustomObject]@{
                Check = 'DNS client'
                Pass = (
                    $DNS.Count -eq 1 -and
                    $DNS[0] -eq $ExpectedIP
                )
            }
            [PSCustomObject]@{
                Check = 'No default gateway'
                Pass = ($DefaultRoutes.Count -eq 0)
            }
            [PSCustomObject]@{
                Check = 'Workgroup member'
                Pass = (-not $Computer.PartOfDomain)
            }
            [PSCustomObject]@{
                Check = 'Not a domain controller'
                Pass = ($Computer.DomainRole -notin @(4,5))
            }
            [PSCustomObject]@{
                Check = 'AD DS not yet configured'
                Pass = (-not (Test-Path 'C:\Windows\NTDS\ntds.dit'))
            }
        )

        $Checks
    } -ErrorAction Stop

    Write-Host "`nLAB 3 - PRECHECK REPORT" -ForegroundColor Cyan
    $Result | Format-Table Check, Pass -AutoSize | Out-Host

    $Failed = @($Result | Where-Object { -not $_.Pass })

    if ($Failed.Count -gt 0) {
        throw "$($Failed.Count) prerequisite check(s) failed."
    }

    Write-Host "LAB 3 - PRECHECK PASSED" -ForegroundColor Green
}
finally {
    if ($null -ne $Session) {
        Remove-PSSession $Session
    }
}
