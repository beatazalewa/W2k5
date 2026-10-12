
# ==========================================================
# LAB 5 - Script 02 - Create Organizational Units
# Run ONLY on Hyper-V host as Administrator
# Target: SEA-DC1
# Domain: contoso.com
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMName = 'SEA-DC1'
$ReportPath = 'C:\LabReports'

Import-Module Hyper-V -ErrorAction Stop

New-Item -Path $ReportPath -ItemType Directory -Force |
    Out-Null

$VM = Get-VM -Name $VMName -ErrorAction Stop

if ($VM.State -ne 'Running') {
    throw "$VMName is not running."
}

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message "Enter domain Administrator password for $VMName"

$Session = $null

try {

    $Session = New-PSSession `
        -VMName $VMName `
        -Credential $Credential `
        -ErrorAction Stop

    $Results = Invoke-Command `
        -Session $Session `
        -ScriptBlock {

            $ErrorActionPreference = 'Stop'
            Import-Module ActiveDirectory -ErrorAction Stop

            $Domain = Get-ADDomain -ErrorAction Stop

            if ($Domain.DNSRoot -ne 'contoso.com') {
                throw "Unexpected domain: $($Domain.DNSRoot)"
            }

            $DomainDN = $Domain.DistinguishedName

            # Define parent OU first
            $Structure = @(
                @{ Name='Centrala'; Parent=$DomainDN }
                @{ Name='IT'; Parent="OU=Centrala,$DomainDN" }
                @{ Name='Administracja'; Parent="OU=Centrala,$DomainDN" }
                @{ Name='Finanse'; Parent="OU=Centrala,$DomainDN" }
                @{ Name='HR'; Parent="OU=Centrala,$DomainDN" }
                @{ Name='Serwery'; Parent="OU=Centrala,$DomainDN" }
                @{ Name='Stacje robocze'; Parent="OU=Centrala,$DomainDN" }
                @{ Name='Konta administracyjne'; Parent="OU=Centrala,$DomainDN" }
            )

            # Add departmental child OUs
            foreach ($Department in @(
                'IT',
                'Administracja',
                'Finanse',
                'HR'
            )) {

                $ParentDN = "OU=$Department,OU=Centrala,$DomainDN"

                $Structure += @{
                    Name = 'Uzytkownicy'
                    Parent = $ParentDN
                }

                $Structure += @{
                    Name = 'Grupy'
                    Parent = $ParentDN
                }
            }

            foreach ($OU in $Structure) {

                $OUName = [string]$OU['Name']
                $OUParent = [string]$OU['Parent']
                $OUDN = "OU=$OUName,$OUParent"

                try {

                    # Search existing child OUs without -Identity
                    $Existing = @(
                        Get-ADOrganizationalUnit `
                            -LDAPFilter '(objectClass=organizationalUnit)' `
                            -SearchBase $OUParent `
                            -SearchScope OneLevel `
                            -Properties ProtectedFromAccidentalDeletion `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.Name -eq $OUName
                        }
                    )

                    if ($Existing.Count -gt 1) {
                        throw "Multiple matching OUs found: $OUDN"
                    }

                    if ($Existing.Count -eq 1) {

                        $Action = 'EXISTS'
                        $Protected = [bool](
                            $Existing[0].ProtectedFromAccidentalDeletion
                        )
                    }
                    else {

                        # Create a missing OU
                        $NewOU = New-ADOrganizationalUnit `
                            -Name $OUName `
                            -Path $OUParent `
                            -ProtectedFromAccidentalDeletion $true `
                            -PassThru `
                            -ErrorAction Stop

                        $Action = 'CREATED'
                        $Protected = $true
                    }

                    [PSCustomObject]@{
                        OUName = $OUName
                        DistinguishedName = $OUDN
                        Action = $Action
                        Protected = $Protected
                        Status = 'PASS'
                        Error = ''
                    }
                }
                catch {

                    [PSCustomObject]@{
                        OUName = $OUName
                        DistinguishedName = $OUDN
                        Action = 'ERROR'
                        Protected = $false
                        Status = 'FAIL'
                        Error = $_.Exception.Message
                    }
                }
            }
        } `
        -ErrorAction Stop

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 5 - OU CREATION REPORT"
    Write-Host "=========================================="

    $Results |
        Format-Table OUName, Action, Protected, Status -AutoSize |
        Out-Host

    $Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

    $ReportFile = Join-Path `
        $ReportPath `
        "LAB05-OU-Report_$Timestamp.csv"

    $Results |
        Export-Csv `
            -Path $ReportFile `
            -NoTypeInformation `
            -Encoding UTF8

    $Created = @($Results | Where-Object Action -eq 'CREATED').Count
    $Existing = @($Results | Where-Object Action -eq 'EXISTS').Count
    $Failed = @($Results | Where-Object Status -eq 'FAIL').Count

    Write-Host ""
    Write-Host "Created: $Created" -ForegroundColor Green
    Write-Host "Existing: $Existing" -ForegroundColor Cyan
    Write-Host "Failed: $Failed" -ForegroundColor Yellow
    Write-Host "Report: $ReportFile"

    if ($Failed -eq 0 -and $Results.Count -eq 16) {
        Write-Host "LAB 5 - OU CREATION PASSED" `
            -ForegroundColor Green
    }
    else {
        Write-Warning "Some organizational units require attention."
    }
}
finally {

    if ($null -ne $Session) {
        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}
