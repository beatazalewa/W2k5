# ==========================================================
# LAB 7 - Script 01 - Authentication Environment PreCheck
#
# Run ONLY on host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# DNS server: 10.10.10.10
# Hyper-V switch: LabSwitch
#
# Virtual machines:
#   SEA-DC1  - 10.10.10.10
#   SEA-SRV1 - 10.10.10.20
#   SEA-SRV2 - 10.10.10.30
#   SEA-CL1  - 10.10.10.100
#
# Checks:
#   Hyper-V VM existence and state
#   Hyper-V virtual switch
#   Windows computer name
#   Active Directory domain membership
#   IPv4 address and DNS client configuration
#   Domain controller DNS resolution
#   Computer secure channel using NLTEST
#   Security event log availability
#   Domain controller services
#
# Reports: CSV, TXT, HTML
# This script is read-only.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$DomainController = 'SEA-DC1'
$DNSServer = '10.10.10.10'
$SwitchName = 'LabSwitch'

$ReportDir = 'C:\LabReports'

$Targets = @(

    [PSCustomObject]@{
        VM = 'SEA-DC1'
        IP = '10.10.10.10'
        Role = 'DC'
    }

    [PSCustomObject]@{
        VM = 'SEA-SRV1'
        IP = '10.10.10.20'
        Role = 'Member'
    }

    [PSCustomObject]@{
        VM = 'SEA-SRV2'
        IP = '10.10.10.30'
        Role = 'Member'
    }

    [PSCustomObject]@{
        VM = 'SEA-CL1'
        IP = '10.10.10.100'
        Role = 'Member'
    }
)

# ----------------------------------------------------------
# 2. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 3. Prepare reports
# ----------------------------------------------------------

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path `
    $ReportDir `
    "LAB07-PreCheck_$Timestamp.csv"

$TXT = Join-Path `
    $ReportDir `
    "LAB07-PreCheck_$Timestamp.txt"

$HTML = Join-Path `
    $ReportDir `
    "LAB07-PreCheck_$Timestamp.html"

$Results = [System.Collections.Generic.List[object]]::new()

# ----------------------------------------------------------
# 4. Helper function
# ----------------------------------------------------------

function Add-LabCheck {

    param(
        [string]$Machine,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [bool]$Passed
    )

    $Results.Add(
        [PSCustomObject]@{
            Machine = $Machine
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = if ($Passed) {
                'PASS'
            }
            else {
                'FAIL'
            }
        }
    )
}

# ----------------------------------------------------------
# 5. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - AUTHENTICATION PRECHECK"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DomainController"
Write-Host "DNS server: $DNSServer"
Write-Host "Virtual switch: $SwitchName"
Write-Host "Machines: $($Targets.Count)"
Write-Host ""

# ----------------------------------------------------------
# 6. Verify Hyper-V configuration
# ----------------------------------------------------------

