# ==========================================================
# Checking ICMPv4 rules
#
# Run from PSSession 
# Connection: PowerShell Direct
# ==========================================================


$Rule = Get-NetFirewallRule -Name 'LAB01-Allow-ICMPv4'

$Rule | Format-List Name, Enabled, Direction, Action, Profile

$Rule |
    Get-NetFirewallPortFilter |
    Format-List Protocol, IcmpType

$Rule |
    Get-NetFirewallAddressFilter |
    Format-List LocalAddress, RemoteAddress