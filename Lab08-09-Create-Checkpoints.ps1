# ==========================================================
# LAB 8 - Script 09 - Create Checkpoints
#
# Run ONLY on the Hyper-V host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Automatically detects the Hyper-V host name.
#
# Target VMs:
#   SEA-SRV1
#   SEA-SRV2
#   SEA-CL1
#
# Excluded VM:
#   SEA-DC1
#
# Checkpoint name:
#   LAB08-Group-Policies-Verified
#
# Features:
#   Verify Hyper-V environment
#   Verify target virtual machines
#   Exclude the domain controller
#   Reuse existing named checkpoints
#   Prefer production checkpoints
#   Never silently fall back to standard checkpoints
#   Restore original checkpoint type settings
#   Verify checkpoint existence
#   Export CSV, TXT and HTML reports
#
# No VM is stopped or restarted.
# No existing checkpoint is deleted.
# No checkpoint is restored.
# ==========================================================

[CmdletBinding()]
param(
    [string]$CheckpointName = 'LAB08-Group-Policies-Verified',
    [string]$ReportDir = 'C:\LabReports'
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$HostName = $env:COMPUTERNAME

$TargetVMs = @(
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

$ExcludedVM = 'SEA-DC1'

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $ReportDir (
    "LAB08-Checkpoints_$Timestamp.csv"
)

$TXT = Join-Path $ReportDir (
    "LAB08-Checkpoints_$Timestamp.txt"
)

$HTML = Join-Path $ReportDir (
    "LAB08-Checkpoints_$Timestamp.html"
)

$Results = New-Object 'System.Collections.Generic.List[object]'

# ----------------------------------------------------------
# 2. Helper function
# ----------------------------------------------------------

function Add-Result {
    param(
        [string]$VMName,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [ValidateSet('PASS','FAIL','INFO','REVIEW')]
        [string]$Status,
        [string]$Details = ''
    )

    [void]$Results.Add(
        [PSCustomObject]@{
            VM = $VMName
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = $Status
            Details = $Details
        }
    )
}

# ----------------------------------------------------------
# 3. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CREATE VM CHECKPOINTS"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $HostName"
Write-Host "Checkpoint: $CheckpointName"
Write-Host "Excluded DC: $ExcludedVM"
Write-Host ""

# ----------------------------------------------------------
# 4. Verify administrator privileges
# ----------------------------------------------------------

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal `
    -ArgumentList $Identity

$IsAdmin = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {
    throw 'Run Windows PowerShell as Administrator.'
}

# ----------------------------------------------------------
# 5. Load Hyper-V module
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

New-Item `
    -Path $ReportDir `
    -ItemType Directory `
    -Force `
    -ErrorAction Stop | Out-Null

# ----------------------------------------------------------
# 6. Verify target list does not contain the DC
# ----------------------------------------------------------

if ($ExcludedVM -in $TargetVMs) {
    throw 'The domain controller must not be in TargetVMs.'
}

if ($TargetVMs.Count -ne 3) {
    throw 'Expected exactly three target virtual machines.'
}

# ----------------------------------------------------------
# 7. Verify domain controller exclusion
# ----------------------------------------------------------

$DCCheckpointsBefore = @(
    Get-VMSnapshot `
        -VMName $ExcludedVM `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq $CheckpointName
    }
)

# ----------------------------------------------------------
# 8. Process member VMs
# ----------------------------------------------------------

foreach ($VMName in $TargetVMs) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Processing: $VMName"
    Write-Host "------------------------------------------"

    $VM = Get-VM `
        -Name $VMName `
        -ErrorAction SilentlyContinue

    if ($null -eq $VM) {

        Add-Result `
            -VMName $VMName `
            -Check 'VM exists' `
            -Expected 'True' `
            -Actual 'False' `
            -Status 'FAIL' `
            -Details 'Virtual machine not found.'

        continue
    }

    Add-Result `
        -VMName $VMName `
        -Check 'VM exists' `
        -Expected 'True' `
        -Actual 'True' `
        -Status 'PASS'

    # ------------------------------------------------------
    # 9. Verify VM state
    # ------------------------------------------------------

    $VMState = [string]$VM.State

    $Running = ($VMState -eq 'Running')

    Add-Result `
        -VMName $VMName `
        -Check 'VM running' `
        -Expected 'Running' `
        -Actual $VMState `
        -Status $(if ($Running) {
            'PASS'
        }
        else {
            'FAIL'
        })

    if (-not $Running) {
        continue
    }

    # ------------------------------------------------------
    # 10. Check whether checkpoint already exists
    # ------------------------------------------------------

    $Existing = @(
        Get-VMSnapshot `
            -VMName $VMName `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq $CheckpointName
        }
    )

    if ($Existing.Count -gt 1) {

        Add-Result `
            -VMName $VMName `
            -Check 'Checkpoint uniqueness' `
            -Expected 'One matching checkpoint' `
            -Actual "$($Existing.Count) matches" `
            -Status 'FAIL' `
            -Details 'Duplicate checkpoint names require manual review.'

        continue
    }

    if ($Existing.Count -eq 1) {

        Write-Host "Checkpoint already exists."

        Add-Result `
            -VMName $VMName `
            -Check 'Checkpoint action' `
            -Expected 'Created or existing' `
            -Actual 'EXISTING' `
            -Status 'PASS' `
            -Details 'Existing checkpoint was preserved.'

        $CreatedThisRun = $false
    }
    else {

        # --------------------------------------------------
        # 11. Configure temporary checkpoint type
        # --------------------------------------------------

        $OriginalVM = Get-VM -Name $VMName -ErrorAction Stop

        $OriginalCheckpointType = (
            [string]$OriginalVM.CheckpointType
        )

        $SettingsChanged = $false
        $CreatedThisRun = $false

        try {

            # ProductionOnly prevents fallback to standard
            # checkpoints if production checkpoint creation
            # is unsuccessful.

            if ($OriginalCheckpointType -ne 'ProductionOnly') {

                Set-VM `
                    -Name $VMName `
                    -CheckpointType ProductionOnly `
                    -ErrorAction Stop

                $SettingsChanged = $true
            }

            # ----------------------------------------------
            # 12. Create production checkpoint
            # ----------------------------------------------

            Write-Host "Creating production checkpoint..."

            Checkpoint-VM `
                -Name $VMName `
                -SnapshotName $CheckpointName `
                -ErrorAction Stop

            $CreatedThisRun = $true

            Add-Result `
                -VMName $VMName `
                -Check 'Checkpoint action' `
                -Expected 'Created or existing' `
                -Actual 'CREATED' `
                -Status 'PASS'
        }
        catch {

            Add-Result `
                -VMName $VMName `
                -Check 'Checkpoint action' `
                -Expected 'Created or existing' `
                -Actual 'FAILED' `
                -Status 'FAIL' `
                -Details $_.Exception.Message
        }
        finally {

            # ----------------------------------------------
            # 13. Restore original VM checkpoint settings
            # ----------------------------------------------

            if ($SettingsChanged) {

                try {

                    Set-VM `
                        -Name $VMName `
                        -CheckpointType $OriginalCheckpointType `
                        -ErrorAction Stop

                    Add-Result `
                        -VMName $VMName `
                        -Check 'Checkpoint settings restored' `
                        -Expected $OriginalCheckpointType `
                        -Actual $OriginalCheckpointType `
                        -Status 'PASS'
                }
                catch {

                    Add-Result `
                        -VMName $VMName `
                        -Check 'Checkpoint settings restored' `
                        -Expected $OriginalCheckpointType `
                        -Actual 'FAILED' `
                        -Status 'FAIL' `
                        -Details $_.Exception.Message
                }
            }
            else {

                Add-Result `
                    -VMName $VMName `
                    -Check 'Checkpoint settings preserved' `
                    -Expected $OriginalCheckpointType `
                    -Actual $OriginalCheckpointType `
                    -Status 'PASS'
            }
        }
    }

    # ------------------------------------------------------
    # 14. Verify checkpoint existence
    # ------------------------------------------------------

    $Verified = @(
        Get-VMSnapshot `
            -VMName $VMName `
            -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq $CheckpointName
        }
    )

    $CheckpointOK = ($Verified.Count -eq 1)

    Add-Result `
        -VMName $VMName `
        -Check 'Checkpoint verified' `
        -Expected 'One matching checkpoint' `
        -Actual "$($Verified.Count) matches" `
        -Status $(if ($CheckpointOK) {
            'PASS'
        }
        else {
            'FAIL'
        })

    if ($CheckpointOK) {

        $Snapshot = $Verified[0]

        Write-Host "Checkpoint: $($Snapshot.Name)"
        Write-Host "Created: $($Snapshot.CreationTime)"
        Write-Host "ID: $($Snapshot.Id)"

        Add-Result `
            -VMName $VMName `
            -Check 'Checkpoint metadata' `
            -Expected $CheckpointName `
            -Actual ([string]$Snapshot.Name) `
            -Status 'INFO' `
            -Details (
                "ID=$($Snapshot.Id); " +
                "Created=$($Snapshot.CreationTime)"
            )
    }
}

# ----------------------------------------------------------
# 15. Verify DC was not modified by this script
# ----------------------------------------------------------

$DCCheckpointsAfter = @(
    Get-VMSnapshot `
        -VMName $ExcludedVM `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq $CheckpointName
    }
)

