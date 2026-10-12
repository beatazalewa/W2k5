# ==========================================================
# LAB 1 - Configure ICMPv4 Firewall Rules on Hyper-V VMs
# Run ONLY on the Hyper-V host as Administrator
# Uses PowerShell Direct - no network connection required
# ==========================================================

$ErrorActionPreference = 'Stop'

# Virtual machines
$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

# Firewall rule settings
$RuleName   = 'LAB01-Allow-ICMPv4'
$LabSubnet  = '10.10.10.0/24'

Import-Module Hyper-V -ErrorAction Stop

$Results = foreach ($VMName in $VMs) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "===================================="
        Write-Host "Processing VM: $VMName" -ForegroundColor Cyan
        Write-Host "===================================="

        # Verify that the VM is running
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "$VMName is not running."
        }

        # Select local administrator account
        $UserName = if ($VMName -eq 'SEA-CL1') {
            '.\Admin'
        }
        else {
            '.\Administrator'
        }

        # Request credentials for this VM
        $Credential = Get-Credential `
            -UserName $UserName `
            -Message "Enter password for $UserName on $VMName"

        if ($null -eq $Credential) {
            throw "Credentials not provided."
        }

        # Create PowerShell Direct session
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Configure firewall inside the virtual machine
        $Result = Invoke-Command `
            -Session $Session `
            -ArgumentList $RuleName, $LabSubnet `
            -ScriptBlock {

                param(
                    [string]$RuleName,
                    [string]$LabSubnet
                )

                $ErrorActionPreference = 'Stop'

                # Check existing firewall rule
                $ExistingRule = Get-NetFirewallRule `
                    -Name $RuleName `
                    -ErrorAction SilentlyContinue

                if ($ExistingRule) {

                    # Update existing rule
                    Set-NetFirewallRule `
                        -Name $RuleName `
                        -DisplayName 'LAB 1 - Allow ICMPv4' `
                        -Direction Inbound `
                        -Action Allow `
                        -Enabled True `
                        -Profile Any

                    Get-NetFirewallRule -Name $RuleName |
                        Get-NetFirewallAddressFilter |
                        Set-NetFirewallAddressFilter -RemoteAddress $LabSubnet

                    $ActionTaken = 'UPDATED'
                }
                else {

                    # Create new firewall rule
                    New-NetFirewallRule `
                        -Name $RuleName `
                        -DisplayName 'LAB 1 - Allow ICMPv4' `
                        -Direction Inbound `
                        -Protocol ICMPv4 `
                        -IcmpType 8 `
                        -RemoteAddress $LabSubnet `
                        -Action Allow `
                        -Profile Any `
                        -Enabled True `
                        -ErrorAction Stop | Out-Null

                    $ActionTaken = 'CREATED'
                }

                # Verify rule configuration
                $Rule = Get-NetFirewallRule `
                    -Name $RuleName `
                    -ErrorAction Stop

                $AddressFilter = $Rule |
                    Get-NetFirewallAddressFilter

                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    RuleName     = $Rule.Name
                    Enabled      = $Rule.Enabled
                    Action       = $Rule.Action
                    RemoteAddress = $AddressFilter.RemoteAddress -join ', '
                    ActionTaken  = $ActionTaken
                }
            } `
            -ErrorAction Stop

        Write-Host "$VMName - ICMPv4 rule configured." `
            -ForegroundColor Green

        [PSCustomObject]@{
            VMName       = $VMName
            ComputerName = $Result.ComputerName
            RuleName     = $Result.RuleName
            ActionTaken  = $Result.ActionTaken
            Status       = 'OK'
            Error        = ''
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message

        Write-Warning ("{0}: {1}" -f $VMName, $ErrorMessage)

        [PSCustomObject]@{
            VMName       = $VMName
            ComputerName = ''
            RuleName     = $RuleName
            ActionTaken  = ''
            Status       = 'FAILED'
            Error        = $ErrorMessage
        }
    }
    finally {
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# Display summary
Write-Host ""
Write-Host "===================================="
Write-Host "LAB 1 - ICMP FIREWALL REPORT"
Write-Host "===================================="

$Results |
    Format-Table VMName, ComputerName, ActionTaken, Status, Error -AutoSize
