# ==========================================================
# LAB 5 - Script 06 - Verify AD Organizational Structure
# Run on Hyper-V host as Administrator
# Reports: CSV, TXT, HTML
# ==========================================================

$ErrorActionPreference = 'Stop'
Import-Module Hyper-V -ErrorAction Stop

$ReportPath = 'C:\LabReports'
New-Item -ItemType Directory -Path $ReportPath -Force |
    Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $ReportPath "LAB05-Verification_$Timestamp.csv"
$TXT = Join-Path $ReportPath "LAB05-Verification_$Timestamp.txt"
$HTML = Join-Path $ReportPath "LAB05-Verification_$Timestamp.html"

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

$Session = $null

try {
    $Session = New-PSSession `
        -VMName 'SEA-DC1' `
        -Credential $Credential `
        -ErrorAction Stop

    $Results = Invoke-Command -Session $Session -ScriptBlock {

        $ErrorActionPreference = 'Stop'
        Import-Module ActiveDirectory

        $DomainDN = (Get-ADDomain).DistinguishedName
        $Results = [System.Collections.Generic.List[object]]::new()

        function Add-Result {
            param($Type,$Name,$Expected,$Actual,$Pass)

            $Results.Add([PSCustomObject]@{
                Type = $Type
                Name = $Name
                Expected = [string]$Expected
                Actual = [string]$Actual
                Status = if ($Pass) { 'PASS' } else { 'FAIL' }
            })
        }

        # Verify organizational units
        $OUs = @(
            "OU=Centrala,$DomainDN"
            "OU=IT,OU=Centrala,$DomainDN"
            "OU=Administracja,OU=Centrala,$DomainDN"
            "OU=Finanse,OU=Centrala,$DomainDN"
            "OU=HR,OU=Centrala,$DomainDN"
            "OU=Serwery,OU=Centrala,$DomainDN"
            "OU=Stacje robocze,OU=Centrala,$DomainDN"
            "OU=Konta administracyjne,OU=Centrala,$DomainDN"
        )

        foreach ($Department in @('IT','Administracja','Finanse','HR')) {
            foreach ($Child in @('Uzytkownicy','Grupy')) {
                $OUs += "OU=$Child,OU=$Department,OU=Centrala,$DomainDN"
            }
        }

        foreach ($DN in $OUs) {
            $OU = Get-ADOrganizationalUnit `
                -Identity $DN `
                -ErrorAction SilentlyContinue

            Add-Result 'OU' $DN 'Exists' `
                $(if ($OU) { 'Exists' } else { 'Missing' }) `
                ($null -ne $OU)
        }

        # Verify users
        $Users = @(
            'anna.kowalska','piotr.nowak',
            'marta.wisniewska','tomasz.zielinski',
            'ewa.kaczmarek','adam.lewandowski',
            'karolina.wojcik','michal.kaminski',
            'adm.lab'
        )

        foreach ($Login in $Users) {

            $User = Get-ADUser `
                -Filter "SamAccountName -eq '$Login'" `
                -ErrorAction Stop

            $UserOK = (
                $null -ne $User -and
                $User.Enabled
            )

            Add-Result 'User' $Login 'Enabled' `
                $(if ($User) {
                    if ($User.Enabled) { 'Enabled' }
                    else { 'Disabled' }
                } else { 'Missing' }) `
                $UserOK
        }

        # Verify security groups and memberships
        $Memberships = [ordered]@{
            'GG_IT_Users' = @('anna.kowalska','piotr.nowak')
            'GG_IT_Admins' = @('adm.lab')
            'GG_Admin_Users' = @('marta.wisniewska','tomasz.zielinski')
            'GG_Finance_Users' = @('ewa.kaczmarek','adam.lewandowski')
            'GG_HR_Users' = @('karolina.wojcik','michal.kaminski')
            'DL_IT_Read' = @('GG_IT_Users')
            'DL_Admin_Read' = @('GG_Admin_Users')
            'DL_Finance_RW' = @('GG_Finance_Users')
            'DL_HR_Read' = @('GG_HR_Users')
        }

        foreach ($GroupName in $Memberships.Keys) {

            $Group = Get-ADGroup `
                -Identity $GroupName `
                -ErrorAction SilentlyContinue

            Add-Result 'Group' $GroupName 'Exists' `
                $(if ($Group) { 'Exists' } else { 'Missing' }) `
                ($null -ne $Group)

            if (-not $Group) {
                foreach ($MemberName in $Memberships[$GroupName]) {
                    Add-Result 'Membership' `
                        "$GroupName <- $MemberName" `
                        'Member' 'Group missing' $false
                }
                continue
            }

            $Members = @(
                Get-ADGroupMember -Identity $Group |
                Select-Object -ExpandProperty SamAccountName
            )

            foreach ($MemberName in $Memberships[$GroupName]) {

                $MemberOK = ($MemberName -in $Members)

                Add-Result 'Membership' `
                    "$GroupName <- $MemberName" `
                    'Member' `
                    $(if ($MemberOK) { 'Member' } else { 'Missing' }) `
                    $MemberOK
            }
        }

        $Results
    } -ErrorAction Stop

    # Export structured data
    $Results |
        Export-Csv -Path $CSV -NoTypeInformation -Encoding UTF8

    $Results |
        Format-List |
        Out-String -Width 200 |
        Out-File -FilePath $TXT -Encoding UTF8

    $Style = @"
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    background: #f5f9fb;
    color: #294554;
}
h1 { color: #146393; }
table {
    border-collapse: collapse;
    width: 100%;
    background: white;
}
th {
    background: #146393;
    color: white;
    padding: 9px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 8px;
}
</style>
"@

    ConvertTo-Html `
        -Title 'LAB 5 - AD Verification' `
        -Head $Style `
        -Body (
            '<h1>LAB 5 - AD Structure Verification</h1>' +
            "<p>Date: $(Get-Date)</p>" +
            ($Results | ConvertTo-Html -Fragment | Out-String)
        ) |
        Out-File -FilePath $HTML -Encoding UTF8

    $Passed = @($Results | Where-Object Status -eq 'PASS').Count
    $Failed = @($Results | Where-Object Status -eq 'FAIL').Count

    Write-Host "`nLAB 5 - VERIFICATION REPORT" -ForegroundColor Cyan

    $Results |
        Format-Table Type, Name, Status -AutoSize |
        Out-Host

    Write-Host "Passed: $Passed" -ForegroundColor Green
    Write-Host "Failed: $Failed" -ForegroundColor Yellow

    Write-Host "CSV: $CSV"
    Write-Host "TXT: $TXT"
    Write-Host "HTML: $HTML"

    if ($Failed -eq 0) {
        Write-Host 'LAB 5 - VERIFICATION PASSED' `
            -ForegroundColor Green
    }
    else {
        Write-Warning 'LAB 5 - Some checks failed.'
    }
}
finally {
    if ($Session) {
        Remove-PSSession $Session
    }
}