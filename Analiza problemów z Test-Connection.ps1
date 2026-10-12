# =====================================================
# Analiza problemów z Test-Connection
# =====================================================


<#
Analiza wyników SEA-CL1
Parametr	             Wynik	            Ocena
Karta Ethernet	         Up	                Poprawnie
Hyper-V Network Adapter	 Wykryty	        Poprawnie
Adres IPv4	             10.10.10.100	    Poprawnie
Maska	                 /24	            Poprawnie
AddressState	         Preferred	        Poprawnie
Trasa 10.10.10.0/24	     Ethernet	        Poprawnie
Brama domyślna	         Brak	            Prawidłowo dla LAB 1
DNS                      10.10.10.10	    Docelowy DNS domenowy

Zwróć uwagę na:
NetProfile.Name : Unidentified network

To nie jest błąd. Ponieważ nie masz jeszcze domeny Active Directory ani działającego DNS domenowego, Windows 11 może identyfikować sieć jako niezidentyfikowaną i stosować profil zapory Public.


2. Co oznacza błąd „Error due to lack of resources”?
Ponieważ karta jest aktywna, adres IP ma stan Preferred, a trasa do 10.10.10.0/24 istnieje, możemy wykluczyć kilka podstawowych błędów konfiguracji.
Nie możemy jednak jeszcze stwierdzić, czy problem wynika z:
- zapory na SEA-DC1,
- komunikacji między kartami Hyper-V,
- działania polecenia Test-Connection,
- lokalnego problemu ze stosem ICMP Windows 11.
Następnym krokiem nie jest zmiana adresacji IP, lecz sprawdzenie rzeczywistej komunikacji.
3. Wykonaj cztery testy na SEA-CL1
W tej samej sesji PowerShell Direct uruchom:
#>
# Test lokalnego stosu TCP/IP
ping.exe -n 2 127.0.0.1

# Test wlasnego adresu IPv4
ping.exe -n 2 10.10.10.100

# Test kontrolera domeny (przyszlego)
ping.exe -n 2 10.10.10.10

# Test serwera czlonkowskiego
ping.exe -n 2 10.10.10.20


<# Wyniki pozwolą rozróżnić problem lokalny od problemu komunikacji między VM.
4. Sprawdź ARP na SEA-CL1
Po wykonaniu pingów:
#>

Get-NetNeighbor `
    -InterfaceIndex 10 `
    -AddressFamily IPv4 |
    Format-Table IPAddress, LinkLayerAddress, State


<# Szczególnie interesują nas wpisy dla:
10.10.10.10 oraz 10.10.10.20.
Jeżeli wpisy mają prawidłowe adresy MAC i stan Reachable lub Stale, oznacza to, że rozpoznawanie adresów sąsiadów w sieci lokalnej działa.
Jeżeli widzisz Incomplete lub Unreachable, należy sprawdzić połączenia VM z LabSwitch oraz konfigurację sieci na pozostałych serwerach.
5. Sprawdzenie zapory Windows
Na SEA-DC1 wykonaj:
#> 
Get-NetFirewallRule -Name 'LAB01-Allow-ICMPv4' `
    -ErrorAction SilentlyContinue |
    Format-Table Name, Enabled, Direction, Action


# Jeżeli reguła nie istnieje, utwórz ją:
New-NetFirewallRule `
    -Name 'LAB01-Allow-ICMPv4' `
    -DisplayName 'LAB 1 - Allow ICMPv4' `
    -Direction Inbound `
    -Protocol ICMPv4 `
    -IcmpType 8 `
    -RemoteAddress '10.10.10.0/24' `
    -Action Allow `
    -Profile Any


<# Nie wyłączaj całej zapory Windows Defender. Dla szkolenia dotyczącego hardeningu lepiej stosować precyzyjne reguły.

Na razie nie zmieniaj niczego w konfiguracji SEA-CL1.
Prześlij mi wynik tych dwóch poleceń wykonanych na SEA-CL1:
#>
ping.exe -n 2 127.0.0.1
ping.exe -n 2 10.10.10.10


<# Jeśli pierwszy test działa, a drugi nie, przejdziemy do diagnostyki komunikacji pomiędzy SEA-CL1 a SEA-DC1 przez LabSwitch. Jeśli już test loopback zwróci błąd, skupimy się na lokalnym stosie TCP/IP Windows 11.
#>