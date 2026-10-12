# ==========================================================
# LAB 6 - Script 04 - Verify Domain Environment
#
# Run ONLY on host as Administrator.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# DNS server: 10.10.10.10
#
# Target computers:
#   SEA-SRV1 - 10.10.10.20
#   SEA-SRV2 - 10.10.10.30
#   SEA-CL1  - 10.10.10.100
#
# Prerequisites:
#   All computers joined to contoso.com
#   Required restarts completed
#   Computer accounts moved to appropriate OUs
#
# Reports: CSV, TXT, HTML
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 2. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$DomainController = 'SEA-DC1'
$DNSServer = '10.10.10.10'

$ReportDir = 'C:\LabReports'

$Targets = @(

    [PSCustomObject]@{
        VM = 'SEA-SRV1'
        IP = '10.10.10.20'
    }

    [PSCustomObject]@{
        VM = 'SEA-SRV2'
        IP = '10.10.10.30'
    }

    [PSCustomObject]@{
        VM = 'SEA-CL1'
        IP = '10.10.10.100'
    }
)

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

# ----------------------------------------------------------
# 3. Define report paths
# ----------------------------------------------------------

$CSV = Join-Path `
    $ReportDir `
    "LAB06-Domain-Verification_$Timestamp.csv"

$TXT = Join-Path `
    $ReportDir `
    "LAB06-Domain-Verification_$Timestamp.txt"

$HTML = Join-Path `
    $ReportDir `
    "LAB06-Domain-Verification_$Timestamp.html"

# ----------------------------------------------------------
# 4. Initialize verification results
# ----------------------------------------------------------

$Checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {

    param(
        [string]$Machine,
        [string]$Check,
        [string]$Expected,
        $Actual,
        [bool]$Pass
    )

    $Checks.Add(

        [PSCustomObject]@{
            Machine  = $Machine
            Check    = $Check
            Expected = $Expected
            Actual   = [string]$Actual
            Status   = if ($Pass) { 'PASS' } else { 'FAIL' }
        }

    )
}

# ----------------------------------------------------------
# 5. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - DOMAIN VERIFICATION"
Write-Host "=========================================="
Write-Host ""
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DomainController"
Write-Host "DNS server: $DNSServer"
Write-Host "Computers: $($Targets.Count)"
Write-Host ""

# ----------------------------------------------------------
# 6. Request domain administrator credentials
# ----------------------------------------------------------

$DomainCredential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator credentials'

if ($null -eq $DomainCredential) {
    throw 'Domain credentials were not provided.'
}

# ----------------------------------------------------------
# 7. Verify each member computer
# ----------------------------------------------------------

