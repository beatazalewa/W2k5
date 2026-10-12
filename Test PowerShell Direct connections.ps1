# =====================================================
# Test PowerShell Direct connections
# Separate credentials for each virtual machine
# Run on the Hyper-V host as Administrator
# =====================================================

$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

$Results = foreach ($VM in $VMs) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "===================================="
        Write-Host "Connecting to: $VM" -ForegroundColor Cyan
        Write-Host "===================================="

        # Check if VM exists and is running
        $VMObject = Get-VM -Name $VM -ErrorAction Stop

        if ($VMObject.State -ne 'Running') {
            throw "Virtual machine $VM is not running."
        }

        # Request separate credentials for each VM
        $Credential = Get-Credential -Message "Enter administrator credentials for $VM"

        if ($null -eq $Credential) {
            throw "No credentials provided for $VM."
        }

        # Create a PowerShell Direct session
        $Session = New-PSSession `
            -VMName $VM `
            -Credential $Credential `
            -ErrorAction Stop

        # Execute hostname command inside the VM
        $ComputerName = Invoke-Command `
            -Session $Session `
            -ScriptBlock {
                hostname
            } `
            -ErrorAction Stop

        Write-Host "$VM - OK - $ComputerName" `
            -ForegroundColor Green

        # Save successful result
        [PSCustomObject]@{
            VMName       = $VM
            ComputerName = $ComputerName
            Status       = 'OK'
            Error        = ''
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message

        Write-Warning "${VM} - FAILED - $ErrorMessage"

        # Save failed result
        [PSCustomObject]@{
            VMName       = $VM
            ComputerName = ''
            Status       = 'FAILED'
            Error        = $ErrorMessage
        }
    }
    finally {
        # Close PowerShell Direct session
        if ($Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# Display test summary
Write-Host ""
Write-Host "===================================="
Write-Host "POWERSHELL DIRECT TEST SUMMARY"
Write-Host "===================================="

$Results |
    Format-Table VMName, ComputerName, Status, Error -AutoSize
