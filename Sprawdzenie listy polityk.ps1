$Credential = Get-Credential -UserName 'CONTOSO\Administrator'

Invoke-Command -VMName 'SEA-DC1' -Credential $Credential -ScriptBlock {

    Import-Module GroupPolicy

    Get-GPO -All -Domain 'contoso.com' |
        Where-Object {
            $_.DisplayName -like 'LAB09-*'
        } |
        Select-Object DisplayName, Id, GpoStatus

}