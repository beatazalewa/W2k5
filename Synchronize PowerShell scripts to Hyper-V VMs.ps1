
# ==========================================================
# Synchronize PowerShell scripts to Hyper-V VMs
# Run on the Hyper-V host as Administrator
#
# Existing files: OVERWRITE
# Missing files:  ADD
# VM-only files:   KEEP
# ==========================================================

$ErrorActionPreference = 'Stop'

# Virtual machines
$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

# Source folder on Hyper-V host
$SourceFolder = 'C:\LabScripts'

# Destination folder inside each VM
$DestinationFolder = 'C:\LabScripts'

# ----------------------------------------------------------
# STEP 1 - Verify source folder
# ----------------------------------------------------------

if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
    New-Item `
        -Path $SourceFolder `
        -ItemType Directory `
        -Force | Out-Null

    Write-Host "Created host folder: $SourceFolder" `
        -ForegroundColor Yellow
}

# Get PowerShell scripts
$ScriptFiles = @(
    Get-ChildItem `
        -LiteralPath $SourceFolder `
        -Filter '*.ps1' `
        -File
)

if ($ScriptFiles.Count -eq 0) {
    throw "No PowerShell scripts found in $SourceFolder"
}

Write-Host ""
Write-Host "Source scripts:" -ForegroundColor Cyan

$ScriptFiles |
    Select-Object Name, Length, LastWriteTime |
    Format-Table -AutoSize

# ----------------------------------------------------------
# STEP 2 - Process each virtual machine
# ----------------------------------------------------------

$Results = foreach ($VMName in $VMs) {

    $Session = $null
    $Added = 0
    $Overwritten = 0
    $Failed = 0

    try {

        Write-Host ""
        Write-Host "======================================"
        Write-Host "Processing VM: $VMName" -ForegroundColor Cyan
        Write-Host "======================================"

        # Verify VM state
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "Virtual machine $VMName is not running."
        }

        # Request separate credentials for each VM
        $Credential = Get-Credential `
            -Message "Enter administrator credentials for $VMName"

        if ($null -eq $Credential) {
            throw "No credentials provided for $VMName."
        }

        # Create PowerShell Direct session
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Create destination folder inside VM
        Invoke-Command `
            -Session $Session `
            -ArgumentList $DestinationFolder `
            -ScriptBlock {
                param($Folder)

                if (-not (Test-Path -LiteralPath $Folder)) {
                    New-Item `
                        -Path $Folder `
                        -ItemType Directory `
                        -Force `
                        -ErrorAction Stop | Out-Null

                    Write-Output "Created folder: $Folder"
                }
            } `
            -ErrorAction Stop

        # --------------------------------------------------
        # STEP 3 - Synchronize scripts
        # --------------------------------------------------

        foreach ($File in $ScriptFiles) {

            $DestinationFile = Join-Path `
                $DestinationFolder `
                $File.Name

            try {

                # Check whether file already exists inside VM
                $FileExists = Invoke-Command `
                    -Session $Session `
                    -ArgumentList $DestinationFile `
                    -ScriptBlock {
                        param($Path)

                        Test-Path `
                            -LiteralPath $Path `
                            -PathType Leaf
                    } `
                    -ErrorAction Stop

                if ($FileExists) {

                    # Overwrite existing script
                    Copy-Item `
                        -LiteralPath $File.FullName `
                        -Destination $DestinationFile `
                        -ToSession $Session `
                        -Force `
                        -ErrorAction Stop

                    $Overwritten++

                    Write-Host "OVERWRITTEN: $($File.Name)" `
                        -ForegroundColor Yellow
                }
                else {

                    # Copy new script
                    Copy-Item `
                        -LiteralPath $File.FullName `
                        -Destination $DestinationFile `
                        -ToSession $Session `
                        -ErrorAction Stop

                    $Added++

                    Write-Host "ADDED: $($File.Name)" `
                        -ForegroundColor Green
                }

                # Verify copied file using SHA256 hashes
                $SourceHash = (Get-FileHash `
                    -LiteralPath $File.FullName `
                    -Algorithm SHA256).Hash

                $DestinationHash = Invoke-Command `
                    -Session $Session `
                    -ArgumentList $DestinationFile `
                    -ScriptBlock {
                        param($Path)

                        (Get-FileHash `
                            -LiteralPath $Path `
                            -Algorithm SHA256).Hash
                    } `
                    -ErrorAction Stop

                if ($SourceHash -ne $DestinationHash) {
                    throw "SHA256 verification failed for $($File.Name)"
                }
            }
            catch {

                $Failed++

                Write-Warning (
                    "COPY FAILED: {0} - {1}" -f
                    $File.Name, $_.Exception.Message
                )
            }
        }

        # --------------------------------------------------
        # STEP 4 - Save VM results
        # --------------------------------------------------

        [PSCustomObject]@{
            VMName      = $VMName
            Status      = if ($Failed -eq 0) { 'OK' } else { 'PARTIAL' }
            Added       = $Added
            Overwritten = $Overwritten
            Failed      = $Failed
            Error       = ''
        }
    }
    catch {

        $ErrorMessage = $_.Exception.Message

        Write-Warning "${VMName} - FAILED - $ErrorMessage"

        [PSCustomObject]@{
            VMName      = $VMName
            Status      = 'FAILED'
            Added       = $Added
            Overwritten = $Overwritten
            Failed      = $Failed
            Error       = $ErrorMessage
        }
    }
    finally {

        # Close PowerShell Direct session
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# ----------------------------------------------------------
# STEP 5 - Display synchronization summary
# ----------------------------------------------------------

Write-Host ""
Write-Host "======================================"
Write-Host "SCRIPT SYNCHRONIZATION REPORT"
Write-Host "======================================"

$Results |
    Format-Table VMName, Status, Added, Overwritten, Failed -AutoSize

Write-Host ""
Write-Host "Synchronization completed." -ForegroundColor Cyan
