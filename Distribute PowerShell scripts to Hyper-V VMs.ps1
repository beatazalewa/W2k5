
# =====================================================
# Distribute PowerShell scripts to Hyper-V VMs
# Create C:\LabScripts inside each virtual machine
# Use separate administrator credentials for each VM
# Run on the Hyper-V host as Administrator
# =====================================================

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

# Create source folder on the host if necessary
if (-not (Test-Path -LiteralPath $SourceFolder)) {
    New-Item `
        -Path $SourceFolder `
        -ItemType Directory `
        -Force | Out-Null

    Write-Host "Created host folder: $SourceFolder" `
        -ForegroundColor Yellow
}

# Find PowerShell scripts on the host
$ScriptFiles = @(
    Get-ChildItem `
        -LiteralPath $SourceFolder `
        -Filter '*.ps1' `
        -File
)

if ($ScriptFiles.Count -eq 0) {
    throw "No .ps1 files found in $SourceFolder. Add scripts and run again."
}

# Process each virtual machine
$Results = foreach ($VMName in $VMs) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "===================================="
        Write-Host "Processing VM: $VMName" -ForegroundColor Cyan
        Write-Host "===================================="

        # Verify that VM exists and is running
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "Virtual machine $VMName is not running."
        }

        # Request separate administrator credentials
        $Credential = Get-Credential `
            -Message "Enter administrator credentials for $VMName"

        if ($null -eq $Credential) {
            throw "No credentials provided for $VMName."
        }

        # Open PowerShell Direct session
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Create C:\LabScripts inside the VM
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
                else {
                    Write-Output "Folder already exists: $Folder"
                }
            } `
            -ErrorAction Stop

        # Copy all PowerShell scripts into the VM
        foreach ($File in $ScriptFiles) {

            Copy-Item `
                -LiteralPath $File.FullName `
                -Destination $DestinationFolder `
                -ToSession $Session `
                -Force `
                -ErrorAction Stop

            Write-Host "Copied: $($File.Name)" `
                -ForegroundColor Green
        }

        # Verify that expected files exist in the VM
        $CopiedFiles = Invoke-Command `
            -Session $Session `
            -ArgumentList $DestinationFolder `
            -ScriptBlock {
                param($Folder)

                @(
                    Get-ChildItem `
                        -LiteralPath $Folder `
                        -Filter '*.ps1' `
                        -File `
                        -ErrorAction Stop |
                    Select-Object -ExpandProperty Name
                )
            } `
            -ErrorAction Stop

        $MissingFiles = @(
            $ScriptFiles |
            Where-Object { $_.Name -notin $CopiedFiles }
        )

        if ($MissingFiles.Count -gt 0) {
            throw "Some script files are missing on $VMName."
        }

        Write-Host ""
        Write-Host "$VMName - folder ready and scripts copied." `
            -ForegroundColor Green

        # Successful result
        [PSCustomObject]@{
            VMName       = $VMName
            Folder       = $DestinationFolder
            Status       = 'OK'
            FilesCopied  = $ScriptFiles.Count
            Error        = ''
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message

        Write-Warning "${VMName} - FAILED - $ErrorMessage"

        # Failed result
        [PSCustomObject]@{
            VMName       = $VMName
            Folder       = $DestinationFolder
            Status       = 'FAILED'
            FilesCopied  = 0
            Error        = $ErrorMessage
        }
    }
    finally {
        # Close the session
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# Display the summary
Write-Host ""
Write-Host "===================================="
Write-Host "SCRIPT DISTRIBUTION SUMMARY"
Write-Host "===================================="

$Results |
    Format-Table VMName, Folder, Status, FilesCopied, Error -AutoSize
