# =====================================================
# LAB 1 Script 1d - Verify computer names on all three servers and Win 11
# Run on Hyper-V host as Administrator
# =====================================================

$Servers = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

$Results = foreach ($Server in $Servers) {

    try {
        Write-Host ""
        Write-Host "Checking $Server..." -ForegroundColor Cyan

        # Pre-fill the local administrator username for each VM
        $LocalUser = if ($Server -eq 'SEA-CL1') { 'Admin' } else { 'Administrator' }
        $UserName = ".\$LocalUser"

        # Request only the password, with username pre-filled
        $Credential = Get-Credential `
            -UserName $UserName `
            -Message "Enter the password for $UserName on $Server"

        # Get Windows computer name through PowerShell Direct
        $ComputerName = Invoke-Command `
            -VMName $Server `
            -Credential $Credential `
            -ScriptBlock {
                hostname
            } `
            -ErrorAction Stop

        # Compare Hyper-V VM name with Windows computer name
        $Status = if ($ComputerName -eq $Server) {
            'OK'
        }
        else {
            'NAME MISMATCH'
        }

        [PSCustomObject]@{
            VMName       = $Server
            ComputerName = $ComputerName
            Status       = $Status
        }
    }
    catch {
        Write-Warning "${Server}: $($_.Exception.Message)"

        [PSCustomObject]@{
            VMName       = $Server
            ComputerName = ''
            Status       = 'FAILED'
        }
    }
}

# Display results
Write-Host ""
Write-Host "===================================="
Write-Host "COMPUTER NAME VERIFICATION"
Write-Host "===================================="

$Results | Format-Table -AutoSize
