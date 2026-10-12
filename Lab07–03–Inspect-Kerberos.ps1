# ==========================================================
# LAB 7 - Script 03 - Inspect Kerberos Authentication
#
# Run ONLY on host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# KDC / DNS: 10.10.10.10
#
# Virtual machines:
#   SEA-DC1  - 10.10.10.10
#   SEA-SRV1 - 10.10.10.20
#   SEA-SRV2 - 10.10.10.30
#   SEA-CL1  - 10.10.10.100
#
# Inspects:
#   Kerberos service (KDC)
#   Kerberos DNS SRV records
#   Kerberos TCP connectivity
#   Domain controller discovery
#   Windows Time service
#   Time synchronization status
#   Current PowerShell session tickets
#
# Reports: CSV, TXT, HTML
#
# This script does not modify system configuration.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$DomainController = 'SEA-DC1'
$DCAddress = '10.10.10.10'
$ReportDir = 'C:\LabReports'

$Targets = @(
    [PSCustomObject]@{
        VM = 'SEA-DC1'
        Role = 'DC'
    }
    [PSCustomObject]@{
        VM = 'SEA-SRV1'
        Role = 'Member'
    }
    [PSCustomObject]@{
        VM = 'SEA-SRV2'
        Role = 'Member'
    }
    [PSCustomObject]@{
        VM = 'SEA-CL1'
        Role = 'Member'
    }
)

# ----------------------------------------------------------
# 2. Initialize environment
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path `
    $ReportDir `
    "LAB07-Kerberos_$Timestamp.csv"

$TXT = Join-Path `
    $ReportDir `
    "LAB07-Kerberos_$Timestamp.txt"

$HTML = Join-Path `
    $ReportDir `
    "LAB07-Kerberos_$Timestamp.html"

$Checks = [System.Collections.Generic.List[object]]::new()
$Details = [System.Collections.Generic.List[string]]::new()

# ----------------------------------------------------------
# 3. Helper function
# ----------------------------------------------------------

function Add-LabCheck {

    param(
        [string]$Machine,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [string]$Status
    )

    $Checks.Add(
        [PSCustomObject]@{
            Machine = $Machine
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = $Status
        }
    )
}

# ----------------------------------------------------------
# 4. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - KERBEROS INSPECTION"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DomainController"
Write-Host "KDC address: $DCAddress"
Write-Host "Machines: $($Targets.Count)"
Write-Host ""

# ----------------------------------------------------------
# 5. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password for LAB 7'

if ($null -eq $Credential) {
    throw 'Domain credentials were not provided.'
}

# ----------------------------------------------------------
# 6. Process virtual machines
# ----------------------------------------------------------

