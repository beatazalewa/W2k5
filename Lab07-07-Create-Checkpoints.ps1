# ==========================================================
# LAB 7 - Create Hyper-V Checkpoints
#
# Run ONLY on host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Checkpoint name:
#   LAB07-Authentication-Verified
#
# Target VMs:
#   SEA-SRV1
#   SEA-SRV2
#   SEA-CL1
#
# SEA-DC1 is deliberately excluded.
#
# Uses production-only checkpoints.
# Does not shut down or restart virtual machines.
# ==========================================================

$ErrorActionPreference = 'Stop'

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$VMNames = @(
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

$CheckpointName = 'LAB07-Authentication-Verified'

$ReportDir = 'C:\LabReports'

New-Item `
    -Path $ReportDir `
    -ItemType Directory `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$ReportPath = Join-Path $ReportDir `
    "LAB07-Checkpoints_$Timestamp.csv"

$Results = @()

# ----------------------------------------------------------
# 2. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - CREATE HYPER-V CHECKPOINTS"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Checkpoint: $CheckpointName"
Write-Host "VMs: $($VMNames -join ', ')"
Write-Host ""

# ----------------------------------------------------------
# 3. Process virtual machines
# ----------------------------------------------------------

foreach ($VMName in $VMNames) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Processing: $VMName"
    Write-Host "------------------------------------------"

    try {

        # Verify the virtual machine exists
        $VM = Get-VM `
            -Name $VMName `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "Virtual machine is not running."
        }

        # Avoid creating duplicate checkpoints
        $ExistingCheckpoint = Get-VMSnapshot `
            -VMName $VMName `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq $CheckpointName
            }

        if ($ExistingCheckpoint) {

            Write-Host "Checkpoint already exists." `
                -ForegroundColor Yellow

            $Status = 'EXISTS'

        }
        else {

            # Require a production checkpoint
            # without fallback to a standard checkpoint

            Set-VM `
                -Name $VMName `
                -CheckpointType ProductionOnly `
                -ErrorAction Stop

            Write-Host "Creating production checkpoint..."

            Checkpoint-VM `
                -Name $VMName `
                -SnapshotName $CheckpointName `
                -ErrorAction Stop

            $Status = 'CREATED'

            Write-Host "Checkpoint created successfully." `
                -ForegroundColor Green
        }

        # Verify the checkpoint
        $Checkpoint = Get-VMSnapshot `
            -VMName $VMName `
            -ErrorAction Stop |
            Where-Object {
                $_.Name -eq $CheckpointName
            }

        if (-not $Checkpoint) {
            throw "Checkpoint verification failed."
        }

        $Results += [PSCustomObject]@{
            VM = $VMName
            Checkpoint = $CheckpointName
            Status = $Status
            Created = $Checkpoint.CreationTime
            VMState = [string]$VM.State
        }

    }
    catch {

        $Message = $_.Exception.Message

        Write-Warning "Checkpoint failed on ${VMName}: $Message"

        $Results += [PSCustomObject]@{
            VM = $VMName
            Checkpoint = $CheckpointName
            Status = 'FAIL'
            Created = $null
            VMState = $Message
        }
    }
}

# ----------------------------------------------------------
# 4. Export report
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $ReportPath `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 5. Display final results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - CHECKPOINT RESULTS"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table `
        VM,
        Checkpoint,
        Status,
        Created `
        -AutoSize |
    Out-Host

$Failed = @(
    $Results |
    Where-Object Status -eq 'FAIL'
).Count

Write-Host ""
Write-Host "Report: $ReportPath"

if ($Failed -gt 0) {

    Write-Warning "$Failed checkpoint operation(s) failed."

}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 7 - CHECKPOINTS VERIFIED"
    Write-Host "==========================================" `
        -ForegroundColor Green
}
