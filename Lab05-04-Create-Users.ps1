# ==========================================================
# LAB 5 - Script 04 - Create Domain Users
# Run on Hyper-V host as Administrator
# Individual initial password for every new user
# ==========================================================

$ErrorActionPreference = 'Stop'
Import-Module Hyper-V -ErrorAction Stop

$Users = @(
    @{Login='anna.kowalska'; First='Anna'; Last='Kowalska'; Dept='IT'}
    @{Login='piotr.nowak'; First='Piotr'; Last='Nowak'; Dept='IT'}
    @{Login='marta.wisniewska'; First='Marta'; Last='Wisniewska'; Dept='Administracja'}
    @{Login='tomasz.zielinski'; First='Tomasz'; Last='Zielinski'; Dept='Administracja'}
    @{Login='ewa.kaczmarek'; First='Ewa'; Last='Kaczmarek'; Dept='Finanse'}
    @{Login='adam.lewandowski'; First='Adam'; Last='Lewandowski'; Dept='Finanse'}
    @{Login='karolina.wojcik'; First='Karolina'; Last='Wojcik'; Dept='HR'}
    @{Login='michal.kaminski'; First='Michal'; Last='Kaminski'; Dept='HR'}
    @{Login='adm.lab'; First='Lab'; Last='Administrator'; Dept='Konta administracyjne'}
)

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

$Session = $null
$Results = [System.Collections.Generic.List[object]]::new()

try {
    $Session = New-PSSession `
        -VMName 'SEA-DC1' `
        -Credential $Credential `
        -ErrorAction Stop

    foreach ($User in $Users) {

        $Login = $User.Login

        # Check whether account already exists
        $Existing = Invoke-Command `
            -Session $Session `
            -ArgumentList $Login `
            -ScriptBlock {
                param($Login)
                Import-Module ActiveDirectory

                [bool](Get-ADUser `
                    -Filter "SamAccountName -eq '$Login'" `
                    -ErrorAction Stop)
            } `
            -ErrorAction Stop

        if ($Existing) {
            $Results.Add([PSCustomObject]@{
                Login = $Login
                Action = 'EXISTS'
                Status = 'SKIPPED'
            })
            continue
        }

        # Prompt separately for each new user's password
        $Password = Read-Host `
            "Enter initial password for $Login" `
            -AsSecureString

        if ($Password.Length -eq 0) {
            throw "Password not provided for $Login"
        }

        try {
            $Created = Invoke-Command `
                -Session $Session `
                -ArgumentList $User, $Password `
                -ScriptBlock {

                    param($User, [securestring]$Password)

                    $ErrorActionPreference = 'Stop'
                    Import-Module ActiveDirectory

                    $DomainDN = (Get-ADDomain).DistinguishedName

                    if ($User.Dept -eq 'Konta administracyjne') {
                        $Path = "OU=Konta administracyjne,OU=Centrala,$DomainDN"
                    }
                    else {
                        $Path = "OU=Uzytkownicy,OU=$($User.Dept),OU=Centrala,$DomainDN"
                    }

                    $NewUser = New-ADUser `
                        -Name "$($User.First) $($User.Last)" `
                        -GivenName $User.First `
                        -Surname $User.Last `
                        -SamAccountName $User.Login `
                        -UserPrincipalName "$($User.Login)@contoso.com" `
                        -Department $User.Dept `
                        -Path $Path `
                        -AccountPassword $Password `
                        -Enabled $true `
                        -ChangePasswordAtLogon $true `
                        -PassThru `
                        -ErrorAction Stop

                    [PSCustomObject]@{
                        Login = $NewUser.SamAccountName
                        Action = 'CREATED'
                        Status = 'PASS'
                    }
                } `
                -ErrorAction Stop

            $Results.Add($Created)
        }
        finally {
            $Password = $null
        }
    }

    Write-Host "`nLAB 5 - USER CREATION REPORT" `
        -ForegroundColor Cyan

    $Results |
        Format-Table Login, Action, Status -AutoSize |
        Out-Host
}
finally {
    if ($Session) {
        Remove-PSSession $Session
    }
}