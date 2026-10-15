# ==========================================================
# LAB 9 - Script 01 - Environment PreCheck
#
# Run on Hyper-V host as Administrator.
# Windows PowerShell 5.1.
#
# This script does not change Active Directory or GPOs.
# ==========================================================

$ErrorActionPreference = 'Stop'

$HostName = $env:COMPUTERNAME
$DCName = 'SEA-DC1'
$DomainName = 'contoso.com'
$ReportDir = 'C:\LabReports'
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $ReportDir "LAB09-PreCheck_$Timestamp.csv"
$TXT = Join-Path $ReportDir "LAB09-PreCheck_$Timestamp.txt"

$VMNames = @(
    'SEA-DC1'
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

$Checks = @()

function Add-Check {
    param(
        [string]$Computer,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [string]$Status
    )

    $script:Checks += [PSCustomObject]@{
        Computer = $Computer
        Check = $Check
        Expected = $Expected
        Actual = $Actual
        Status = $Status
    }
}

# ----------------------------------------------------------
# 1. Verify administrator privileges
# ----------------------------------------------------------

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw 'Run PowerShell as Administrator.'
}

Import-Module Hyper-V -ErrorAction Stop

New-Item -Path $ReportDir -ItemType Directory -Force |
    Out-Null

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 9 - ENVIRONMENT PRECHECK"
Write-Host "=========================================="
Write-Host ""
Write-Host "Host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host ""

# ----------------------------------------------------------
# 2. Verify virtual machines
# ----------------------------------------------------------

