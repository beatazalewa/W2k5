# ==========================================================
# LAB 8 - Verify Effective Firewall Configuration
# Run on Hyper-V host as Administrator.
# ==========================================================

$CredentialParameters = @{
    UserName = 'CONTOSO\Administrator'
    Message  = 'Enter domain Administrator password'
}

$Credential = Get-Credential @CredentialParameters

$InvokeParameters = @{
    VMName      = 'SEA-CL1'
    Credential  = $Credential
    ErrorAction = 'Stop'
    ScriptBlock = {

        Write-Host ""
        Write-Host "=== LOCAL FIREWALL PROFILE ==="

        Get-NetFirewallProfile -Name Domain |
            Format-List Name,
                        Enabled,
                        DefaultInboundAction,
                        DefaultOutboundAction

        Write-Host ""
        Write-Host "=== EFFECTIVE FIREWALL PROFILE ==="

        Get-NetFirewallProfile `
            -PolicyStore ActiveStore `
            -Name Domain |
            Format-List Name,
                        Enabled,
                        DefaultInboundAction,
                        DefaultOutboundAction

        Write-Host ""
        Write-Host "=== DOMAIN FIREWALL REGISTRY POLICY ==="

        Get-ItemProperty `
            -Path 'HKLM:\Software\Policies\Microsoft\WindowsFirewall\DomainProfile' |
            Select-Object EnableFirewall,
                          DefaultInboundAction,
                          DefaultOutboundAction
    }
}

Invoke-Command @InvokeParameters
