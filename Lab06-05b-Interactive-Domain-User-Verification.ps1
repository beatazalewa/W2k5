# ==========================================================
# LAB 6 - Interactive Domain User Verification
# Run in the signed-in user's PowerShell session.
# Do not run as another administrator.
# ==========================================================

$ExpectedDomain = 'contoso.com'
$ExpectedDC = '10.10.10.10'

$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Computer = Get-CimInstance Win32_ComputerSystem

$Checks = @()

$Checks += [PSCustomObject]@{
    Check = 'Domain computer'
    Result = [bool](
        $Computer.PartOfDomain -and
        $Computer.Domain -ieq $ExpectedDomain
    )
}

$Checks += [PSCustomObject]@{
    Check = 'Domain user identity'
    Result = [bool](
        $Identity.Name -like 'CONTOSO\*' -and
        $Identity.Name -notlike '*\Administrator'
    )
}

$Checks += [PSCustomObject]@{
    Check = 'Domain controller DNS'
    Result = [bool](@(
        Resolve-DnsName SEA-DC1.contoso.com `
            -Type A `
            -Server $ExpectedDC `
            -ErrorAction SilentlyContinue |
        Where-Object IPAddress -eq $ExpectedDC
    ).Count -gt 0)
}

$Checks += [PSCustomObject]@{
    Check = 'Kerberos TCP 88'
    Result = [bool](
        Test-NetConnection $ExpectedDC -Port 88 `
            -InformationLevel Quiet
    )
}

$Checks += [PSCustomObject]@{
    Check = 'LDAP TCP 389'
    Result = [bool](
        Test-NetConnection $ExpectedDC -Port 389 `
            -InformationLevel Quiet
    )
}

$Checks += [PSCustomObject]@{
    Check = 'SMB TCP 445'
    Result = [bool](
        Test-NetConnection $ExpectedDC -Port 445 `
            -InformationLevel Quiet
    )
}

$Tickets = (& klist.exe tickets 2>&1 | Out-String)

$Checks += [PSCustomObject]@{
    Check = 'Kerberos TGT'
    Result = [bool](
        $LASTEXITCODE -eq 0 -and
        $Tickets -match 'krbtgt/'
    )
}

Write-Host "`nCurrent identity: $($Identity.Name)"
Write-Host "Computer: $env:COMPUTERNAME"

$Checks | Format-Table -AutoSize

$Passed = @($Checks | Where-Object Result -eq $true).Count
$Failed = @($Checks | Where-Object Result -eq $false).Count

Write-Host "`nPassed: $Passed"
Write-Host "Failed: $Failed"

if ($Failed -eq 0) {
    Write-Host 'LAB 6 - USER SESSION VERIFIED' -ForegroundColor Green
}
else {
    Write-Warning 'Some checks require investigation.'
}
