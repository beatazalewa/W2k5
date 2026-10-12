# =====================================================
# PowerShell Direct - pojedyncza maszyna SEA-CL1
# =====================================================

<#
PowerShell Direct jest wbudowany w Hyper-V i nie wymaga osobnej instalacji. W Twoim środowisku z Windows Server 2025 i Windows 11 Enterprise LTSC 2024 powinien działać.
Możesz to sprawdzić bez Internetu i bez skonfigurowanych adresów IP.
1. Sprawdź, czy masz dostępne polecenia PowerShell Direct
Na hoście Hyper-V, uruchom Windows PowerShell 5.1 jako administrator i wykonaj:
#>
Get-Command Enter-PSSession, New-PSSession, Invoke-Command


# Następnie sprawdź, czy Enter-PSSession obsługuje parametr VMName:
(Get-Command Enter-PSSession).Parameters.ContainsKey('VMName')


<#
Wynik: True oznacza to, że Twoja wersja PowerShell obsługuje składnię PowerShell Direct. Nie potwierdza jeszcze, że połączenie z konkretną maszyną będzie działać.
#>

# 2. Sprawdź połączenie z SEA-CL1. Najpierw sprawdź, czy maszyna jest uruchomiona:
Get-VM -Name 'SEA-CL1'


# Jeżeli jej stan to Running, wykonaj:
Enter-PSSession -VMName 'SEA-CL1' -Credential (Get-Credential)


<#
W oknie logowania podaj nazwę i hasło administratora systemu wewnątrz SEA-DC1, a nie konta hosta Hyper-V.
Jeśli jest to konto lokalne, możesz użyć:
SEA-CL1\Admin lub Admin
#>

<#
Jeśli połączenie się powiedzie, zobaczysz prompt podobny do:
[SEA-CL1]: PS C:\Users\Admin\Documents>
#>


# Teraz wykonaj:
hostname
Get-NetAdapter


<#
Jeśli pojawią się informacje dotyczące SEA-CL1, PowerShell Direct działa prawidłowo.
Aby zakończyć sesję:
#>
Exit-PSSession