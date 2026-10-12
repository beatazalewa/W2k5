# ==========================================================
# LAB 5 - Script 03 - Create Security Groups
# Run on Hyper-V host as Administrator
# ==========================================================

$ErrorActionPreference = 'Stop'
Import-Module Hyper-V -ErrorAction Stop

$Groups = @(
    @{Name='GG_IT_Users'; Dept='IT'; Scope='Global'}
    @{Name='GG_IT_Admins'; Dept='IT'; Scope='Global'}
    @{Name='GG_Admin_Users'; Dept='Administracja'; Scope='Global'}
    @{Name='GG_Finance_Users'; Dept='Finanse'; Scope='Global'}
    @{Name='GG_HR_Users'; Dept='HR'; Scope='Global'}
    @{Name='DL_IT_Read'; Dept='IT'; Scope='DomainLocal'}
    @{Name='DL_Finance_RW'; Dept='Finanse'; Scope='DomainLocal'}
    @{Name='DL_HR_Read'; Dept='HR'; Scope='DomainLocal'}
    @{Name='DL_Admin_Read'; Dept='Administracja'; Scope='DomainLocal'}
)

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

$Session = $null

try {
    $Session = New-PSSession `
        -VMName 'SEA-DC1' `
        -Credential $Credential `
        -ErrorAction Stop

    $Results = Invoke-Command `
        -Session $Session `
        -ArgumentList (,$Groups) `
        -ScriptBlock {

            param([object[]]$Groups)

            $ErrorActionPreference = 'Stop'
            Import-Module ActiveDirectory

            $DomainDN = (Get-ADDomain).DistinguishedName

            foreach ($Group in $Groups) {

                $Path = "OU=Grupy,OU=$($Group.Dept),OU=Centrala,$DomainDN"

                $Existing = Get-ADGroup `
                    -LDAPFilter "(sAMAccountName=$($Group.Name))" `
                    -ErrorAction Stop

                if ($Existing) {

                    if (
                        $Existing.GroupScope -ne $Group.Scope -or
                        $Existing.GroupCategory -ne 'Security' -or
                        $Existing.DistinguishedName -notlike "*,$Path"
                    ) {
                        throw "Existing group has unexpected configuration: $($Group.Name)"
                    }

                    $Action = 'EXISTS'
                }
                else {
                    New-ADGroup `
                        -Name $Group.Name `
                        -SamAccountName $Group.Name `
                        -GroupScope $Group.Scope `
                        -GroupCategory Security `
                        -Path $Path `
                        -Description "LAB 5 - $($Group.Dept)" `
                        -ErrorAction Stop

                    $Action = 'CREATED'
                }

                [PSCustomObject]@{
                    Group = $Group.Name
                    Scope = $Group.Scope
                    Department = $Group.Dept
                    Action = $Action
                    Status = 'PASS'
                }
            }
        } `
        -ErrorAction Stop

    $Results |
        Format-Table Group, Scope, Action, Status -AutoSize |
        Out-Host
}
finally {
    if ($Session) {
        Remove-PSSession $Session
    }
}