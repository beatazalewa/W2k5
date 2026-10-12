# ==========================================================
# LAB 1 - Execute script on all Hyper-V virtual machines
# Run FROM Hyper-V host, execute ONLY INSIDE virtual machines
# No network configuration changes on the Hyper-V host
# ==========================================================

$ErrorActionPreference = 'Stop'

$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

$SourceScript = 'C:\LabScripts\Lab 1 Script 2.ps1'
$DestinationScript = 'C:\LabScripts\Lab 1 Script 2.ps1'

$ExpectedIPs = @{
    'SEA-DC1'  = '10.10.10.10'
    'SEA-SRV1' = '10.10.10.20'
    'SEA-SRV2' = '10.10.10.30'
    'SEA-CL1'  = '10.10.10.100'
}

# Check source script on host - no modifications
if (-not (Test-Path -LiteralPath $SourceScript -PathType Leaf)) {
    throw "Source script not found: $SourceScript"
}

Import-Module Hyper-V -ErrorAction Stop

$Results = foreach ($VMName in $VMs) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "Processing VM: $VMName" -ForegroundColor Cyan

        # Check whether VM is running
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "VM $VMName is not running."
        }

        # Request separate credentials for each VM
        $Credential = Get-Credential `
            -Message "Enter credentials for $VMName"

        # Connect directly to the guest system
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Create folder inside VM only
        Invoke-Command -Session $Session -ScriptBlock {
            New-Item -Path 'C:\LabScripts' `
                -ItemType Directory -Force | Out-Null
        } -ErrorAction Stop

        # Copy script from host to VM
        Copy-Item `
            -LiteralPath $SourceScript `
            -Destination $DestinationScript `
            -ToSession $Session `
            -Force `
            -ErrorAction Stop

        # Execute script only inside VM
        Invoke-Command `
            -Session $Session `
            -ScriptBlock {
                $ErrorActionPreference = 'Stop'

                & 'C:\LabScripts\Lab 1 Script 2.ps1'
            } `
            -ErrorAction Stop | Out-Null

        # Verify IP address inside the VM
        $ActualIPs = @(
            Invoke-Command `
                -Session $Session `
                -ScriptBlock {
                    Get-NetIPAddress -AddressFamily IPv4 |
                        Select-Object -ExpandProperty IPAddress
                } `
                -ErrorAction Stop
        )

        $ExpectedIP = $ExpectedIPs[$VMName]

        if ($ExpectedIP -notin $ActualIPs) {
            throw "Expected IP $ExpectedIP not found inside $VMName."
        }

        Write-Host "$VMName - SUCCESS: $ExpectedIP" `
            -ForegroundColor Green

        [PSCustomObject]@{
            VMName = $VMName
            IP = $ExpectedIP
            Status = 'OK'
            Error = ''
        }
    }
    catch {
        Write-Warning ("{0}: {1}" -f $VMName, $_.Exception.Message)

        [PSCustomObject]@{
            VMName = $VMName
            IP = $ExpectedIPs[$VMName]
            Status = 'FAILED'
            Error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

Write-Host ""
Write-Host "LAB 1 - RESULTS" -ForegroundColor Cyan
$Results | Format-Table -AutoSize
