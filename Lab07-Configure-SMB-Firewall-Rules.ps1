# ==========================================================
# LAB 7 - Configure SMB Firewall Rules
#
# Run ONLY on host as Administrator.
# Target VMs:
#   SEA-SRV1
#   SEA-SRV2
#
# Allow inbound SMB TCP 445 from LAB network only.
# ==========================================================

$ErrorActionPreference = 'Stop'

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$VMNames = @(
    'SEA-SRV1'
    'SEA-SRV2'
)

$RuleName = 'LAB07-Allow-SMB-TCP445'
$LabNetwork = '10.10.10.0/24'

# ----------------------------------------------------------
# 2. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

# ----------------------------------------------------------
# 3. Configure each server
# ----------------------------------------------------------

foreach ($VMName in $VMNames) {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Configuring SMB firewall: $VMName"
    Write-Host "=========================================="

    $Session = $null

    try {

        # Verify VM state
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "$VMName is not running."
        }

        # Connect using PowerShell Direct
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Configure firewall inside the guest
        $Result = Invoke-Command `
            -Session $Session `
            -ArgumentList $RuleName, $LabNetwork `
            -ScriptBlock {

                param(
                    [string]$RuleName,
                    [string]$LabNetwork
                )

                $ErrorActionPreference = 'Stop'

                $Rule = Get-NetFirewallRule `
                    -Name $RuleName `
                    -ErrorAction SilentlyContinue

                if (-not $Rule) {

                    New-NetFirewallRule `
                        -Name $RuleName `
                        -DisplayName 'LAB07 - Allow SMB TCP 445' `
                        -Direction Inbound `
                        -Action Allow `
                        -Protocol TCP `
                        -LocalPort 445 `
                        -RemoteAddress $LabNetwork `
                        -Profile Domain `
                        -Enabled True `
                        -ErrorAction Stop | Out-Null

                    $Action = 'CREATED'
                }
                else {

                    # Ensure the existing rule matches lab policy
                    Set-NetFirewallRule `
                        -Name $RuleName `
                        -Direction Inbound `
                        -Action Allow `
                        -Profile Domain `
                        -Enabled True `
                        -ErrorAction Stop

                    Set-NetFirewallPortFilter `
                        -AssociatedNetFirewallRule $Rule `
                        -Protocol TCP `
                        -LocalPort 445 `
                        -ErrorAction Stop

                    Set-NetFirewallAddressFilter `
                        -AssociatedNetFirewallRule $Rule `
                        -RemoteAddress $LabNetwork `
                        -ErrorAction Stop

                    $Action = 'UPDATED'
                }

                # Verify the final firewall configuration
                $VerifiedRule = Get-NetFirewallRule `
                    -Name $RuleName `
                    -ErrorAction Stop

                $PortFilter = $VerifiedRule |
                    Get-NetFirewallPortFilter

                $AddressFilter = $VerifiedRule |
                    Get-NetFirewallAddressFilter

                [PSCustomObject]@{
                    Computer = $env:COMPUTERNAME
                    Rule = $RuleName
                    Action = $Action
                    Enabled = [string]$VerifiedRule.Enabled
                    Profile = [string]$VerifiedRule.Profile
                    Protocol = [string]$PortFilter.Protocol
                    LocalPort = [string]$PortFilter.LocalPort
                    RemoteAddress = (
                        $AddressFilter.RemoteAddress -join ','
                    )
                }

            } `
            -ErrorAction Stop

        $Result |
            Format-List |
            Out-Host

        Write-Host "Firewall configured successfully." `
            -ForegroundColor Green

    }
    catch {

        Write-Warning (
            "Failed to configure ${VMName}: $($_.Exception.Message)"
        )
    }
    finally {

        if ($null -ne $Session) {
            Remove-PSSession $Session
        }
    }
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - SMB FIREWALL CONFIGURATION FINISHED"
Write-Host "=========================================="
