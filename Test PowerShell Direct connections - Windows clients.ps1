# Test PowerShell Direct connections - Windows clients
# Run on the Hyper-V host as Administrator

$VMs = @(
    'SEA-CL1'
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