foreach ($Target in $Targets) {

    $VMName = $Target.VM
    $Role = $Target.Role
    $Session = $null

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Inspecting Kerberos on $VMName"
    Write-Host "------------------------------------------"

    try {

        # --------------------------------------------------
        # 7. Verify Hyper-V virtual machine
        # --------------------------------------------------

        $VM = Get-VM `
            -Name $VMName `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "$VMName is not running."
        }

        # --------------------------------------------------
        # 8. Connect using PowerShell Direct
        # --------------------------------------------------

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # --------------------------------------------------
        # 9. Execute Kerberos checks inside the guest
        # --------------------------------------------------

        $Data = Invoke-Command `
            -Session $Session `
            -ArgumentList $Role, $DomainName, $DCAddress `
            -ScriptBlock {

                param(
                    [string]$Role,
                    [string]$DomainName,
                    [string]$DCAddress
                )

                $ErrorActionPreference = 'Stop'

                # ------------------------------------------
                # 10. Read computer information
                # ------------------------------------------

                $Computer = Get-CimInstance `
                    -ClassName Win32_ComputerSystem `
                    -ErrorAction Stop

                $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

                # ------------------------------------------
                # 11. Resolve Kerberos SRV records
                # ------------------------------------------

                $KerberosSRV = @()
                $SRVError = ''

                try {

                    $KerberosSRV = @(
                        Resolve-DnsName `
                            -Name "_kerberos._tcp.$DomainName" `
                            -Type SRV `
                            -Server $DCAddress `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.Type -eq 'SRV' -and
                            ([string]$_.NameTarget).TrimEnd('.') -ieq
                                "SEA-DC1.$DomainName"
                        }
                    )
                }
                catch {
                    $SRVError = $_.Exception.Message
                }

                $SRVOK = ($KerberosSRV.Count -gt 0)

                # ------------------------------------------
                # 12. Verify KDC TCP port 88
                # ------------------------------------------

                $KDCConnection = $false

                try {

                    $KDCConnection = [bool](
                        Test-NetConnection `
                            -ComputerName $DCAddress `
                            -Port 88 `
                            -InformationLevel Quiet `
                            -WarningAction SilentlyContinue
                    )
                }
                catch {
                    $KDCConnection = $false
                }

                # ------------------------------------------
                # 13. Discover the domain controller
                # ------------------------------------------

                $DCOutput = ''
                $DiscoveryOK = $false

                try {

                    $Lines = @(
                        & nltest.exe `
                            "/dsgetdc:$DomainName" `
                            2>&1
                    )

                    $DiscoveryExitCode = $LASTEXITCODE
                    $DCOutput = $Lines -join "`r`n"

                    $DiscoveryOK = (
                        $DiscoveryExitCode -eq 0
                    )
                }
                catch {
                    $DCOutput = $_.Exception.Message
                }

                # ------------------------------------------
                # 14. Verify Windows Time service
                # ------------------------------------------

                $W32TimeStatus = 'Unknown'
                $W32TimeOK = $false

                try {

                    $W32TimeStatus = [string](
                        Get-Service `
                            -Name W32Time `
                            -ErrorAction Stop
                    ).Status

                    $W32TimeOK = (
                        $W32TimeStatus -eq 'Running'
                    )
                }
                catch {
                    $W32TimeStatus = $_.Exception.Message
                }

                # ------------------------------------------
                # 15. Read time synchronization status
                # ------------------------------------------

                $TimeOutput = ''
                $TimeExitCode = -1

                try {

                    $TimeLines = @(
                        & w32tm.exe /query /status 2>&1
                    )

                    $TimeExitCode = $LASTEXITCODE
                    $TimeOutput = $TimeLines -join "`r`n"

                }
                catch {
                    $TimeOutput = $_.Exception.Message
                }

                # ------------------------------------------
                # 16. Inspect Kerberos ticket cache
                # ------------------------------------------

                # The ticket cache belongs to this
                # PowerShell Direct logon session,
                # not the user's interactive desktop.

                $KlistOutput = ''
                $KlistExitCode = -1

                try {

                    $KlistLines = @(
                        & klist.exe tickets 2>&1
                    )

                    $KlistExitCode = $LASTEXITCODE
                    $KlistOutput = $KlistLines -join "`r`n"

                }
                catch {
                    $KlistOutput = $_.Exception.Message
                }

                # ------------------------------------------
                # 17. Check whether TGT is visible
                # ------------------------------------------

                $TGTPresent = (
                    $KlistExitCode -eq 0 -and
                    $KlistOutput -match '(?i)krbtgt/'
                )

                # ------------------------------------------
                # 18. Verify the KDC service on SEA-DC1
                # ------------------------------------------

                $KDCServiceStatus = 'Not applicable'
                $KDCServiceOK = $true

                if ($Role -eq 'DC') {

                    $KDCServiceStatus = [string](
                        Get-Service `
                            -Name KDC `
                            -ErrorAction Stop
                    ).Status

                    $KDCServiceOK = (
                        $KDCServiceStatus -eq 'Running'
                    )
                }

                # ------------------------------------------
                # 19. Return serializable results
                # ------------------------------------------

                [PSCustomObject]@{
                    Computer = [string]$env:COMPUTERNAME
                    Domain = [string]$Computer.Domain
                    DomainMember = [bool]$Computer.PartOfDomain

                    Identity = [string]$Identity.Name

                    KerberosSRVOK = [bool]$SRVOK
                    KerberosSRVError = $SRVError

                    KDCConnection = [bool]$KDCConnection

                    DCDiscoveryOK = [bool]$DiscoveryOK
                    DCDiscoveryOutput = $DCOutput

                    W32TimeStatus = $W32TimeStatus
                    W32TimeOK = [bool]$W32TimeOK

                    TimeExitCode = [int]$TimeExitCode
                    TimeOutput = $TimeOutput

                    KlistExitCode = [int]$KlistExitCode
                    KlistOutput = $KlistOutput

                    TGTPresent = [bool]$TGTPresent

                    KDCServiceStatus = $KDCServiceStatus
                    KDCServiceOK = [bool]$KDCServiceOK
                }

            } `
            -ErrorAction Stop

        # --------------------------------------------------
        # 20. Add verification results
        # --------------------------------------------------

        Add-LabCheck `
            $VMName `
            'Domain membership' `
            $DomainName `
            $Data.Domain `
            $(if (
                $Data.DomainMember -and
                $Data.Domain -ieq $DomainName
            ) { 'PASS' } else { 'FAIL' })

        Add-LabCheck `
            $VMName `
            'Kerberos DNS SRV' `
            'SEA-DC1.contoso.com' `
            $(if ($Data.KerberosSRVOK) {
                'Resolved'
            } else {
                'Not resolved'
            }) `
            $(if ($Data.KerberosSRVOK) {
                'PASS'
            } else {
                'FAIL'
            })

        Add-LabCheck `
            $VMName `
            'KDC TCP 88' `
            'Reachable' `
            ([string]$Data.KDCConnection) `
            $(if ($Data.KDCConnection) {
                'PASS'
            } else {
                'FAIL'
            })

        Add-LabCheck `
            $VMName `
            'Domain controller discovery' `
            'Successful' `
            ([string]$Data.DCDiscoveryOK) `
            $(if ($Data.DCDiscoveryOK) {
                'PASS'
            } else {
                'FAIL'
            })

        Add-LabCheck `
            $VMName `
            'Windows Time service' `
            'Running' `
            $Data.W32TimeStatus `
            $(if ($Data.W32TimeOK) {
                'PASS'
            } else {
                'FAIL'
            })

        Add-LabCheck `
            $VMName `
            'Time status query' `
            'Exit code 0' `
            "Exit code $($Data.TimeExitCode)" `
            $(if ($Data.TimeExitCode -eq 0) {
                'PASS'
            } else {
                'FAIL'
            })

        # A successful KLIST execution is required.
        # An empty ticket cache is not automatically
        # considered a Kerberos infrastructure failure.

        Add-LabCheck `
            $VMName `
            'KLIST execution' `
            'Exit code 0' `
            "Exit code $($Data.KlistExitCode)" `
            $(if ($Data.KlistExitCode -eq 0) {
                'PASS'
            } else {
                'FAIL'
            })

        Add-LabCheck `
            $VMName `
            'TGT in current session' `
            'Informational' `
            ([string]$Data.TGTPresent) `
            'INFO'

        if ($Role -eq 'DC') {

            Add-LabCheck `
                $VMName `
                'KDC service' `
                'Running' `
                $Data.KDCServiceStatus `
                $(if ($Data.KDCServiceOK) {
                    'PASS'
                } else {
                    'FAIL'
                })
        }

        # --------------------------------------------------
        # 21. Store detailed command output
        # --------------------------------------------------

        $Detail = @"

============================================================
LAB 7 - KERBEROS DETAILS
MACHINE: $VMName
============================================================

Domain:
$($Data.Domain)

PowerShell Direct identity:
$($Data.Identity)

------------------------------------------------------------
KERBEROS DNS
------------------------------------------------------------
SRV resolved: $($Data.KerberosSRVOK)
Error: $($Data.KerberosSRVError)

------------------------------------------------------------
DOMAIN CONTROLLER DISCOVERY
------------------------------------------------------------
$($Data.DCDiscoveryOutput)

------------------------------------------------------------
WINDOWS TIME
------------------------------------------------------------
Service: $($Data.W32TimeStatus)

$($Data.TimeOutput)

------------------------------------------------------------
KERBEROS TICKETS - KLIST
------------------------------------------------------------
$($Data.KlistOutput)

TGT visible in this session:
$($Data.TGTPresent)

NOTE:
These tickets belong to the PowerShell Direct session.
They are not the interactive desktop user's tickets.

"@

        $Details.Add($Detail)

        Write-Host "Kerberos inspection completed." `
            -ForegroundColor Green

    }
    catch {

        $Message = $_.Exception.Message

        Add-LabCheck `
            $VMName `
            'PowerShell Direct inspection' `
            'Completed' `
            $Message `
            'FAIL'

        Write-Warning (
            "Kerberos inspection failed on ${VMName}: $Message"
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
# 23. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $Checks | Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Checks | Where-Object Status -eq 'FAIL'
).Count

$Info = @(
    $Checks | Where-Object Status -eq 'INFO'
).Count

$Total = $Checks.Count

# 7 required checks and 1 informational check per VM,
# plus the KDC service check on SEA-DC1.
$ExpectedCount = ($Targets.Count * 8) + 1

# ----------------------------------------------------------
# 24. Export CSV report
# ----------------------------------------------------------

$Checks |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 25. Export TXT report
# ----------------------------------------------------------

$Header = @"
LAB 7 - KERBEROS INSPECTION

Host: $env:COMPUTERNAME
Domain: $DomainName
Domain controller: $DomainController
Date: $(Get-Date)

Total: $Total
Expected: $ExpectedCount
Passed: $Passed
Failed: $Failed
Informational: $Info

"@

$Summary = $Checks |
    Format-Table `
        Machine, Check, Expected, Actual, Status `
        -AutoSize |
    Out-String -Width 220

$DetailedText = $Details -join "`r`n"

($Header + $Summary + "`r`n" + $DetailedText) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 26. Export HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    background: #f5f9fb;
    color: #294554;
}
h1, h2 {
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
pre {
    background: white;
    border: 1px solid #dce6eb;
    padding: 16px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
}
</style>
"@

$HTMLSummary = $Checks |
    ConvertTo-Html -Fragment |
    Out-String

$EncodedDetails = [System.Net.WebUtility]::HtmlEncode(
    $DetailedText
)

$HTMLBody = @"
<h1>LAB 7 - Kerberos Inspection</h1>
<p>Domain: $DomainName</p>
<p>Passed: $Passed | Failed: $Failed | Info: $Info</p>
$HTMLSummary
<h2>Detailed Kerberos diagnostics</h2>
<pre>$EncodedDetails</pre>
"@

ConvertTo-Html `
    -Title 'LAB 7 - Kerberos Inspection' `
    -Head $CSS `
    -Body $HTMLBody |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 27. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - KERBEROS VERIFICATION REPORT"
Write-Host "=========================================="
Write-Host ""

$Checks |
    Format-Table Machine, Check, Status -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "Expected: $ExpectedCount"
Write-Host "Passed: $Passed" -ForegroundColor Green
Write-Host "Failed: $Failed" -ForegroundColor Yellow
Write-Host "Informational: $Info" -ForegroundColor Cyan

Write-Host ""
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 28. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0 -or $Total -ne $ExpectedCount) {

    Write-Warning (
        "LAB 7 - KERBEROS INSPECTION REQUIRES ATTENTION."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 7 - KERBEROS INSPECTION PASSED"
    Write-Host "=========================================="
}