foreach ($Name in $VMNames) {

    $VM = Get-VM -Name $Name -ErrorAction SilentlyContinue

    if ($null -eq $VM) {
        Add-Check $Name 'VM running' 'Running' 'Not found' 'FAIL'
        continue
    }

    $Status = if ($VM.State -eq 'Running') {
        'PASS'
    }
    else {
        'FAIL'
    }

    Add-Check $Name 'VM running' 'Running' `
        ([string]$VM.State) $Status
}

# ----------------------------------------------------------
# 3. Connect to domain controller
# ----------------------------------------------------------

$CredentialOptions = @{
    UserName = 'CONTOSO\Administrator'
    Message = 'Enter domain Administrator password'
}

$Credential = Get-Credential @CredentialOptions

$Session = $null

try {

    $Session = New-PSSession -VMName $DCName `
        -Credential $Credential -ErrorAction Stop

    $Data = @(
        Invoke-Command -Session $Session -ScriptBlock {

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory
            Import-Module GroupPolicy

            $Domain = Get-ADDomain

            [PSCustomObject]@{
                Type = 'DOMAIN'
                Name = $Domain.DNSRoot
                Detail = $Domain.DistinguishedName
            }

            $OUs = @(
                'OU=Uzytkownicy,OU=Finanse,OU=Centrala,DC=contoso,DC=com'
                'OU=Konta administracyjne,OU=Centrala,DC=contoso,DC=com'
                'OU=Stacje robocze,OU=Centrala,DC=contoso,DC=com'
                'OU=Serwery,OU=Centrala,DC=contoso,DC=com'
                'OU=Domain Controllers,DC=contoso,DC=com'
            )

            foreach ($Path in $OUs) {

                $Exists = $false

                try {
                    $null = Get-ADOrganizationalUnit `
                        -Identity $Path -ErrorAction Stop

                    $Exists = $true
                }
                catch {
                    $Exists = $false
                }

                [PSCustomObject]@{
                    Type = 'OU'
                    Name = $Path
                    Detail = [string]$Exists
                }
            }

            $GPOs = @(
                Get-GPO -All -Domain $Domain.DNSRoot
            )

            foreach ($GPO in $GPOs) {
                [PSCustomObject]@{
                    Type = 'GPO'
                    Name = $GPO.DisplayName
                    Detail = [string]$GPO.GpoStatus
                }
            }

            foreach ($Computer in @(
                'SEA-DC1',
                'SEA-SRV1',
                'SEA-SRV2',
                'SEA-CL1'
            )) {

                $ADComputer = Get-ADComputer `
                    -Identity $Computer `
                    -ErrorAction Stop

                [PSCustomObject]@{
                    Type = 'COMPUTER'
                    Name = $Computer
                    Detail = $ADComputer.DistinguishedName
                }
            }

            $AdminOU = (
                'OU=Konta administracyjne,' +
                'OU=Centrala,DC=contoso,DC=com'
            )

            $AdminUsers = @(
                Get-ADUser `
                    -Filter * `
                    -SearchBase $AdminOU `
                    -SearchScope OneLevel
            )

            [PSCustomObject]@{
                Type = 'ADMIN_USERS'
                Name = 'Administrative test accounts'
                Detail = [string]$AdminUsers.Count
            }

        } -ErrorAction Stop
    )

}
finally {
    if ($null -ne $Session) {
        Remove-PSSession $Session
    }
}

# ----------------------------------------------------------
# 4. Verify domain
# ----------------------------------------------------------

$Domain = @($Data | Where-Object Type -eq 'DOMAIN')

if ($Domain.Count -ne 1 -or $Domain[0].Name -ne $DomainName) {
    Add-Check $DCName 'Domain name' $DomainName `
        'Unexpected or missing' 'FAIL'
}
else {
    Add-Check $DCName 'Domain name' $DomainName `
        $Domain[0].Name 'PASS'
}

# ----------------------------------------------------------
# 5. Verify organizational units
# ----------------------------------------------------------

foreach ($Item in @($Data | Where-Object Type -eq 'OU')) {

    $Status = if ($Item.Detail -eq 'True') {
        'PASS'
    }
    else {
        'FAIL'
    }

    Add-Check $DCName "OU: $($Item.Name)" 'True' `
        $Item.Detail $Status
}

# ----------------------------------------------------------
# 6. Display existing GPOs
# ----------------------------------------------------------

Write-Host ""
Write-Host "EXISTING GROUP POLICIES"
Write-Host ""

$Data |
    Where-Object Type -eq 'GPO' |
    Select-Object Name, Detail |
    Format-Table -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 7. Verify computer location information
# ----------------------------------------------------------

foreach ($Item in @($Data | Where-Object Type -eq 'COMPUTER')) {

    Add-Check $DCName "AD computer: $($Item.Name)" `
        'Account exists' $Item.Detail 'PASS'
}

# ----------------------------------------------------------
# 8. Check administrative account availability
# ----------------------------------------------------------

$AdminInfo = @(
    $Data | Where-Object Type -eq 'ADMIN_USERS'
)

$AdminCount = if ($AdminInfo.Count -eq 1) {
    [int]$AdminInfo[0].Detail
}
else {
    0
}

Add-Check $DCName 'Administrative test accounts in OU' `
    'At least one for user-side testing' `
    ([string]$AdminCount) `
    $(if ($AdminCount -gt 0) { 'PASS' } else { 'REVIEW' })

# ----------------------------------------------------------
# 9. Export reports
# ----------------------------------------------------------

$Checks |
    Export-Csv -Path $CSV -NoTypeInformation -Encoding UTF8

$Passed = @($Checks | Where-Object Status -eq 'PASS').Count
$Failed = @($Checks | Where-Object Status -eq 'FAIL').Count
$Review = @($Checks | Where-Object Status -eq 'REVIEW').Count

$Report = @"
LAB 9 - ENVIRONMENT PRECHECK

Host: $HostName
Domain: $DomainName
Date: $(Get-Date)

PASS: $Passed
FAIL: $Failed
REVIEW: $Review

$($Checks | Format-Table -AutoSize | Out-String -Width 240)
"@

$Report | Out-File -FilePath $TXT -Encoding UTF8

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 9 - PRECHECK RESULTS"
Write-Host "=========================================="
Write-Host ""

$Checks | Format-Table -AutoSize | Out-Host

Write-Host "PASS: $Passed"
Write-Host "FAIL: $Failed"
Write-Host "REVIEW: $Review"

Write-Host ""
Write-Host "CSV: $CSV"
Write-Host "TXT: $TXT"

if ($Failed -gt 0) {
    throw 'LAB09-01 precheck failed.'
}

Write-Host "LAB09-01 PRECHECK COMPLETED" -ForegroundColor Green