foreach ($Target in $Targets) {

    $VM = Get-VM `
        -Name $Target.VM `
        -ErrorAction SilentlyContinue

    $Exists = ($null -ne $VM)

    Add-LabCheck `
        $Target.VM `
        'Hyper-V VM exists' `
        'True' `
        ([string]$Exists) `
        $Exists

    if (-not $Exists) {

        Add-LabCheck `
            $Target.VM `
            'VM running' `
            'True' `
            'VM missing' `
            $false

        Add-LabCheck `
            $Target.VM `
            'Hyper-V switch' `
            $SwitchName `
            'VM missing' `
            $false

        continue
    }

    # Check VM state
    $Running = (
        [string]$VM.State -eq 'Running'
    )

    Add-LabCheck `
        $Target.VM `
        'VM running' `
        'True' `
        ([string]$Running) `
        $Running

    # Check virtual network adapters
    $Adapters = @(
        Get-VMNetworkAdapter `
            -VMName $Target.VM `
            -ErrorAction SilentlyContinue
    )

    $SwitchOK = @(
        $Adapters |
        Where-Object {
            $_.SwitchName -eq $SwitchName
        }
    ).Count -gt 0

    $ActualSwitches = (
        $Adapters |
        Select-Object -ExpandProperty SwitchName
    ) -join ','

    Add-LabCheck `
        $Target.VM `
        'Hyper-V switch' `
        $SwitchName `
        $ActualSwitches `
        $SwitchOK
}

# ----------------------------------------------------------
# 7. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password for LAB 7'

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 8. Verify guest operating systems
# ----------------------------------------------------------

foreach ($Target in $Targets) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Checking: $($Target.VM)"
    Write-Host "------------------------------------------"

    $Session = $null

    try {

        $VM = Get-VM `
            -Name $Target.VM `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw 'Virtual machine is not running.'
        }

        # --------------------------------------------------
        # 9. Connect using PowerShell Direct
        # --------------------------------------------------

        $Session = New-PSSession `
            -VMName $Target.VM `
            -Credential $Credential `
            -ErrorAction Stop

        # --------------------------------------------------
        # 10. Execute checks inside guest
        # --------------------------------------------------

        $Data = Invoke-Command `
            -Session $Session `
            -ArgumentList `
                $Target.VM, `
                $Target.IP, `
                $Target.Role, `
                $DomainName, `
                $DNSServer `
            -ScriptBlock {

                param(
                    [string]$ExpectedName,
                    [string]$ExpectedIP,
                    [string]$Role,
                    [string]$ExpectedDomain,
                    [string]$ExpectedDNS
                )

                $ErrorActionPreference = 'Stop'

                # ------------------------------------------
                # 11. Read computer information
                # ------------------------------------------

                $Computer = Get-CimInstance `
                    -ClassName Win32_ComputerSystem `
                    -ErrorAction Stop

                # ------------------------------------------
                # 12. Verify IPv4 configuration
                # ------------------------------------------

                $Addresses = @(
                    Get-NetIPAddress `
                        -AddressFamily IPv4 `
                        -ErrorAction Stop |
                    Where-Object {
                        $_.IPAddress -eq $ExpectedIP
                    }
                )

                $IPOK = ($Addresses.Count -eq 1)

                # ------------------------------------------
                # 13. Verify DNS client configuration
                # ------------------------------------------

                $DNSServers = @()

                if ($IPOK) {

                    $InterfaceIndex = (
                        $Addresses[0].InterfaceIndex
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

                $DNSClientOK = (
                    $DNSServers.Count -eq 1 -and
                    $DNSServers[0] -eq $ExpectedDNS
                )

                # ------------------------------------------
                # 14. Verify domain controller DNS record
                # ------------------------------------------

                $DNSResolutionOK = $false

                try {

                    $DNSAnswers = @(
                        Resolve-DnsName `
                            -Name 'SEA-DC1.contoso.com' `
                            -Type A `
                            -Server $ExpectedDNS `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.IPAddress -eq $ExpectedDNS
                        }
                    )

                    $DNSResolutionOK = (
                        $DNSAnswers.Count -gt 0
                    )
                }
                catch {
                    $DNSResolutionOK = $false
                }

                # ------------------------------------------
                # 15. Verify domain secure channel
                #     using NLTEST instead of PowerShell
                #     Test-ComputerSecureChannel.
                # ------------------------------------------

                $SecureChannelOK = $false
                $SecureChannelDetails = 'Not tested'

                if (
                    $Role -eq 'Member' -and
                    $Computer.PartOfDomain
                ) {

                    try {

                        $NltestOutput = @(
                            & nltest.exe `
                                "/sc_verify:$ExpectedDomain" `
                                2>&1
                        )

                        $NltestExitCode = $LASTEXITCODE

                        $SecureChannelOK = (
                            $NltestExitCode -eq 0
                        )

                        $SecureChannelDetails = (
                            $NltestOutput -join ' '
                        )

                    }
                    catch {

                        $SecureChannelOK = $false

                        $SecureChannelDetails = (
                            $_.Exception.Message
                        )
                    }
                }

                # Secure channel test is not applicable
                # to a domain controller.
                if ($Role -eq 'DC') {

                    $SecureChannelOK = $true

                    $SecureChannelDetails = (
                        'Not applicable to a domain controller'
                    )
                }

                # ------------------------------------------
                # 16. Verify Security event log
                # ------------------------------------------

                $SecurityLogOK = $false

                try {

                    $Log = Get-WinEvent `
                        -ListLog Security `
                        -ErrorAction Stop

                    $SecurityLogOK = [bool]$Log.IsEnabled

                }
                catch {
                    $SecurityLogOK = $false
                }

                # ------------------------------------------
                # 17. Verify domain controller services
                # ------------------------------------------

                $NTDSOK = $true
                $KDCOK = $true
                $DNSServiceOK = $true
                $NetlogonOK = $true

                if ($Role -eq 'DC') {

                    $NTDSStatus = [string](
                        Get-Service `
                            -Name 'NTDS' `
                            -ErrorAction Stop
                    ).Status

                    $KDCStatus = [string](
                        Get-Service `
                            -Name 'KDC' `
                            -ErrorAction Stop
                    ).Status

                    $DNSStatus = [string](
                        Get-Service `
                            -Name 'DNS' `
                            -ErrorAction Stop
                    ).Status

                    $NetlogonStatus = [string](
                        Get-Service `
                            -Name 'Netlogon' `
                            -ErrorAction Stop
                    ).Status

                    $NTDSOK = (
                        $NTDSStatus -eq 'Running'
                    )

                    $KDCOK = (
                        $KDCStatus -eq 'Running'
                    )

                    $DNSServiceOK = (
                        $DNSStatus -eq 'Running'
                    )

                    $NetlogonOK = (
                        $NetlogonStatus -eq 'Running'
                    )
                }

                # ------------------------------------------
                # 18. Return serializable results
                # ------------------------------------------

                [PSCustomObject]@{
                    Name = [string]$env:COMPUTERNAME
                    Domain = [string]$Computer.Domain
                    DomainMember = [bool]$Computer.PartOfDomain

                    IPOK = [bool]$IPOK

                    DNSClient = ($DNSServers -join ',')
                    DNSClientOK = [bool]$DNSClientOK
                    DNSResolutionOK = [bool]$DNSResolutionOK

                    SecureChannelOK = [bool]$SecureChannelOK
                    SecureChannelDetails = $SecureChannelDetails

                    SecurityLogOK = [bool]$SecurityLogOK

                    NTDSOK = [bool]$NTDSOK
                    KDCOK = [bool]$KDCOK
                    DNSServiceOK = [bool]$DNSServiceOK
                    NetlogonOK = [bool]$NetlogonOK
                }

            } `
            -ErrorAction Stop

        # --------------------------------------------------
        # 19. Verify computer name
        # --------------------------------------------------

        Add-LabCheck `
            $Target.VM `
            'Computer name' `
            $Target.VM `
            $Data.Name `
            ($Data.Name -ieq $Target.VM)

        # --------------------------------------------------
        # 20. Verify domain membership
        # --------------------------------------------------

        $DomainOK = (
            $Data.DomainMember -and
            $Data.Domain -ieq $DomainName
        )

        Add-LabCheck `
            $Target.VM `
            'Domain membership' `
            $DomainName `
            $Data.Domain `
            $DomainOK

        # --------------------------------------------------
        # 21. Verify IPv4 address
        # --------------------------------------------------

        Add-LabCheck `
            $Target.VM `
            'IPv4 address' `
            $Target.IP `
            $(if ($Data.IPOK) {
                $Target.IP
            }
            else {
                'Missing'
            }) `
            ([bool]$Data.IPOK)

        # --------------------------------------------------
        # 22. Verify DNS client
        # --------------------------------------------------

        Add-LabCheck `
            $Target.VM `
            'DNS client' `
            $DNSServer `
            $Data.DNSClient `
            ([bool]$Data.DNSClientOK)

        # --------------------------------------------------
        # 23. Verify DNS resolution
        # --------------------------------------------------

        Add-LabCheck `
            $Target.VM `
            'Domain controller DNS' `
            'True' `
            ([string]$Data.DNSResolutionOK) `
            ([bool]$Data.DNSResolutionOK)

        # --------------------------------------------------
        # 24. Verify secure channel on member computers
        # --------------------------------------------------

        if ($Target.Role -eq 'Member') {

            Add-LabCheck `
                $Target.VM `
                'Domain secure channel' `
                'True' `
                ([string]$Data.SecureChannelOK) `
                ([bool]$Data.SecureChannelOK)
        }

        # --------------------------------------------------
        # 25. Verify Security event log
        # --------------------------------------------------

        Add-LabCheck `
            $Target.VM `
            'Security event log' `
            'Enabled' `
            $(if ($Data.SecurityLogOK) {
                'Enabled'
            }
            else {
                'Unavailable'
            }) `
            ([bool]$Data.SecurityLogOK)

        # --------------------------------------------------
        # 26. Verify domain controller services
        # --------------------------------------------------

        if ($Target.Role -eq 'DC') {

            $ServiceProperties = @(
                [PSCustomObject]@{
                    Name = 'NTDS'
                    Property = 'NTDSOK'
                }

                [PSCustomObject]@{
                    Name = 'KDC'
                    Property = 'KDCOK'
                }

                [PSCustomObject]@{
                    Name = 'DNS'
                    Property = 'DNSServiceOK'
                }

                [PSCustomObject]@{
                    Name = 'Netlogon'
                    Property = 'NetlogonOK'
                }
            )

            foreach ($Service in $ServiceProperties) {

                $PropertyName = $Service.Property

                $ServiceOK = [bool](
                    $Data.$PropertyName
                )

                Add-LabCheck `
                    $Target.VM `
                    "$($Service.Name) service" `
                    'Running' `
                    $(if ($ServiceOK) {
                        'Running'
                    }
                    else {
                        'Not running'
                    }) `
                    $ServiceOK
            }
        }

        Write-Host "Guest checks completed." `
            -ForegroundColor Green

    }
    catch {

        $Message = $_.Exception.Message

        Add-LabCheck `
            $Target.VM `
            'PowerShell Direct connection' `
            'Successful' `
            $Message `
            $false

        Write-Warning (
            "PreCheck failed for $($Target.VM): $Message"
        )
    }
    finally {

        # --------------------------------------------------
        # 27. Close PowerShell Direct session
        # --------------------------------------------------

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 28. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $Results |
    Where-Object {
        $_.Status -eq 'PASS'
    }
).Count

$Failed = @(
    $Results |
    Where-Object {
        $_.Status -eq 'FAIL'
    }
).Count

$Total = $Results.Count

# ----------------------------------------------------------
# 29. Calculate expected check count
# ----------------------------------------------------------

# 3 Hyper-V checks per VM:
#   VM exists
#   VM running
#   Hyper-V switch
#
# 6 common guest checks per VM:
#   Computer name
#   Domain membership
#   IPv4 address
#   DNS client
#   Domain controller DNS
#   Security event log
#
# 1 additional secure channel check per member VM
# 4 additional service checks for the domain controller

$ExpectedCount = (
    ($Targets.Count * 3) +
    ($Targets.Count * 6) +
    (@($Targets | Where-Object {
        $_.Role -eq 'Member'
    }).Count) +
    4
)

# Expected result for four VMs: 43

# ----------------------------------------------------------
# 30. Export CSV report
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 31. Export TXT report
# ----------------------------------------------------------

$Header = @"
LAB 7 - AUTHENTICATION PRECHECK

Host: $env:COMPUTERNAME
Domain: $DomainName
Domain controller: $DomainController
Date: $(Get-Date)

Total: $Total
Expected: $ExpectedCount
Passed: $Passed
Failed: $Failed

"@

$Table = $Results |
    Format-Table `
        Machine,
        Check,
        Expected,
        Actual,
        Status `
        -AutoSize |
    Out-String -Width 220

($Header + $Table) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 32. Export HTML report
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
tr:nth-child(even) {
    background: #f5f9fb;
}
</style>
"@

$HTMLHeader = @"
<h1>LAB 7 - Authentication PreCheck</h1>
<p><strong>Host:</strong> $env:COMPUTERNAME</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>Domain controller:</strong> $DomainController</p>
<p><strong>Total:</strong> $Total</p>
<p><strong>Passed:</strong> $Passed</p>
<p><strong>Failed:</strong> $Failed</p>
"@

$Results |
    ConvertTo-Html `
        -Title 'LAB 7 - Authentication PreCheck' `
        -Head $CSS `
        -PreContent $HTMLHeader |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 33. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - PRECHECK RESULTS"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table Machine, Check, Status -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "Expected: $ExpectedCount"
Write-Host "Passed: $Passed" -ForegroundColor Green
Write-Host "Failed: $Failed" -ForegroundColor Yellow

Write-Host ""
Write-Host "Reports exported:"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 34. Final validation
# ----------------------------------------------------------

if ($Total -ne $ExpectedCount) {

    Write-Warning (
        "Expected $ExpectedCount checks, " +
        "but received $Total."
    )
}

if (
    $Failed -gt 0 -or
    $Total -ne $ExpectedCount
) {

    throw (
        "LAB 7 - PRECHECK FAILED. " +
        "Review the detailed reports."
    )
}

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - PRECHECK PASSED"
Write-Host "=========================================="