$DCUnchanged = (
    $DCCheckpointsBefore.Count -eq
    $DCCheckpointsAfter.Count
)

Add-Result `
    -VMName $ExcludedVM `
    -Check 'Domain controller excluded' `
    -Expected 'No new checkpoint' `
    -Actual $(if ($DCUnchanged) {
        'No new checkpoint'
    }
    else {
        'Checkpoint count changed'
    }) `
    -Status $(if ($DCUnchanged) {
        'PASS'
    }
    else {
        'FAIL'
    })

# ----------------------------------------------------------
# 16. Calculate statistics
# ----------------------------------------------------------

$Passed = @(
    $Results | Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Results | Where-Object Status -eq 'FAIL'
).Count

$Info = @(
    $Results | Where-Object Status -eq 'INFO'
).Count

$Review = @(
    $Results | Where-Object Status -eq 'REVIEW'
).Count

$Total = $Results.Count

$FinalStatus = if ($Failed -gt 0) {
    'FAILED'
}
elseif ($Review -gt 0) {
    'REVIEW REQUIRED'
}
else {
    'VERIFIED'
}

# ----------------------------------------------------------
# 17. Export CSV
# ----------------------------------------------------------

$Results |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 18. Generate TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 8 - SCRIPT 09 - CHECKPOINT REPORT
============================================================

Date: $(Get-Date)
Host: $HostName

Checkpoint name:
$CheckpointName

Target virtual machines:
$($TargetVMs -join ', ')

Excluded domain controller:
$ExcludedVM

RESULTS
Total: $Total
PASS: $Passed
FAIL: $Failed
INFO: $Info
REVIEW: $Review

Final status:
$FinalStatus

IMPORTANT:
Existing checkpoints were not deleted.
No checkpoint was restored.
The domain controller was excluded.
Checkpoints are not substitutes for backups.

============================================================
DETAILED RESULTS
============================================================

"@

$Details = $Results |
    Format-Table `
        VM,
        Check,
        Expected,
        Actual,
        Status,
        Details `
        -AutoSize |
    Out-String -Width 240

($Header + $Details) |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 19. Generate HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    background: #f5f9fb;
    color: #294554;
    margin: 32px;
    line-height: 1.6;
}
h1, h2 {
    color: #146393;
}
table {
    width: 100%;
    border-collapse: collapse;
    background: #ffffff;
}
th {
    background: #146393;
    color: #ffffff;
    text-align: left;
    padding: 10px;
}
td {
    border: 1px solid #dce6eb;
    padding: 9px;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
.summary {
    background: #ffffff;
    border: 1px solid #dce6eb;
    padding: 18px;
    margin-bottom: 24px;
}
</style>
"@

$SafeCheckpoint = [System.Net.WebUtility]::HtmlEncode(
    $CheckpointName
)

$HTMLIntro = @"
<h1>LAB 8 - VM Checkpoint Report</h1>

<div class="summary">
<p><strong>Host:</strong> $HostName</p>
<p><strong>Checkpoint:</strong> $SafeCheckpoint</p>
<p><strong>PASS:</strong> $Passed</p>
<p><strong>FAIL:</strong> $Failed</p>
<p><strong>INFO:</strong> $Info</p>
<p><strong>REVIEW:</strong> $Review</p>
<p><strong>Final status:</strong> $FinalStatus</p>
</div>

<h2>Checkpoint verification</h2>
"@

$Results |
    ConvertTo-Html `
        -Title 'LAB 8 - VM Checkpoints' `
        -Head $CSS `
        -PreContent $HTMLIntro |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 20. Display final results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - CHECKPOINT RESULTS"
Write-Host "=========================================="
Write-Host ""

$Results |
    Format-Table `
        VM,
        Check,
        Actual,
        Status `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red
Write-Host "INFO: $Info"
Write-Host "REVIEW: $Review"

Write-Host ""
Write-Host "Final status: $FinalStatus"

Write-Host ""
Write-Host "Reports on $HostName :"
Write-Host "CSV:  $CSV"
Write-Host "TXT:  $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 21. Final validation
# ----------------------------------------------------------

if ($Failed -gt 0) {
    throw (
        "LAB08-09 checkpoint verification failed. " +
        "Review the TXT report."
    )
}

if ($Review -gt 0) {
    Write-Warning (
        "LAB08-09 has items requiring review."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 8 - CHECKPOINTS VERIFIED"
    Write-Host "==========================================" `
        -ForegroundColor Green
}
