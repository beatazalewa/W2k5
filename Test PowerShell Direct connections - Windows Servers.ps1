# Test PowerShell Direct connections - Windows Servers
# Run on the Hyper-V host as Administrator

$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2'
)

$Credential = Get-Credential

foreach ($VM in $VMs) {

    $Session = $null

    try {
        $Session = New-PSSession `
            -VMName $VM `
            -Credential $Credential `
            -ErrorAction Stop

        $ComputerName = Invoke-Command `
            -Session $Session `
            -ScriptBlock { hostname } `
            -ErrorAction Stop

        Write-Host "$VM : OK - $ComputerName" `
            -ForegroundColor Green
    }
    catch {
        Write-Warning "$VM : FAILED - $($_.Exception.Message)"
    }
    finally {
        if ($Session) {
            Remove-PSSession -Session $Session
        }
    }
}
