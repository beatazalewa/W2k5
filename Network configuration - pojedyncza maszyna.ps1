# =====================================================
# Network configuration - pojedyncza maszyna
# =====================================================

Get-NetAdapter | Format-Table Name, Status, LinkSpeed, MacAddress

Get-NetIPConfiguration

Get-NetIPAddress -AddressFamily IPv4 |
    Format-Table InterfaceAlias, IPAddress, PrefixLength, AddressState

Get-NetRoute -AddressFamily IPv4 |
    Format-Table DestinationPrefix, NextHop, InterfaceAlias


<#
Powinniśmy zobaczyć:
Parametr	    Oczekiwana wartość
IPv4	        10.10.10.100
PrefixLength	24
DNS	            10.10.10.10
Brama	        Brak
Adapter	        Up
Trasa	        10.10.10.0/24 przez kartę LabSwitch

Zwróć szczególną uwagę na AddressState. Powinno być Preferred. Jeśli widzisz Tentative lub Duplicate, może występować problem z przypisaniem adresu.

#>