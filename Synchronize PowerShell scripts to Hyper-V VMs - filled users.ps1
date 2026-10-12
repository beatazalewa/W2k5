# ==========================================================
# Synchronize PowerShell scripts to Hyper-V VMs
# Run on the Hyper-V host as Administrator
# ADDED:     file missing on VM, copy from host
# UPDATED:   file differs by SHA256, replace it
# UNCHANGED: same SHA256, do not copy
# VM-only files are preserved
# ==========================================================

$ErrorActionPreference = 'Stop'
$RunId = [guid]::NewGuid().ToString()
$StartTime = Get-Date

$VMs = @('SEA-DC1', 'SEA-SRV1', 'SEA-SRV2', 'SEA-CL1')
$SourceFolder = 'C:\LabScripts'
$DestinationFolder = 'C:\LabScripts'

Write-Host "SCRIPT STARTED - Run ID: $RunId" -ForegroundColor Cyan
Write-Host "Start time: $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"

Import-Module Hyper-V -ErrorAction Stop
if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
    New-Item -Path $SourceFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    Write-Host "Created host folder: $SourceFolder" -ForegroundColor Yellow
}

$ScriptFiles = @(Get-ChildItem -LiteralPath $SourceFolder -Filter '*.ps1' -File -ErrorAction Stop)
if ($ScriptFiles.Count -eq 0) { throw "No .ps1 files found in $SourceFolder" }

Write-Host "`nSource scripts:" -ForegroundColor Cyan
$ScriptFiles | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize

$Results = foreach ($VMName in $VMs) {
    $Session = $null
    $Added = 0
    $Updated = 0
    $Unchanged = 0
    $Failed = 0
    $TotalScripts = $null
    $ErrorText = ''

    try {
        Write-Host "`n======================================"
        Write-Host "Processing VM: $VMName" -ForegroundColor Cyan
        Write-Host "======================================"

        $VM = Get-VM -Name $VMName -ErrorAction Stop
        if ($VM.State -ne 'Running') { throw "Virtual machine $VMName is not running." }

        $LocalUser = if ($VMName -eq 'SEA-CL1') { 'Admin' } else { 'Administrator' }
        $UserName = ".\$LocalUser"
        $Credential = Get-Credential -UserName $UserName -Message "Enter the password for $UserName on $VMName"
        if ($null -eq $Credential) { throw "No credentials provided for $VMName." }

        $Session = New-PSSession -VMName $VMName -Credential $Credential -ErrorAction Stop
        Invoke-Command -Session $Session -ArgumentList $DestinationFolder -ScriptBlock {
            param($Folder)
            if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
                New-Item -Path $Folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
        } -ErrorAction Stop

        foreach ($File in $ScriptFiles) {
            $DestinationFile = Join-Path $DestinationFolder $File.Name
            try {
                $SourceHash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                $ExistingHash = Invoke-Command -Session $Session -ArgumentList $DestinationFile -ScriptBlock {
                    param($Path)
                    if (Test-Path -LiteralPath $Path -PathType Leaf) {
                        (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
                    }
                    else { $null }
                } -ErrorAction Stop

                $Action = if ([string]::IsNullOrEmpty($ExistingHash)) { 'ADDED' }
                          elseif ($ExistingHash -eq $SourceHash) { 'UNCHANGED' }
                          else { 'UPDATED' }

                if ($Action -ne 'UNCHANGED') {
                    Copy-Item -LiteralPath $File.FullName -Destination $DestinationFile -ToSession $Session -Force -ErrorAction Stop
                    $CopiedHash = Invoke-Command -Session $Session -ArgumentList $DestinationFile -ScriptBlock {
                        param($Path)
                        (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
                    } -ErrorAction Stop
                    if ($CopiedHash -ne $SourceHash) {
                        throw "SHA256 verification failed for $($File.Name)"
                    }
                }

                switch ($Action) {
                    'ADDED'     { $Added++;     Write-Host "ADDED: $($File.Name)" -ForegroundColor Green }
                    'UPDATED'   { $Updated++;   Write-Host "UPDATED: $($File.Name)" -ForegroundColor Yellow }
                    'UNCHANGED' { $Unchanged++; Write-Host "UNCHANGED: $($File.Name)" -ForegroundColor DarkGray }
                }
            }
            catch {
                $Failed++
                Write-Warning ("COPY FAILED: {0} - {1}" -f $File.Name, $_.Exception.Message)
            }
        }

        $TotalScripts = Invoke-Command -Session $Session -ArgumentList $DestinationFolder -ScriptBlock {
            param($Folder)
            @(Get-ChildItem -LiteralPath $Folder -Filter '*.ps1' -File -ErrorAction Stop).Count
        } -ErrorAction Stop

        $Status = if ($Failed -eq 0) { 'OK' } else { 'PARTIAL' }
    }
    catch {
        $ErrorText = $_.Exception.Message
        $Status = 'FAILED'
        Write-Warning ("{0} - FAILED - {1}" -f $VMName, $ErrorText)
    }
    finally {
        if ($null -ne $Session) { Remove-PSSession -Session $Session -ErrorAction SilentlyContinue }
    }

    [PSCustomObject]@{
        VMName       = $VMName
        Status       = $Status
        Added        = $Added
        Updated      = $Updated
        Unchanged    = $Unchanged
        Failed       = $Failed
        TotalScripts = $TotalScripts
        Error        = $ErrorText
    }
}

Write-Host "`n======================================"
Write-Host 'SCRIPT SYNCHRONIZATION REPORT' -ForegroundColor Cyan
Write-Host '======================================'
$Results | Format-Table VMName, Status, Added, Updated, Unchanged, Failed, TotalScripts -AutoSize
$BadResults = @($Results | Where-Object { $_.Status -ne 'OK' })
if ($BadResults.Count -gt 0) {
    Write-Host "`nErrors:"
    $BadResults | Format-Table VMName, Status, Error -AutoSize
}
$EndTime = Get-Date
Write-Host "`nSCRIPT FINISHED - Run ID: $RunId" -ForegroundColor Green
Write-Host "End time: $($EndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "Duration: $([math]::Round(($EndTime - $StartTime).TotalSeconds, 1)) seconds"

