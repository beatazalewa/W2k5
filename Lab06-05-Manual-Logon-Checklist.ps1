# ==========================================================
# LAB 6 - Script 05 - Manual Domain Logon Checklist
#
# Run on host in elevated Windows PowerShell 5.1.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# Client: SEA-CL1
#
# Test accounts:
#   CONTOSO\anna.kowalska
#   CONTOSO\ewa.kaczmarek
#
# Interactive logon must be performed in VMConnect.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 2. Configuration
# ----------------------------------------------------------

$VMName = 'SEA-CL1'
$DomainName = 'contoso.com'
$ReportDir = 'C:\LabReports'

$TestUsers = @(
    [PSCustomObject]@{
        User = 'CONTOSO\anna.kowalska'
        Group = 'GG_IT_Users'
    }

    [PSCustomObject]@{
        User = 'CONTOSO\ewa.kaczmarek'
        Group = 'GG_Finance_Users'
    }
)

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path `
    $ReportDir `
    "LAB06-Manual-Logon_$Timestamp.csv"

$TXT = Join-Path `
    $ReportDir `
    "LAB06-Manual-Logon_$Timestamp.txt"

# ----------------------------------------------------------
# 3. Verify client virtual machine
# ----------------------------------------------------------

$VM = Get-VM `
    -Name $VMName `
    -ErrorAction Stop

if ([string]$VM.State -ne 'Running') {
    throw "Virtual machine $VMName is not running."
}

# ----------------------------------------------------------
# 4. Display laboratory instructions
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - MANUAL DOMAIN LOGON TEST"
Write-Host "=========================================="
Write-Host ""

Write-Host "Domain: $DomainName"
Write-Host "Client: $VMName"
Write-Host ""

Write-Host "Open the virtual machine console:" `
    -ForegroundColor Cyan

Write-Host "1. Open Hyper-V Manager."
Write-Host "2. Connect to SEA-CL1."
Write-Host "3. Sign out the current user."
Write-Host "4. Select Other user."
Write-Host "5. Sign in using the test domain account."
Write-Host ""

Write-Host "Run the following commands in the" `
    "signed-in user's PowerShell session:" `
    -ForegroundColor Cyan

Write-Host ""

Write-Host 'whoami'
Write-Host 'whoami /groups'
Write-Host '$env:USERDNSDOMAIN'
Write-Host 'nltest /dsgetdc:contoso.com'
Write-Host 'klist'
Write-Host ""

# ----------------------------------------------------------
# 5. Initialize results
# ----------------------------------------------------------

$Results = @()

# ----------------------------------------------------------
# 6. Process test accounts
# ----------------------------------------------------------

foreach ($TestUser in $TestUsers) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "TEST ACCOUNT: $($TestUser.User)"
    Write-Host "EXPECTED GROUP: $($TestUser.Group)"
    Write-Host "------------------------------------------"

    Write-Host ""
    Write-Host "Sign in interactively on SEA-CL1."
    Write-Host "Verify the account and domain membership."
    Write-Host ""

    # ------------------------------------------------------
    # 7. Confirm interactive logon
    # ------------------------------------------------------

    $LoginAnswer = Read-Host `
        "Was logon successful? (Y/N)"

    $LoginOK = (
        $LoginAnswer.Trim() -ieq 'Y'
    )

    # ------------------------------------------------------
    # 8. Confirm identity
    # ------------------------------------------------------

    $IdentityAnswer = Read-Host `
        "Does whoami show $($TestUser.User)? (Y/N)"

    $IdentityOK = (
        $IdentityAnswer.Trim() -ieq 'Y'
    )

    # ------------------------------------------------------
    # 9. Confirm group membership
    # ------------------------------------------------------

    $GroupAnswer = Read-Host `
        "Is $($TestUser.Group) present in whoami /groups? (Y/N)"

    $GroupOK = (
        $GroupAnswer.Trim() -ieq 'Y'
    )

    # ------------------------------------------------------
    # 10. Confirm domain controller discovery
    # ------------------------------------------------------

    $DCAnswer = Read-Host `
        "Does nltest find a domain controller? (Y/N)"

    $DCOK = (
        $DCAnswer.Trim() -ieq 'Y'
    )

    # ------------------------------------------------------
    # 11. Confirm Kerberos tickets
    # ------------------------------------------------------

    $KerberosAnswer = Read-Host `
        "Does klist show a valid Kerberos ticket? (Y/N)"

    $KerberosOK = (
        $KerberosAnswer.Trim() -ieq 'Y'
    )

    # ------------------------------------------------------
    # 12. Calculate final result for account
    # ------------------------------------------------------

    $Passed = (
        $LoginOK -and
        $IdentityOK -and
        $GroupOK -and
        $DCOK -and
        $KerberosOK
    )

    # ------------------------------------------------------
    # 13. Collect results
    # ------------------------------------------------------

    $Results += [PSCustomObject]@{
        User = $TestUser.User
        ExpectedGroup = $TestUser.Group
        Logon = $LoginOK
        Identity = $IdentityOK
        GroupMembership = $GroupOK
        DomainController = $DCOK
        Kerberos = $KerberosOK
        Status = if ($Passed) { 'PASS' } else { 'FAIL' }
    }

    Write-Host ""
    Write-Host "Sign out before testing the next user." `
        -ForegroundColor Yellow

}

# ----------------------------------------------------------
# 14. Display results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - MANUAL LOGON RESULTS"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table `
        User,
        ExpectedGroup,
        Logon,
        Identity,
        GroupMembership,
        DomainController,
        Kerberos,
        Status `
        -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 15. Export CSV
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 16. Export TXT
# ----------------------------------------------------------

$PassedCount = @(
    $Results |
    Where-Object {
        $_.Status -eq 'PASS'
    }
).Count

$FailedCount = @(
    $Results |
    Where-Object {
        $_.Status -eq 'FAIL'
    }
).Count

$Header = @"
LAB 6 - MANUAL DOMAIN LOGON REPORT

Domain: $DomainName
Client: $VMName
Date: $(Get-Date)

Passed: $PassedCount
Failed: $FailedCount

"@

$Table = $Results |
    Format-Table -AutoSize |
    Out-String -Width 220

($Header + $Table) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 17. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - FINAL MANUAL LOGON REPORT"
Write-Host "=========================================="
Write-Host ""

Write-Host "Passed: $PassedCount" -ForegroundColor Green
Write-Host "Failed: $FailedCount" -ForegroundColor Yellow

Write-Host ""
Write-Host "Reports exported:"
Write-Host "CSV: $CSV"
Write-Host "TXT: $TXT"

# ----------------------------------------------------------
# 18. Final validation
# ----------------------------------------------------------

if ($FailedCount -gt 0) {

    Write-Warning (
        "Some manual logon tests failed. " +
        "Review the report before completing LAB 6."
    )

}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 6 - MANUAL LOGON TEST PASSED"
    Write-Host "=========================================="
   }
