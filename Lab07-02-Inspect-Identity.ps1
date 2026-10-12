# ==========================================================
# LAB 7 - Script 02 - Inspect Windows and AD Identity
#
# Run ONLY on host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
#
# Virtual machines:
#   SEA-DC1
#   SEA-SRV1
#   SEA-SRV2
#   SEA-CL1
#
# Test users:
#   anna.kowalska
#   ewa.kaczmarek
#
# Inspects:
#   whoami
#   whoami /user
#   whoami /groups
#   whoami /priv
#   Windows security identity
#   Active Directory user SID and group membership
#
# Reports: CSV, TXT, HTML
# This script is read-only.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$ReportDir = 'C:\LabReports'

$VMNames = @(
    'SEA-DC1'
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

$TestUsers = @(
    [PSCustomObject]@{
        Login = 'anna.kowalska'
        Group = 'GG_IT_Users'
    }
    [PSCustomObject]@{
        Login = 'ewa.kaczmarek'
        Group = 'GG_Finance_Users'
    }
)

# ----------------------------------------------------------
# 2. Initialize host environment
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $ReportDir `
    "LAB07-Identity_$Timestamp.csv"

$TXT = Join-Path $ReportDir `
    "LAB07-Identity_$Timestamp.txt"

$HTML = Join-Path $ReportDir `
    "LAB07-Identity_$Timestamp.html"

$Results = [System.Collections.Generic.List[object]]::new()
$Details = [System.Collections.Generic.List[string]]::new()

# ----------------------------------------------------------
# 3. Helper function
# ----------------------------------------------------------

function Add-LabCheck {

    param(
        [string]$Machine,
        [string]$Category,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [bool]$Passed
    )

    $Results.Add(
        [PSCustomObject]@{
            Machine  = $Machine
            Category = $Category
            Check    = $Check
            Expected = $Expected
            Actual   = $Actual
            Status   = if ($Passed) { 'PASS' } else { 'FAIL' }
        }
    )
}

# ----------------------------------------------------------
# 4. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - WINDOWS IDENTITY INSPECTION"
Write-Host "=========================================="
Write-Host ""
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Domain: $DomainName"
Write-Host "VM count: $($VMNames.Count)"
Write-Host "AD users: $($TestUsers.Count)"
Write-Host ""

# ----------------------------------------------------------
# 5. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {
    throw 'Domain credentials were not provided.'
}

# ----------------------------------------------------------
# 6. Inspect the administrative identity on each VM
# ----------------------------------------------------------

foreach ($VMName in $VMNames) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Inspecting identity on $VMName"
    Write-Host "------------------------------------------"

    $Session = $null

    try {

        $VM = Get-VM `
            -Name $VMName `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "Virtual machine $VMName is not running."
        }

        # Connect using PowerShell Direct
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Run identity inspection inside the guest
        $Data = Invoke-Command `
            -Session $Session `
            -ScriptBlock {

                $ErrorActionPreference = 'Stop'

                # Read identity from the current session
                $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

                $Principal = New-Object `
                    System.Security.Principal.WindowsPrincipal(
                        $Identity
                    )

                # Inspect token information
                $IdentityName = [string]$Identity.Name
                $IdentitySID = [string]$Identity.User.Value

                $IsAdmin = $Principal.IsInRole(
                    [System.Security.Principal.WindowsBuiltInRole]::Administrator
                )

                # Execute Windows identity commands
                $WhoAmI = (
                    & whoami.exe 2>&1 | Out-String
                ).Trim()

                $WhoAmIUser = (
                    & whoami.exe /user 2>&1 | Out-String
                ).Trim()

                $WhoAmIGroups = (
                    & whoami.exe /groups 2>&1 | Out-String
                ).Trim()

                $WhoAmIPrivileges = (
                    & whoami.exe /priv 2>&1 | Out-String
                ).Trim()

                $Computer = Get-CimInstance `
                    -ClassName Win32_ComputerSystem `
                    -ErrorAction Stop

                # Return collected data
                [PSCustomObject]@{
                    Computer = [string]$env:COMPUTERNAME
                    Identity = $IdentityName
                    SID = $IdentitySID
                    AuthType = [string]$Identity.AuthenticationType
                    IsAuthenticated = [bool]$Identity.IsAuthenticated
                    IsAdministrator = [bool]$IsAdmin
                    Domain = [string]$Computer.Domain
                    DomainMember = [bool]$Computer.PartOfDomain
                    WhoAmI = $WhoAmI
                    WhoAmIUser = $WhoAmIUser
                    WhoAmIGroups = $WhoAmIGroups
                    WhoAmIPrivileges = $WhoAmIPrivileges
                }

            } `
            -ErrorAction Stop

        # Check current Windows identity
        $IdentityOK = (
            $Data.Identity -ieq 'CONTOSO\Administrator'
        )

        Add-LabCheck `
            $VMName `
            'Identity' `
            'Administrative session account' `
            'CONTOSO\Administrator' `
            $Data.Identity `
            $IdentityOK

        # Check Windows SID
        $SIDOK = (
            $Data.SID -match '^S-1-5-21-\d+-\d+-\d+-\d+$'
        )

        Add-LabCheck `
            $VMName `
            'Identity' `
            'Windows user SID' `
            'Domain account SID' `
            $Data.SID `
            $SIDOK

        # Check domain membership
        $DomainOK = (
            $Data.DomainMember -and
            $Data.Domain -ieq $DomainName
        )

        Add-LabCheck `
            $VMName `
            'Domain' `
            'Domain membership' `
            $DomainName `
            $Data.Domain `
            $DomainOK

        # Check authentication
        Add-LabCheck `
            $VMName `
            'Identity' `
            'Authenticated identity' `
            'True' `
            ([string]$Data.IsAuthenticated) `
            ([bool]$Data.IsAuthenticated)

        # Check whoami output
        Add-LabCheck `
            $VMName `
            'WhoAmI' `
            'whoami identity matches Windows identity' `
            $Data.Identity `
            $Data.WhoAmI `
            ($Data.WhoAmI -ieq $Data.Identity)

        # Check administrative token
        Add-LabCheck `
            $VMName `
            'Token' `
            'Administrative token' `
            'True' `
            ([string]$Data.IsAdministrator) `
            ([bool]$Data.IsAdministrator)

        # Collect detailed token output
        $Detail = @"

============================================================
VM: $VMName
============================================================

Identity:
$($Data.Identity)

SID:
$($Data.SID)

Authentication type:
$($Data.AuthType)

Administrator token:
$($Data.IsAdministrator)

------------------------------------------------------------
WHOAMI /USER
------------------------------------------------------------

$($Data.WhoAmIUser)

------------------------------------------------------------
WHOAMI /GROUPS
------------------------------------------------------------

$($Data.WhoAmIGroups)

------------------------------------------------------------
WHOAMI /PRIV
------------------------------------------------------------

$($Data.WhoAmIPrivileges)

"@

        $Details.Add($Detail)

        Write-Host "Identity: $($Data.Identity)"
        Write-Host "SID: $($Data.SID)"
        Write-Host "Administrator token: $($Data.IsAdministrator)"
        Write-Host "Inspection completed." -ForegroundColor Green

    }
    catch {

        $Message = $_.Exception.Message

        Add-LabCheck `
            $VMName `
            'Connection' `
            'PowerShell Direct identity inspection' `
            'Completed' `
            $Message `
            $false

        Write-Warning "Inspection failed on ${VMName}: $Message"
    }
    finally {

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 7. Inspect user accounts in Active Directory
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - ACTIVE DIRECTORY USER INSPECTION"
Write-Host "=========================================="

$Session = $null

try {

    $Session = New-PSSession `
        -VMName 'SEA-DC1' `
        -Credential $Credential `
        -ErrorAction Stop

    $ADUsers = Invoke-Command `
        -Session $Session `
        -ArgumentList (,$TestUsers) `
        -ScriptBlock {

            param(
                [object[]]$TestUsers
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            $Domain = Get-ADDomain -ErrorAction Stop

            if ($Domain.DNSRoot -ne 'contoso.com') {
                throw "Unexpected domain: $($Domain.DNSRoot)"
            }

            foreach ($Target in $TestUsers) {

                try {

                    $Login = [string]$Target.Login

                    $User = Get-ADUser `
                        -Identity $Login `
                        -Properties `
                            Enabled,
                            UserPrincipalName,
                            Department,
                            LockedOut `
                        -ErrorAction Stop

                    $Groups = @(
                        Get-ADPrincipalGroupMembership `
                            -Identity $User `
                            -ErrorAction Stop |
                        Select-Object -ExpandProperty Name
                    )

                    [PSCustomObject]@{
                        Login = $Login
                        Name = [string]$User.Name
                        SID = [string]$User.SID.Value
                        UPN = [string]$User.UserPrincipalName
                        Department = [string]$User.Department
                        Enabled = [bool]$User.Enabled
                        LockedOut = [bool]$User.LockedOut
                        ExpectedGroup = [string]$Target.Group
                        Groups = ($Groups -join ', ')
                        ExpectedGroupOK = [bool](
                            $Target.Group -in $Groups
                        )
                        Error = ''
                    }

                }
                catch {

                    [PSCustomObject]@{
                        Login = [string]$Target.Login
                        Name = ''
                        SID = ''
                        UPN = ''
                        Department = ''
                        Enabled = $false
                        LockedOut = $false
                        ExpectedGroup = [string]$Target.Group
                        Groups = ''
                        ExpectedGroupOK = $false
                        Error = $_.Exception.Message
                    }
                }
            }

        } `
        -ErrorAction Stop

    foreach ($User in $ADUsers) {

        $Exists = (
            [string]::IsNullOrWhiteSpace($User.Error) -and
            -not [string]::IsNullOrWhiteSpace($User.SID)
        )

        Add-LabCheck `
            'SEA-DC1' `
            'AD User' `
            "Account exists: $($User.Login)" `
            'True' `
            ([string]$Exists) `
            $Exists

        Add-LabCheck `
            'SEA-DC1' `
            'AD User' `
            "Account enabled: $($User.Login)" `
            'True' `
            ([string]$User.Enabled) `
            ([bool]$User.Enabled)

        Add-LabCheck `
            'SEA-DC1' `
            'AD User' `
            "Account unlocked: $($User.Login)" `
            'True' `
            ([string](-not $User.LockedOut)) `
            ($Exists -and -not $User.LockedOut)

        Add-LabCheck `
            'SEA-DC1' `
            'AD Group' `
            "Group membership: $($User.Login)" `
            $User.ExpectedGroup `
            $User.Groups `
            ([bool]$User.ExpectedGroupOK)

        # Save Active Directory details
        $UserDetail = @"

============================================================
ACTIVE DIRECTORY USER: $($User.Login)
============================================================

Name: $($User.Name)
SID: $($User.SID)
UPN: $($User.UPN)
Department: $($User.Department)
Enabled: $($User.Enabled)
Locked out: $($User.LockedOut)

Expected group:
$($User.ExpectedGroup)

Group membership:
$($User.Groups)

Error:
$($User.Error)

"@

        $Details.Add($UserDetail)
    }

    Write-Host ""
    Write-Host "ACTIVE DIRECTORY USERS"
    Write-Host ""

    $ADUsers |
        Select-Object `
            Login,
            SID,
            Enabled,
            LockedOut,
            ExpectedGroupOK |
        Format-Table -AutoSize |
        Out-Host

}
catch {

    Add-LabCheck `
        'SEA-DC1' `
        'AD User' `
        'Active Directory inspection' `
        'Completed' `
        $_.Exception.Message `
        $false
}
finally {

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------
# 8. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $Results | Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Results | Where-Object Status -eq 'FAIL'
).Count

$Total = $Results.Count

$ExpectedCount = (
    ($VMNames.Count * 6) +
    ($TestUsers.Count * 4)
)

# Expected: 24 guest checks + 8 AD checks = 32

# ----------------------------------------------------------
# 9. Export CSV report
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 10. Export TXT report
# ----------------------------------------------------------

$Header = @"
LAB 7 - IDENTITY INSPECTION REPORT

Host: $env:COMPUTERNAME
Domain: $DomainName
Date: $(Get-Date)

Total: $Total
Expected: $ExpectedCount
Passed: $Passed
Failed: $Failed

NOTE:
The WHOAMI output represents the PowerShell Direct
administrative session, not the interactive desktop user.

"@

$Summary = $Results |
    Format-Table `
        Machine, Category, Check, Status `
        -AutoSize |
    Out-String -Width 220

$DetailedText = $Details -join "`r`n"

($Header + $Summary + "`r`n" + $DetailedText) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 11. Export HTML report
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
    background: #ffffff;
    border: 1px solid #dce6eb;
    padding: 16px;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
}
</style>
"@

$HTMLHeader = @"
<h1>LAB 7 - Identity Inspection</h1>
<p>Domain: $DomainName</p>
<p>Passed: $Passed | Failed: $Failed</p>
<p>
WHOAMI output represents the PowerShell Direct
administrative session.
</p>
"@

$SummaryHTML = $Results |
    ConvertTo-Html -Fragment |
    Out-String

# Encode the detailed text to prevent HTML injection
$EncodedDetails = [System.Net.WebUtility]::HtmlEncode(
    $DetailedText
)

$HTMLBody = @"
$HTMLHeader
$SummaryHTML
<h2>Detailed identity and token information</h2>
<pre>$EncodedDetails</pre>
"@

ConvertTo-Html `
    -Title 'LAB 7 - Identity Inspection' `
    -Head $CSS `
    -Body $HTMLBody |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 12. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - IDENTITY INSPECTION REPORT"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table `
        Machine,
        Category,
        Check,
        Status `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "Expected: $ExpectedCount"
Write-Host "Passed: $Passed" -ForegroundColor Green
Write-Host "Failed: $Failed" -ForegroundColor Yellow

Write-Host ""
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 13. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0 -or $Total -ne $ExpectedCount) {

    Write-Warning (
        "Identity inspection reported failures or " +
        "an unexpected check count."
    )

}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 7 - IDENTITY INSPECTION PASSED"
    Write-Host "=========================================="
}

