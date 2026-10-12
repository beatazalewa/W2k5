# =====================================================
# Network configuration - sprawdzanie problemów z Test-Connection
# =====================================================

ping.exe 127.0.0.1
ping.exe 10.10.10.100
ping.exe 10.10.10.10

<#
Interpretacja:
Wynik	                                   Wniosek
Nie działa 127.0.0.1	                   Problem z lokalnym stosem TCP/IP
Działa 127.0.0.1, ale nie własny IP	       Problem z konfiguracją interfejsu
Działa własny IP, ale nie 10.10.10.10	   Sprawdź LabSwitch, ARP i zaporę
ping.exe działa, ale Test-Connection nie   Problem może dotyczyć mechanizmu używanego przez cmdlet

Wykonaj również:
Test-NetConnection -ComputerName 10.10.10.10 -InformationLevel Detailed

#>