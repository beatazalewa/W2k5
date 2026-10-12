# ==========================================================
# LAB 3 - Script 02 - Install AD DS Role
# Run on Hyper-V host as Administrator
# ==========================================================

$ErrorActionPreference = 'Stop'
$VMName = 'SEA-DC1'

Import-Module Hyper-V -ErrorAction Stop

if ((Get-VM -Name $VMName -ErrorAction Stop).State -ne 'Running') {
    throw "$VMName is not running."
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

        $Computer = Get-CimInstance Win32_ComputerSystem

        if ($Computer.DomainRole -in @(4, 5)) {
            throw 'This computer is already a domain controller.'
        }

        $Feature = Get-WindowsFeature `
            -Name AD-Domain-Services `
            -ErrorAction Stop

        if (-not $Feature.Installed) {
            $Installation = Install-WindowsFeature `
                -Name AD-Domain-Services `
                -IncludeManagementTools `
                -ErrorAction Stop

            if (-not $Installation.Success) {
                throw 'AD DS feature installation failed.'
            }

            $RestartNeeded = [string]$Installation.RestartNeeded
        }
        else {
            $RestartNeeded = 'No'
        }

        $Feature = Get-WindowsFeature `
            -Name AD-Domain-Services `
            -ErrorAction Stop

        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Feature = $Feature.Name
            Installed = $Feature.Installed
            RestartNeeded = $RestartNeeded
            Status = if ($Feature.Installed) {
                'PASS'
            } else {
                'FAIL'
            }
        }
    } -ErrorAction Stop

    Write-Host "`nLAB 3 - AD DS ROLE INSTALLATION" `
        -ForegroundColor Cyan

    $Result | Format-List | Out-Host

    if ($Result.Status -ne 'PASS') {
        throw 'AD DS installation verification failed.'
    }

    if ($Result.RestartNeeded -notin @('No', 'False')) {
        Write-Warning 'Restart SEA-DC1 before continuing.'
    }
}
finally {
    if ($null -ne $Session) {
        Remove-PSSession $Session
    }
}