foreach ($Target in $Targets) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Verifying: $($Target.VM)"
    Write-Host "------------------------------------------"

    $Session = $null

    try {

        # --------------------------------------------------
        # 8. Verify Hyper-V machine state
        # --------------------------------------------------

        $VM = Get-VM `
            -Name $Target.VM `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "VM $($Target.VM) is not running."
        }

        # --------------------------------------------------
        # 9. Connect using PowerShell Direct
        # --------------------------------------------------

        $Session = New-PSSession `
            -VMName $Target.VM `
            -Credential $DomainCredential `
            -ErrorAction Stop

        # --------------------------------------------------
        # 10. Run verification inside member computer
        # --------------------------------------------------

        $Data = Invoke-Command `
            -Session $Session `
            -ArgumentList $Target.VM, $Target.IP `
            -ScriptBlock {

                param(
                    [string]$ExpectedName,
                    [string]$ExpectedIP
                )

                $ErrorActionPreference = 'Stop'

                # ------------------------------------------
                # 11. Read computer domain membership
                # ------------------------------------------

                $ComputerSystem = Get-CimInstance `
                    -ClassName Win32_ComputerSystem `
                    -ErrorAction Stop

                # ------------------------------------------
                # 12. Verify IPv4 address
                # ------------------------------------------

                $IPAddresses = @(
                    Get-NetIPAddress `
                        -AddressFamily IPv4 `
                        -ErrorAction Stop |
                    Where-Object {
                        $_.IPAddress -eq $ExpectedIP
                    }
                )

                $HasExpectedIP = (
                    $IPAddresses.Count -eq 1
                )

                # ------------------------------------------
                # 13. Read DNS client configuration
                # ------------------------------------------

                $DNSServers = @()

                if ($HasExpectedIP) {

                    $InterfaceIndex = (
                        $IPAddresses[0].InterfaceIndex
                    )

                    $DNSServers = @(
                        (
                            Get-DnsClientServerAddress `
                                -InterfaceIndex $InterfaceIndex `
                                -AddressFamily IPv4 `
                                -ErrorAction Stop
                        ).ServerAddresses
                    )
                }

                # ------------------------------------------
                # 14. Verify domain controller A record
                # ------------------------------------------

                $ARecords = @()

                try {

                    $ARecords = @(
                        Resolve-DnsName `
                            -Server '10.10.10.10' `
                            -Name 'SEA-DC1.contoso.com' `
                            -Type A `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.IPAddress -eq '10.10.10.10'
                        }
                    )

                }
                catch {
                    $ARecords = @()
                }

                # ------------------------------------------
                # 15. Verify Active Directory LDAP SRV record
                # ------------------------------------------

                $SRVRecords = @()

                try {

                    $SRVRecords = @(
                        Resolve-DnsName `
                            -Server '10.10.10.10' `
                            -Name '_ldap._tcp.dc._msdcs.contoso.com' `
                            -Type SRV `
                            -ErrorAction Stop
                    )

                }
                catch {
                    $SRVRecords = @()
                }

                # ------------------------------------------
                # 16. Verify reverse DNS lookup
                # ------------------------------------------

                $ReverseRecords = @()

                try {

                    $ReverseRecords = @(
                        Resolve-DnsName `
                            -Server '10.10.10.10' `
                            -Name '10.10.10.10.in-addr.arpa' `
                            -Type PTR `
                            -ErrorAction Stop |
                        Where-Object {
                            ([string]$_.NameHost).TrimEnd('.') -ieq
                                'SEA-DC1.contoso.com'
                        }
                    )

                }
                catch {
                    $ReverseRecords = @()
                }

                # ------------------------------------------
                # 17. Verify domain secure channel
                # ------------------------------------------

                $SecureChannel = $false

                if ($ComputerSystem.PartOfDomain) {

                    try {

                        $SecureChannel = [bool](
                            Test-ComputerSecureChannel `
                                -ErrorAction Stop
                        )

                    }
                    catch {
                        $SecureChannel = $false
                    }
                }

                # ------------------------------------------
                # 18. Verify LDAP TCP connectivity
                # ------------------------------------------

                $LDAPAvailable = $false

                try {

                    $LDAPAvailable = [bool](
                        Test-NetConnection `
                            -ComputerName '10.10.10.10' `
                            -Port 389 `
                            -InformationLevel Quiet `
                            -WarningAction SilentlyContinue
                    )

                }
                catch {
                    $LDAPAvailable = $false
                }

                # ------------------------------------------
                # 19. Return results to Hyper-V host
                # ------------------------------------------

                [PSCustomObject]@{
                    Name          = $env:COMPUTERNAME
                    ExpectedName  = $ExpectedName
                    Domain        = [string]$ComputerSystem.Domain
                    Member        = [bool]$ComputerSystem.PartOfDomain
                    HasIP         = [bool]$HasExpectedIP
                    DNS           = ($DNSServers -join ',')
                    DC_A          = [bool]($ARecords.Count -gt 0)
                    LDAP_SRV      = [bool]($SRVRecords.Count -gt 0)
                    PTR           = [bool]($ReverseRecords.Count -gt 0)
                    SecureChannel = [bool]$SecureChannel
                    LDAPPort      = [bool]$LDAPAvailable
                }

            } `
            -ErrorAction Stop

        # --------------------------------------------------
        # 20. Validate returned information
        # --------------------------------------------------

        Add-Check `
            $Target.VM `
            'Windows name' `
            $Target.VM `
            $Data.Name `
            ($Data.Name -eq $Target.VM)

        Add-Check `
            $Target.VM `
            'Domain membership' `
            'contoso.com' `
            $Data.Domain `
            ($Data.Member -and $Data.Domain -eq 'contoso.com')

        Add-Check `
            $Target.VM `
            'IPv4 address' `
            $Target.IP `
            $Data.HasIP `
            ([bool]$Data.HasIP)

        Add-Check `
            $Target.VM `
            'DNS client' `
            '10.10.10.10' `
            $Data.DNS `
            ($Data.DNS -eq '10.10.10.10')

        Add-Check `
            $Target.VM `
            'DC A record' `
            'True' `
            $Data.DC_A `
            ([bool]$Data.DC_A)

        Add-Check `
            $Target.VM `
            'LDAP SRV record' `
            'True' `
            $Data.LDAP_SRV `
            ([bool]$Data.LDAP_SRV)

        Add-Check `
            $Target.VM `
            'Reverse DNS lookup' `
            'True' `
            $Data.PTR `
            ([bool]$Data.PTR)

        Add-Check `
            $Target.VM `
            'LDAP TCP 389' `
            'True' `
            $Data.LDAPPort `
            ([bool]$Data.LDAPPort)

        Add-Check `
            $Target.VM `
            'Secure channel' `
            'True' `
            $Data.SecureChannel `
            ([bool]$Data.SecureChannel)

        Write-Host "Verification completed for $($Target.VM)." `
            -ForegroundColor Green

    }
    catch {

        # --------------------------------------------------
        # 21. Record verification failure
        # --------------------------------------------------

        $Message = $_.Exception.Message

        Add-Check `
            $Target.VM `
            'PowerShell Direct verification' `
            'Connected and checked' `
            $Message `
            $false

        Write-Warning (
            "Verification failed for $($Target.VM): $Message"
        )

    }
    finally {

        # --------------------------------------------------
        # 22. Close PowerShell Direct session
        # --------------------------------------------------

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 23. Verify computer accounts on domain controller
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - ACTIVE DIRECTORY COMPUTER ACCOUNTS"
Write-Host "=========================================="

$Session = $null

try {

    # ------------------------------------------------------
    # 24. Connect to domain controller
    # ------------------------------------------------------

    $Session = New-PSSession `
        -VMName 'SEA-DC1' `
        -Credential $DomainCredential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 25. Verify computer accounts and organizational units
    # ------------------------------------------------------

    $ComputerChecks = Invoke-Command `
        -Session $Session `
        -ArgumentList (,$Targets) `
        -ScriptBlock {

            param(
                [object[]]$Targets
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            $Domain = Get-ADDomain -ErrorAction Stop
            $DomainDN = $Domain.DistinguishedName

            foreach ($Target in $Targets) {

                $ComputerName = [string]$Target.VM

                # ------------------------------------------
                # 26. Find computer account in Active Directory
                # ------------------------------------------

                $ComputerAccount = Get-ADComputer `
                    -Filter "SamAccountName -eq '$ComputerName`$'" `
                    -Properties Enabled, DNSHostName `
                    -ErrorAction Stop

                # ------------------------------------------
                # 27. Determine expected organizational unit
                # ------------------------------------------

                if ($ComputerName -eq 'SEA-CL1') {
                    $ExpectedOU = 'Stacje robocze'
                }
                else {
                    $ExpectedOU = 'Serwery'
                }

                $TargetOU = "OU=$ExpectedOU,OU=Centrala,$DomainDN"

                # ------------------------------------------
                # 28. Verify account location
                # ------------------------------------------

                $InCorrectOU = $false

                if ($null -ne $ComputerAccount) {

                    $CurrentDN = [string](
                        $ComputerAccount.DistinguishedName
                    )

                    $InCorrectOU = $CurrentDN.EndsWith(
                        ",$TargetOU",
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                }

                # ------------------------------------------
                # 29. Return Active Directory account details
                # ------------------------------------------

                [PSCustomObject]@{
                    VM          = $ComputerName
                    Found       = [bool]($null -ne $ComputerAccount)
                    Enabled     = [bool](
                        $null -ne $ComputerAccount -and
                        $ComputerAccount.Enabled
                    )
                    InOU        = [bool]$InCorrectOU
                    DNSHostName = if ($ComputerAccount) {
                        [string]$ComputerAccount.DNSHostName
                    }
                    else {
                        ''
                    }
                }

            }

        } `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 30. Add Active Directory checks to final report
    # ------------------------------------------------------

    foreach ($Computer in $ComputerChecks) {

        $AccountOK = (
            $Computer.Found -and
            $Computer.Enabled
        )

        Add-Check `
            $Computer.VM `
            'AD computer account' `
            'Exists and enabled' `
            "Found=$($Computer.Found); Enabled=$($Computer.Enabled)" `
            $AccountOK

        Add-Check `
            $Computer.VM `
            'Correct AD OU' `
            'True' `
            $Computer.InOU `
            ([bool]$Computer.InOU)
    }

}
catch {

    Add-Check `
        'SEA-DC1' `
        'AD computer-account verification' `
        'Completed' `
        $_.Exception.Message `
        $false
}
finally {

    # ------------------------------------------------------
    # 31. Close domain controller session
    # ------------------------------------------------------

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------
# 32. Calculate verification statistics
# ----------------------------------------------------------

$Passed = @(
    $Checks |
    Where-Object {
        $_.Status -eq 'PASS'
    }
).Count

$Failed = @(
    $Checks |
    Where-Object {
        $_.Status -eq 'FAIL'
    }
).Count

$Total = $Passed + $Failed

# ----------------------------------------------------------
# 33. Export CSV report
# ----------------------------------------------------------

$Checks |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 34. Export TXT report
# ----------------------------------------------------------

$Header = @"
LAB 6 - DOMAIN VERIFICATION

Domain: $DomainName
Domain controller: $DomainController
Date: $(Get-Date)

Total: $Total
Passed: $Passed
Failed: $Failed

"@

$TextTable = $Checks |
    Format-Table `
        Machine,
        Check,
        Expected,
        Actual,
        Status `
        -AutoSize |
    Out-String -Width 220

($Header + $TextTable) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 35. Export HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    background: #f5f9fb;
    color: #294554;
}
h1 {
    color: #146393;
}
table {
    border-collapse: collapse;
    width: 100%;
    background: #ffffff;
}
th {
    background: #146393;
    color: #ffffff;
    padding: 9px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 8px;
}
</style>
"@

