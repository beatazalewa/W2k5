# ==========================================================
# LAB 5 - Script 01 - Active Directory PreCheck
# Run on Hyper-V host as Administrator
# ==========================================================

$ErrorActionPreference = 'Stop'
Import-Module Hyper-V -ErrorAction Stop

$VMName = 'SEA-DC1'

if ((Get-VM -Name $VMName).State -ne 'Running') {
    throw 'SEA-DC1 is not running.'
}

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

$Session = $null

try {
    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    $Result = Invoke-Command -Session $Session -ScriptBlock {

        $ErrorActionPreference = 'Stop'
        Import-Module ActiveDirectory

        $Domain = Get-ADDomain
        $DC = Get-ADDomainController -Identity 'SEA-DC1'
        $Computer = Get-CimInstance Win32_ComputerSystem

        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Domain       = $Domain.DNSRoot
            DistinguishedName = $Domain.DistinguishedName
            DomainController = $DC.HostName
            GlobalCatalog = $DC.IsGlobalCatalog
            DomainRole = $Computer.DomainRole
            ADDSService = (Get-Service NTDS).Status
            DNSService = (Get-Service DNS).Status
            Status = if (
                $Domain.DNSRoot -eq 'contoso.com' -and
                $Computer.DomainRole -in @(4,5) -and
                (Get-Service NTDS).Status -eq 'Running' -and
                (Get-Service DNS).Status -eq 'Running'
            ) { 'PASS' } else { 'FAIL' }
        }
    } -ErrorAction Stop

    $Result | Format-List | Out-Host

    if ($Result.Status -ne 'PASS') {
        throw 'Active Directory precheck failed.'
    }

    Write-Host 'LAB 5 - PRECHECK PASSED' -ForegroundColor Green
}
finally {
    if ($Session) {
        Remove-PSSession $Session
    }
}