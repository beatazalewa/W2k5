# =====================================================
# Copy scripts to Hyper-V virtual machines
# Separate credentials for each VM
# Run on the Hyper-V host as Administrator
# =====================================================

$ErrorActionPreference = 'Stop'

$VMs = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2',
    'SEA-CL1'
)

$SourceFolder = 'C:\LabScripts'
$DestinationFolder = 'C:\LabScripts'

# Verify source folder and PowerShell scripts
if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
    throw "Source folder does not exist: $SourceFolder"
}

$ScriptFiles = @(
    Get-ChildItem -LiteralPath $SourceFolder -Filter '*.ps1' -File
)

if ($ScriptFiles.Count -eq 0) {
    throw "No PowerShell scripts found in $SourceFolder"
}

# Process each virtual machine
$Results = foreach ($VMName in $VMs) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "===================================="
        Write-Host "Connecting to $VMName" -ForegroundColor Cyan
        Write-Host "===================================="

        # Check VM state
        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "Virtual machine $VMName is not running."
        }

        # Request credentials separately for each VM
        $Credential = Get-Credential `
            -Message "Enter administrator credentials for $VMName"

        if ($null -eq $Credential) {
            throw "Credentials were not provided for $VMName."
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

                New-Item `
                    -Path $Folder `
                    -ItemType Directory `
                    -Force | Out-Null
            } `
            -ErrorAction Stop

        # Copy scripts from host to VM
        foreach ($File in $ScriptFiles) {

            Copy-Item `
                -LiteralPath $File.FullName `
                -Destination $DestinationFolder `
                -ToSession $Session `
                -Force `
                -ErrorAction Stop
        }

        # Verify files inside VM
        $CopiedFiles = Invoke-Command `
            -Session $Session `
            -ArgumentList $DestinationFolder `
            -ScriptBlock {
                param($Folder)

                @(Get-ChildItem `
                    -Path $Folder `
                    -Filter '*.ps1' `
                    -File).Name
            } `
            -ErrorAction Stop

        Write-Host "$VMName - scripts copied successfully." `
            -ForegroundColor Green

        [PSCustomObject]@{
            VMName      = $VMName
            Status      = 'OK'
            FilesCopied = $ScriptFiles.Count
            Error       = ''
        }
    }
    catch {
        $ErrorMessage = $_.Exception.Message

        Write-Warning "${VMName} - FAILED - $ErrorMessage"

        [PSCustomObject]@{
            VMName      = $VMName
            Status      = 'FAILED'
            FilesCopied = 0
            Error       = $ErrorMessage
        }
    }
    finally {
        # Close session
        if ($null -ne $Session) {
            Remove-PSSession -Session $Session
        }
    }
}

# Display summary
Write-Host ""
Write-Host "===================================="
Write-Host "FILE COPY SUMMARY"
Write-Host "===================================="

$Results |
    Format-Table VMName, Status, FilesCopied, Error -AutoSize
