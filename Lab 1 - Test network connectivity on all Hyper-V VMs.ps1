
# ==========================================================
# LAB 1 - Network connectivity tests on Hyper-V VMs
# Run on Hyper-V HOST as Administrator
# PowerShell Direct with pre-filled usernames
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

$Computers = [ordered]@{
    'SEA-DC1'  = '10.10.10.10'
    'SEA-SRV1' = '10.10.10.20'
    'SEA-SRV2' = '10.10.10.30'
    'SEA-CL1'  = '10.10.10.100'
}

# Load Hyper-V module on HOST only
Import-Module Hyper-V -ErrorAction Stop

# Store only structured test results
$AllResults = [System.Collections.Generic.List[object]]::new()

foreach ($VMName in $VMs) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "===================================="
        Write-Host "Testing from VM: $VMName" -ForegroundColor Cyan
        Write-Host "===================================="

        # Verify VM
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "$VMName is not running."
        }

        # Pre-fill local user
        $UserName = if ($VMName -eq 'SEA-CL1') {
            '.\Admin'
        }
        else {
            '.\Administrator'
        }

        $Credential = Get-Credential `
            -UserName $UserName `
            -Message "Enter password for $VMName"

        if ($null -eq $Credential) {
            throw "Credentials not provided."
        }

        # Connect using PowerShell Direct
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Execute tests inside guest VM
        $VMResults = @(
            Invoke-Command `
                -Session $Session `
                -ArgumentList $VMName, $Computers `
                -ScriptBlock {

                    param(
                        [string]$SourceVM,
                        [System.Collections.IDictionary]$Targets
                    )

                    foreach ($TargetVM in $Targets.Keys) {

                        $IP = $Targets[$TargetVM]

                        if ($SourceVM -eq $TargetVM) {
                            $Status = 'LOCAL'
                        }
                        else {
                            $Success = Test-Connection `
                                -ComputerName $IP `
                                -Count 2 `
                                -Quiet `
                                -ErrorAction SilentlyContinue

                            $Status = if ($Success) {
                                'PASS'
                            }
                            else {
                                'FAIL'
                            }
                        }

                        [PSCustomObject]@{
                            SourceVM  = $SourceVM
                            TargetVM  = $TargetVM
                            IPAddress = $IP
                            Status    = $Status
                        }
                    }
                } `
                -ErrorAction Stop
        )

        # Add structured data to the report
        foreach ($Item in $VMResults) {
            $AllResults.Add($Item)
        }

        # Display per-VM summary without polluting results
        Write-Host "Tests completed for $VMName" `
            -ForegroundColor Green
    }
    catch {
        $Message = $_.Exception.Message

        Write-Warning ("{0}: {1}" -f $VMName, $Message)

        $AllResults.Add(
            [PSCustomObject]@{
                SourceVM  = $VMName
                TargetVM  = 'ALL'
                IPAddress = ''
                Status    = 'ERROR'
            }
        )
    }
    finally {
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# ==========================================================
# FINAL REPORT
# ==========================================================

Write-Host ""
Write-Host "===================================="
Write-Host "LAB 1 - CONNECTIVITY TEST REPORT"
Write-Host "===================================="

# Format only once, at the end
$AllResults |
    Format-Table SourceVM, TargetVM, IPAddress, Status -AutoSize |
    Out-Host

# Calculate statistics
$Passed = @($AllResults | Where-Object Status -eq 'PASS').Count
$Failed = @($AllResults | Where-Object Status -eq 'FAIL').Count
$Errors = @($AllResults | Where-Object Status -eq 'ERROR').Count
$Local  = @($AllResults | Where-Object Status -eq 'LOCAL').Count

Write-Host ""
Write-Host "NETWORK TEST SUMMARY" -ForegroundColor Cyan

Write-Host "Passed: $Passed" -ForegroundColor Green
Write-Host "Failed: $Failed" -ForegroundColor Yellow
Write-Host "Errors: $Errors" -ForegroundColor Red
Write-Host "Local tests skipped: $Local"

if ($Passed -eq 12 -and $Failed -eq 0 -and $Errors -eq 0) {

    Write-Host ""
    Write-Host "LAB 1 - ALL NETWORK TESTS PASSED" `
        -ForegroundColor Green
}
else {
    Write-Warning "Some tests failed or were not completed."
}
