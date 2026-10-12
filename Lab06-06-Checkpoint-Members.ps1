# ==========================================================
# LAB 6 - Script 06 - Create Member VM Checkpoints
#
# Run ONLY on host as Administrator.
#
# Domain: contoso.com
#
# Target virtual machines:
#   SEA-SRV1 - Windows Server 2025
#   SEA-SRV2 - Windows Server 2025
#   SEA-CL1  - Windows 11
#
# Checkpoint type: ProductionOnly
# Checkpoint name: LAB06-Domain-Joined
#
# Prerequisites:
#   LAB06-04-Verify-Domain.ps1 passed
#   Domain logon tests completed
#
# Reports: CSV
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

# ----------------------------------------------------------
# 2. Configuration
# ----------------------------------------------------------

$VMNames = @(
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

$CheckpointName = 'LAB06-Domain-Joined'
$ReportDir = 'C:\LabReports'

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path `
    $ReportDir `
    "LAB06-Checkpoints_$Timestamp.csv"

$Results = [System.Collections.Generic.List[object]]::new()

# ----------------------------------------------------------
# 3. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - PRODUCTION CHECKPOINTS"
Write-Host "=========================================="
Write-Host ""
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Domain: contoso.com"
Write-Host "Checkpoint name: $CheckpointName"
Write-Host "Target VMs: $($VMNames.Count)"
Write-Host ""

# ----------------------------------------------------------
# 4. Process each virtual machine
# ----------------------------------------------------------

foreach ($VMName in $VMNames) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Processing: $VMName"
    Write-Host "------------------------------------------"

    try {

        # --------------------------------------------------
        # 5. Verify virtual machine
        # --------------------------------------------------

        $VM = Get-VM `
            -Name $VMName `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "Virtual machine $VMName is not running."
        }

        # --------------------------------------------------
        # 6. Configure production checkpoints only
        # --------------------------------------------------

        Set-VM `
            -Name $VMName `
            -CheckpointType ProductionOnly `
            -ErrorAction Stop

        # --------------------------------------------------
        # 7. Check for existing checkpoint
        # --------------------------------------------------

        $Existing = @(
            Get-VMSnapshot `
                -VMName $VMName `
                -Name $CheckpointName `
                -ErrorAction SilentlyContinue
        )

        $TargetCheckpointName = $CheckpointName

        if ($Existing.Count -gt 0) {

            $ExistingType = [string](
                $Existing[0].SnapshotType
            )

            if ($ExistingType -match 'Production') {

                Write-Host (
                    "Production checkpoint already exists " +
                    "for $VMName."
                ) -ForegroundColor Green

                $Results.Add(
                    [PSCustomObject]@{
                        VM = $VMName
                        Checkpoint = $CheckpointName
                        SnapshotType = $ExistingType
                        Action = 'ALREADY_EXISTS'
                        Status = 'PASS'
                        Error = ''
                    }
                )

                continue
            }

            # Preserve an existing standard checkpoint
            $TargetCheckpointName = (
                "$CheckpointName-Production"
            )

            Write-Warning (
                "Existing checkpoint for $VMName " +
                "is not identified as production."
            )
        }

        # --------------------------------------------------
        # 8. Prevent checkpoint name collision
        # --------------------------------------------------

        $ExistingTarget = @(
            Get-VMSnapshot `
                -VMName $VMName `
                -Name $TargetCheckpointName `
                -ErrorAction SilentlyContinue
        )

        if ($ExistingTarget.Count -gt 0) {

            throw (
                "Checkpoint name already exists: " +
                $TargetCheckpointName
            )
        }

        # --------------------------------------------------
        # 9. Create production checkpoint
        # --------------------------------------------------

        Write-Host (
            "Creating checkpoint: $TargetCheckpointName"
        ) -ForegroundColor Cyan

        Checkpoint-VM `
            -Name $VMName `
            -SnapshotName $TargetCheckpointName `
            -ErrorAction Stop

        # --------------------------------------------------
        # 10. Verify checkpoint
        # --------------------------------------------------

        $Created = Get-VMSnapshot `
            -VMName $VMName `
            -Name $TargetCheckpointName `
            -ErrorAction Stop

        $CreatedType = [string]$Created.SnapshotType

        if ($CreatedType -notmatch 'Production') {

            throw (
                "Checkpoint was created but its type " +
                "is not identified as production: " +
                $CreatedType
            )
        }

        # --------------------------------------------------
        # 11. Record successful result
        # --------------------------------------------------

        $Results.Add(
            [PSCustomObject]@{
                VM = $VMName
                Checkpoint = $TargetCheckpointName
                SnapshotType = $CreatedType
                Action = 'CREATED'
                Status = 'PASS'
                Error = ''
            }
        )

        Write-Host (
            "Checkpoint verified for $VMName."
        ) -ForegroundColor Green

    }
    catch {

        # --------------------------------------------------
        # 12. Record failure and continue
        # --------------------------------------------------

        $Message = $_.Exception.Message

        Write-Warning (
            "Checkpoint operation failed for " +
            "${VMName}: $Message"
        )

        $Results.Add(
            [PSCustomObject]@{
                VM = $VMName
                Checkpoint = $CheckpointName
                SnapshotType = ''
                Action = 'ERROR'
                Status = 'FAIL'
                Error = $Message
            }
        )
    }
}

# ----------------------------------------------------------
# 13. Display checkpoint report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - CHECKPOINT REPORT"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table `
        VM,
        Checkpoint,
        SnapshotType,
        Action,
        Status `
        -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 14. Export CSV report
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 15. Calculate statistics
# ----------------------------------------------------------

$CreatedCount = @(
    $Results |
    Where-Object {
        $_.Action -eq 'CREATED'
    }
).Count

$ExistingCount = @(
    $Results |
    Where-Object {
        $_.Action -eq 'ALREADY_EXISTS'
    }
).Count

$FailedCount = @(
    $Results |
    Where-Object {
        $_.Status -eq 'FAIL'
    }
).Count

Write-Host ""
Write-Host "Created: $CreatedCount" -ForegroundColor Green
Write-Host "Already existing: $ExistingCount" `
    -ForegroundColor Cyan
Write-Host "Failed: $FailedCount" -ForegroundColor Yellow

Write-Host ""
Write-Host "CSV report: $CSV"

# ----------------------------------------------------------
# 16. Display all checkpoints
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - ALL MEMBER VM CHECKPOINTS"
Write-Host "=========================================="

foreach ($VMName in $VMNames) {

    Write-Host ""
    Write-Host "VM: $VMName" -ForegroundColor Cyan

    Get-VMSnapshot `
        -VMName $VMName `
        -ErrorAction SilentlyContinue |
    Select-Object `
        Name,
        SnapshotType,
        CreationTime |
    Sort-Object CreationTime |
    Format-Table -AutoSize |
    Out-Host
}

# ----------------------------------------------------------
# 17. Final validation
# ----------------------------------------------------------

if (
    $FailedCount -eq 0 -and
    ($CreatedCount + $ExistingCount) -eq $VMNames.Count
) {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 6 - CHECKPOINTS VERIFIED"
    Write-Host "=========================================="

}
else {

    Write-Warning (
        "Some checkpoints could not be verified. " +
        "Review the report before continuing."
    )
}