$HTMLHeader = @"
<h1>LAB 6 - Domain Verification</h1>
<p>Domain: $DomainName</p>
<p>Domain controller: $DomainController</p>
<p>Passed: $Passed | Failed: $Failed</p>
"@

$Checks |
    ConvertTo-Html `
        -Title 'LAB 6 - Domain Verification' `
        -Head $CSS `
        -PreContent $HTMLHeader |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 36. Display verification results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - FINAL VERIFICATION REPORT"
Write-Host "=========================================="
Write-Host ""

$Checks |
    Format-Table `
        Machine,
        Check,
        Status `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "Passed: $Passed" -ForegroundColor Green
Write-Host "Failed: $Failed" -ForegroundColor Yellow

Write-Host ""
Write-Host "Reports exported:"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 37. Final validation
# ----------------------------------------------------------

$ExpectedChecks = $Targets.Count * 11

if ($Total -ne $ExpectedChecks) {

    Write-Warning (
        "Expected $ExpectedChecks checks, but received $Total."
    )
}

if (
    $Failed -gt 0 -or
    $Total -ne $ExpectedChecks
) {

    throw (
        "LAB 6 - VERIFICATION FAILED. " +
        "Review the detailed reports."
    )
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - AUTOMATED VERIFICATION PASSED"
Write-Host "=========================================="

