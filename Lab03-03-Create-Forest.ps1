# ==========================================================
# LAB 3 - Script 03 - Create Active Directory Forest
# Run on Hyper-V host as Administrator
#
# Target VM: SEA-DC1
# Domain: CONTOSO.COM
# Functional level: Windows Server 2025
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Forest configuration
# ----------------------------------------------------------

$VMName = 'SEA-DC1'
$DomainName = 'contoso.com'
$NetBIOSName = 'CONTOSO'

$ForestMode = 'Win2025'
$DomainMode = 'Win2025'

$ExpectedIP = '10.10.10.10'

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 2. Verify VM state
# ----------------------------------------------------------

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "$VMName is not running."
}

Write-Host ""
Write-Host "========================================"
Write-Host "LAB 3 - CREATE ACTIVE DIRECTORY FOREST"
Write-Host "========================================"
Write-Host "VM:          $VMName"
Write-Host "Domain:      $DomainName"
Write-Host "NetBIOS:     $NetBIOSName"
Write-Host "Forest mode: $ForestMode"
Write-Host "Domain mode: $DomainMode"
Write-Host ""

# ----------------------------------------------------------
# 3. Require explicit confirmation
# ----------------------------------------------------------

$Confirmation = Read-Host `
    "Type CREATE to confirm new forest installation"

if ($Confirmation -cne 'CREATE') {
    throw 'Operation cancelled.'
}

# ----------------------------------------------------------
# 4. Request credentials and DSRM password
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName '.\Administrator' `
    -Message "Enter local Administrator password for $VMName"

if ($null -eq $Credential) {
    throw 'Credentials not provided.'
}

$DSRMPassword = Read-Host `
    'Enter Directory Services Restore Mode password' `
    -AsSecureString

if ($DSRMPassword.Length -eq 0) {
    throw 'DSRM password cannot be empty.'
}

$Session = $null

try {

    # ------------------------------------------------------
    # 5. Establish PowerShell Direct session
    # ------------------------------------------------------

    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 6. Create new forest inside the VM
    # ------------------------------------------------------

    $Result = Invoke-Command `
        -Session $Session `
        -ArgumentList `
            $VMName,
            $ExpectedIP,
            $DomainName,
            $NetBIOSName,
            $ForestMode,
            $DomainMode,
            $DSRMPassword `
        -ScriptBlock {

            param(
                [string]$ExpectedName,
                [string]$ExpectedIP,
                [string]$DomainName,
                [string]$NetBIOSName,
                [string]$ForestMode,
                [string]$DomainMode,
                [securestring]$DSRMPassword
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ADDSDeployment -ErrorAction Stop

            # Validate server identity
            if ($env:COMPUTERNAME -ne $ExpectedName) {
                throw 'Unexpected computer name.'
            }

            # Validate IPv4 address
            $IP = Get-NetIPAddress `
                -IPAddress $ExpectedIP `
                -AddressFamily IPv4 `
                -ErrorAction Stop

            if ($IP.PrefixLength -ne 24) {
                throw 'Unexpected network prefix.'
            }

            # Verify installed server role
            $Feature = Get-WindowsFeature `
                -Name AD-Domain-Services

            if (-not $Feature.Installed) {
                throw 'AD DS role is not installed.'
            }

            # Prevent accidental repeated promotion
            $Computer = Get-CimInstance Win32_ComputerSystem

            if ($Computer.DomainRole -in @(4,5)) {
                throw 'Computer is already a domain controller.'
            }

            if ($Computer.PartOfDomain) {
                throw 'Computer already belongs to a domain.'
            }

            # Install the first domain controller
            # Reboot is deliberately deferred for verification
            $Installation = Install-ADDSForest `
                -DomainName $DomainName `
                -DomainNetbiosName $NetBIOSName `
                -ForestMode $ForestMode `
                -DomainMode $DomainMode `
                -InstallDns:$true `
                -CreateDnsDelegation:$false `
                -SafeModeAdministratorPassword $DSRMPassword `
                -NoRebootOnCompletion:$true `
                -Force:$true `
                -ErrorAction Stop

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                DomainName = $DomainName
                NetBIOSName = $NetBIOSName
                ForestMode = $ForestMode
                DomainMode = $DomainMode
                InstallationCompleted = $true
                RestartRequired = $true
                Status = 'RESTART_REQUIRED'
            }
        } `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "========================================"
    Write-Host "LAB 3 - FOREST INSTALLATION RESULT"
    Write-Host "========================================"

    $Result | Format-List | Out-Host

    Write-Host ""
    Write-Host "Forest installation completed." `
        -ForegroundColor Green

    Write-Host "Restart SEA-DC1 to finalize promotion." `
        -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "LAB 3 - FOREST INSTALLATION ERROR" `
        -ForegroundColor Red

    Write-Host $_.Exception.Message -ForegroundColor Red

    throw
}
finally {
    if ($null -ne $Session) {
        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }

    $DSRMPassword = $null
}
