# ==========================================================
# LAB 5 - Script 05 - Assign Group Memberships
# Run on Hyper-V host as Administrator
# ==========================================================

$ErrorActionPreference = 'Stop'
Import-Module Hyper-V -ErrorAction Stop

$Memberships = @(
    @{Group='GG_IT_Users'; Members=@('anna.kowalska','piotr.nowak')}
    @{Group='GG_Admin_Users'; Members=@('marta.wisniewska','tomasz.zielinski')}
    @{Group='GG_Finance_Users'; Members=@('ewa.kaczmarek','adam.lewandowski')}
    @{Group='GG_HR_Users'; Members=@('karolina.wojcik','michal.kaminski')}
    @{Group='GG_IT_Admins'; Members=@('adm.lab')}

    @{Group='DL_IT_Read'; Members=@('GG_IT_Users')}
    @{Group='DL_Admin_Read'; Members=@('GG_Admin_Users')}
    @{Group='DL_Finance_RW'; Members=@('GG_Finance_Users')}
    @{Group='DL_HR_Read'; Members=@('GG_HR_Users')}
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
        -ArgumentList (,$Memberships) `
        -ScriptBlock {

            param([object[]]$Memberships)

            $ErrorActionPreference = 'Stop'
            Import-Module ActiveDirectory

            foreach ($Entry in $Memberships) {

                $Group = Get-ADGroup `
                    -Identity $Entry.Group `
                    -ErrorAction Stop

                foreach ($MemberName in $Entry.Members) {

                    $Member = Get-ADObject `
                        -LDAPFilter "(sAMAccountName=$MemberName)" `
                        -ErrorAction Stop

                    if (-not $Member) {
                        throw "Missing member: $MemberName"
                    }

                    $ExistingMembers = @(
                        Get-ADGroupMember `
                            -Identity $Group `
                            -ErrorAction Stop |
                        Select-Object -ExpandProperty DistinguishedName
                    )

                    if ($Member.DistinguishedName -in $ExistingMembers) {
                        $Action = 'EXISTS'
                    }
                    else {
                        Add-ADGroupMember `
                            -Identity $Group `
                            -Members $Member `
                            -ErrorAction Stop

                        $Action = 'ADDED'
                    }

                    [PSCustomObject]@{
                        Group = $Entry.Group
                        Member = $MemberName
                        Action = $Action
                        Status = 'PASS'
                    }
                }
            }
        } `
        -ErrorAction Stop

    Write-Host "`nLAB 5 - GROUP MEMBERSHIPS" `
        -ForegroundColor Cyan

    $Results |
        Format-Table Group, Member, Action, Status -AutoSize |
        Out-Host
}
finally {
    if ($Session) {
        Remove-PSSession $Session
    }
}