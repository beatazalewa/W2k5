# ==========================================================
# LAB 8 - Script 08 - Final Report
#
# Run ONLY on the Hyper-V host as Administrator.
# Requires Windows PowerShell 5.1.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# Client: SEA-CL1
#
# Tasks:
#   Verify Hyper-V laboratory machines
#   Import the latest LAB08-07 CSV report
#   Validate all 43 previous verification records
#   Read the current domain account policy
#   Verify GPO existence, status and direct OU links
#   Generate consolidated CSV, TXT and HTML reports
#
# This script is read-only.
# It does not modify GPOs or Active Directory.
# It does not create VM checkpoints.
# ==========================================================

[CmdletBinding()]
param(
    [string]$ReportDir = 'C:\LabReports',
    [string]$DomainName = 'contoso.com',
    [string]$DCName = 'SEA-DC1',
    [string]$ClientName = 'SEA-CL1'
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$HostName = $env:COMPUTERNAME
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$ExpectedLab07Checks = 43

$VMNames = @(
    'SEA-DC1'
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

$FinanceOU = (
    'OU=Uzytkownicy,OU=Finanse,' +
    'OU=Centrala,DC=contoso,DC=com'
)

$WorkstationOU = (
    'OU=Stacje robocze,' +
    'OU=Centrala,DC=contoso,DC=com'
)

$CSV = Join-Path $ReportDir (
    "LAB08-Final-Report_$Timestamp.csv"
)

$TXT = Join-Path $ReportDir (
    "LAB08-Final-Report_$Timestamp.txt"
)

$HTML = Join-Path $ReportDir (
    "LAB08-Final-Report_$Timestamp.html"
)

$Checks = New-Object 'System.Collections.Generic.List[object]'

# ----------------------------------------------------------
# 2. Helper function
# ----------------------------------------------------------

function Add-LabCheck {
    param(
        [string]$Area,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [ValidateSet('PASS','FAIL','REVIEW','INFO')]
        [string]$Status
    )

    [void]$Checks.Add(
        [PSCustomObject]@{
            Area = $Area
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = $Status
        }
    )
}

# ----------------------------------------------------------
# 3. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - FINAL REPORT"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host "Client: $ClientName"
Write-Host ""

# ----------------------------------------------------------
# 4. Verify execution environment
# ----------------------------------------------------------

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal `
    -ArgumentList $Identity

$IsAdministrator = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdministrator) {
    throw 'Run Windows PowerShell as Administrator.'
}

Import-Module Hyper-V -ErrorAction Stop

New-Item -Path $ReportDir `
    -ItemType Directory `
    -Force `
    -ErrorAction Stop | Out-Null

# ----------------------------------------------------------
# 5. Verify laboratory virtual machines
# ----------------------------------------------------------

Write-Host "Checking Hyper-V virtual machines..."

foreach ($VMName in $VMNames) {

    $VM = Get-VM `
        -Name $VMName `
        -ErrorAction SilentlyContinue

    if ($null -eq $VM) {

        Add-LabCheck `
            -Area 'Hyper-V' `
            -Check $VMName `
            -Expected 'Running' `
            -Actual 'Not found' `
            -Status 'FAIL'

        continue
    }

    $State = [string]$VM.State

    Add-LabCheck `
        -Area 'Hyper-V' `
        -Check $VMName `
        -Expected 'Running' `
        -Actual $State `
        -Status $(if ($State -eq 'Running') {
            'PASS'
        }
        else {
            'FAIL'
        })
}

# ----------------------------------------------------------
# 6. Locate the latest LAB08-07 report
# ----------------------------------------------------------

Write-Host "Locating LAB08-07 verification report..."

$Lab07File = Get-ChildItem `
    -Path $ReportDir `
    -Filter 'LAB08-Apply-And-Verify_*.csv' `
    -File `
    -ErrorAction Stop |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$Lab07Checks = @()
$Lab07FilePath = 'Not found'

if ($null -eq $Lab07File) {

    Add-LabCheck `
        -Area 'LAB08-07' `
        -Check 'Verification report available' `
        -Expected 'CSV report' `
        -Actual 'Not found' `
        -Status 'FAIL'
}
else {

    $Lab07FilePath = $Lab07File.FullName

    $Lab07Checks = @(
        Import-Csv `
            -Path $Lab07FilePath `
            -ErrorAction Stop
    )

    $HeadersOK = $true

    foreach ($Name in @(
        'Area',
        'Check',
        'Expected',
        'Actual',
        'Status'
    )) {

        if (
            $Lab07Checks.Count -eq 0 -or
            $Name -notin $Lab07Checks[0].PSObject.Properties.Name
        ) {
            $HeadersOK = $false
        }
    }

    Add-LabCheck `
        -Area 'LAB08-07' `
        -Check 'Verification report format' `
        -Expected 'Valid CSV columns' `
        -Actual ([string]$HeadersOK) `
        -Status $(if ($HeadersOK) {
            'PASS'
        }
        else {
            'FAIL'
        })

    Add-LabCheck `
        -Area 'LAB08-07' `
        -Check 'Number of verification records' `
        -Expected ([string]$ExpectedLab07Checks) `
        -Actual ([string]$Lab07Checks.Count) `
        -Status $(if (
            $Lab07Checks.Count -eq $ExpectedLab07Checks
        ) {
            'PASS'
        }
        else {
            'FAIL'
        })

    if ($HeadersOK) {

        foreach ($Item in $Lab07Checks) {

            $RecordedStatus = (
                [string]$Item.Status
            ).Trim().ToUpperInvariant()

            if ($RecordedStatus -notin @(
                'PASS',
                'FAIL',
                'REVIEW'
            )) {
                $RecordedStatus = 'FAIL'
            }

            Add-LabCheck `
                -Area ("LAB08-07 / " + [string]$Item.Area) `
                -Check ([string]$Item.Check) `
                -Expected ([string]$Item.Expected) `
                -Actual ([string]$Item.Actual) `
                -Status $RecordedStatus
        }
    }
}

# ----------------------------------------------------------
# 7. Request domain administrator credentials
# ----------------------------------------------------------

$CredentialParameters = @{
    UserName = 'CONTOSO\Administrator'
    Message = 'Enter domain Administrator password'
}

$Credential = Get-Credential @CredentialParameters

if ($null -eq $Credential) {
    throw 'Credentials were not supplied.'
}

# ----------------------------------------------------------
# 8. Connect to SEA-DC1
# ----------------------------------------------------------

$DCData = @()
$Session = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 9. Read current domain and GPO configuration
    # ------------------------------------------------------

    $DCData = @(
        Invoke-Command `
            -Session $Session `
            -ArgumentList @(
                $DomainName,
                $FinanceOU,
                $WorkstationOU
            ) `
            -ScriptBlock {

                param(
                    [string]$ExpectedDomain,
                    [string]$FinanceOU,
                    [string]$WorkstationOU
                )

                $ErrorActionPreference = 'Stop'

                Import-Module ActiveDirectory
                Import-Module GroupPolicy

                $Domain = Get-ADDomain -ErrorAction Stop

                if ($Domain.DNSRoot -ine $ExpectedDomain) {
                    throw "Unexpected domain: $($Domain.DNSRoot)"
                }

                # ------------------------------------------
                # Read domain account policy
                # ------------------------------------------

                $Policy = Get-ADDefaultDomainPasswordPolicy `
                    -Identity $ExpectedDomain `
                    -ErrorAction Stop

                $PolicyTests = @(
                    @{
                        Name = 'Minimum password length'
                        Expected = '12'
                        Actual = [string]$Policy.MinPasswordLength
                        OK = ($Policy.MinPasswordLength -eq 12)
                    }
                    @{
                        Name = 'Password history'
                        Expected = '24'
                        Actual = [string]$Policy.PasswordHistoryCount
                        OK = ($Policy.PasswordHistoryCount -eq 24)
                    }
                    @{
                        Name = 'Password complexity'
                        Expected = 'True'
                        Actual = [string]$Policy.ComplexityEnabled
                        OK = ($Policy.ComplexityEnabled -eq $true)
                    }
                    @{
                        Name = 'Account lockout threshold'
                        Expected = '5'
                        Actual = [string]$Policy.LockoutThreshold
                        OK = ($Policy.LockoutThreshold -eq 5)
                    }
                    @{
                        Name = 'Account lockout duration'
                        Expected = '15 minutes'
                        Actual = "$($Policy.LockoutDuration.TotalMinutes) minutes"
                        OK = ($Policy.LockoutDuration.TotalMinutes -eq 15)
                    }
                    @{
                        Name = 'Lockout reset interval'
                        Expected = '15 minutes'
                        Actual = "$($Policy.LockoutObservationWindow.TotalMinutes) minutes"
                        OK = ($Policy.LockoutObservationWindow.TotalMinutes -eq 15)
                    }
                )

                foreach ($Test in $PolicyTests) {

                    [PSCustomObject]@{
                        RecordType = 'CHECK'
                        Area = 'Current domain policy'
                        Name = [string]$Test.Name
                        Expected = [string]$Test.Expected
                        Actual = [string]$Test.Actual
                        Status = if ($Test.OK) {
                            'PASS'
                        }
                        else {
                            'FAIL'
                        }
                    }
                }

                # ------------------------------------------
                # Verify GPO existence and direct OU links
                # ------------------------------------------

                $Definitions = @(
                    @{
                        Name = 'LAB08-Desktop-Finance'
                        Target = $FinanceOU
                    }
                    @{
                        Name = 'LAB08-System-Workstations'
                        Target = $WorkstationOU
                    }
                    @{
                        Name = 'LAB08-Security-Workstations'
                        Target = $WorkstationOU
                    }
                )

                foreach ($Definition in $Definitions) {

                    $GPO = Get-GPO `
                        -Name $Definition.Name `
                        -Domain $ExpectedDomain `
                        -ErrorAction Stop

                    $Inheritance = Get-GPInheritance `
                        -Target $Definition.Target `
                        -Domain $ExpectedDomain `
                        -ErrorAction Stop

                    $Links = @(
                        $Inheritance.GpoLinks |
                        Where-Object {
                            [string]$_.GpoId -eq
                            [string]$GPO.Id
                        }
                    )

                    $LinkOK = (
                        $Links.Count -eq 1 -and
                        [string]$Links[0].Enabled -in
                            @('Yes','True')
                    )

                    $Status = [string]$GPO.GpoStatus

                    $CorrectSideEnabled = if (
                        $Definition.Name -eq
                        'LAB08-Desktop-Finance'
                    ) {
                        $Status -in @(
                            'AllSettingsEnabled',
                            'ComputerSettingsDisabled'
                        )
                    }
                    else {
                        $Status -in @(
                            'AllSettingsEnabled',
                            'UserSettingsDisabled'
                        )
                    }

                    [PSCustomObject]@{
                        RecordType = 'CHECK'
                        Area = 'Current GPO configuration'
                        Name = $Definition.Name
                        Expected = 'Exists and correct side enabled'
                        Actual = $Status
                        Status = if ($CorrectSideEnabled) {
                            'PASS'
                        }
                        else {
                            'FAIL'
                        }
                    }

                    [PSCustomObject]@{
                        RecordType = 'CHECK'
                        Area = 'Current GPO links'
                        Name = $Definition.Name
                        Expected = 'Direct OU link enabled'
                        Actual = [string]$LinkOK
                        Status = if ($LinkOK) {
                            'PASS'
                        }
                        else {
                            'FAIL'
                        }
                    }

                    [PSCustomObject]@{
                        RecordType = 'GPO'
                        Name = $Definition.Name
                        GPOID = [string]$GPO.Id
                        GPOStatus = $Status
                        TargetOU = $Definition.Target
                        LinkEnabled = [bool]$LinkOK
                    }
                }

            } `
            -ErrorAction Stop
    )

}
finally {

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------
# 10. Validate returned records
# ----------------------------------------------------------

$DCChecks = @(
    $DCData |
    Where-Object RecordType -eq 'CHECK'
)

$GPORecords = @(
    $DCData |
    Where-Object RecordType -eq 'GPO'
)

if ($DCChecks.Count -ne 12) {
    throw (
        "Expected 12 current DC checks; received " +
        $DCChecks.Count
    )
}

if ($GPORecords.Count -ne 3) {
    throw (
        "Expected 3 GPO records; received " +
        $GPORecords.Count
    )
}

foreach ($Item in $DCChecks) {

    Add-LabCheck `
        -Area ([string]$Item.Area) `
        -Check ([string]$Item.Name) `
        -Expected ([string]$Item.Expected) `
        -Actual ([string]$Item.Actual) `
        -Status ([string]$Item.Status)
}

# ----------------------------------------------------------
# 11. Calculate final statistics
# ----------------------------------------------------------

$Passed = @(
    $Checks |
    Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Checks |
    Where-Object Status -eq 'FAIL'
).Count

$Review = @(
    $Checks |
    Where-Object Status -eq 'REVIEW'
).Count

$Info = @(
    $Checks |
    Where-Object Status -eq 'INFO'
).Count

$Total = $Checks.Count

$FinalStatus = if ($Failed -gt 0) {
    'FAILED'
}
elseif ($Review -gt 0) {
    'REVIEW REQUIRED'
}
else {
    'VERIFIED'
}

# ----------------------------------------------------------
# 12. Export consolidated CSV report
# ----------------------------------------------------------

$Checks |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 13. Prepare GPO summary
# ----------------------------------------------------------

$GPOTable = $GPORecords |
    Select-Object `
        Name,
        GPOID,
        GPOStatus,
        LinkEnabled,
        TargetOU |
    Format-Table -AutoSize |
    Out-String -Width 240

$ChecksTable = $Checks |
    Format-Table `
        Area,
        Check,
        Expected,
        Actual,
        Status `
        -AutoSize |
    Out-String -Width 260

# ----------------------------------------------------------
# 14. Generate TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 8 - FINAL REPORT
============================================================

Date: $(Get-Date)

HOST
$HostName

DOMAIN
$DomainName

DOMAIN CONTROLLER
$DCName

WORKSTATION
$ClientName

PREVIOUS VERIFICATION REPORT
$Lab07FilePath

GPO SUMMARY
$GPOTable

VERIFICATION RESULTS

Total checks: $Total
PASS: $Passed
FAIL: $Failed
REVIEW: $Review
INFO: $Info

FINAL STATUS
$FinalStatus

NOTE
LAB08-07 results were imported from the latest CSV report.
Domain policy and GPO links were checked again on SEA-DC1.
The client-side results in this report are historical,
not a new gpresult execution.

============================================================
DETAILED CHECKS
============================================================

"@

($Header + $ChecksTable) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 15. Generate HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    background: #f5f9fb;
    color: #294554;
    line-height: 1.6;
}
h1, h2 {
    color: #146393;
}
table {
    border-collapse: collapse;
    width: 100%;
    background: #ffffff;
    margin-bottom: 24px;
}
th {
    background: #146393;
    color: #ffffff;
    padding: 10px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 9px;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
.summary {
    background: #ffffff;
    border: 1px solid #dce6eb;
    padding: 18px;
    margin-bottom: 24px;
}
</style>
"@

$SafeStatus = [System.Net.WebUtility]::HtmlEncode(
    $FinalStatus
)

$SafeSource = [System.Net.WebUtility]::HtmlEncode(
    $Lab07FilePath
)

$Intro = @"
<h1>LAB 8 - Final Report</h1>

<div class="summary">
<p><strong>Host:</strong> $HostName</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>Domain controller:</strong> $DCName</p>
<p><strong>Client:</strong> $ClientName</p>
<p><strong>Previous verification:</strong> $SafeSource</p>
<p><strong>Total checks:</strong> $Total</p>
<p><strong>PASS:</strong> $Passed</p>
<p><strong>FAIL:</strong> $Failed</p>
<p><strong>REVIEW:</strong> $Review</p>
<p><strong>Final status:</strong> $SafeStatus</p>
</div>

<h2>Consolidated verification</h2>
"@

$Checks |
    ConvertTo-Html `
        -Title 'LAB 8 - Final Report' `
        -Head $CSS `
        -PreContent $Intro |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 16. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - FINAL RESULTS"
Write-Host "=========================================="
Write-Host ""

Write-Host "Previous LAB08-07 report:"
Write-Host $Lab07FilePath
Write-Host ""

Write-Host "GPO SUMMARY"
$GPORecords |
    Format-Table `
        Name,
        GPOStatus,
        LinkEnabled `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red
Write-Host "REVIEW: $Review" -ForegroundColor Yellow

Write-Host ""
Write-Host "Final status: $FinalStatus"

Write-Host ""
Write-Host "Reports on $HostName :"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 17. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0) {
    throw (
        "LAB08-08 detected verification failures. " +
        "Review the detailed report."
    )
}

if ($Review -gt 0) {

    Write-Warning (
        "LAB08-08 completed with items requiring review. " +
        "Do not treat all tests as fully verified."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 8 - FINAL REPORT VERIFIED"
    Write-Host "==========================================" `
        -ForegroundColor Green
}
