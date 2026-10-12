# =====================================================
# LAB 1 Script 1b - Rename Windows computers inside Hyper-V VMs
# Run on the Hyper-V host as Administrator
# =====================================================

$ErrorActionPreference = 'Stop'

$VMNames = @(
    'SEA-DC1',
    'SEA-SRV1',
    'SEA-SRV2'
)

$Results = foreach ($VMName in $VMNames) {

    $Session = $null

    try {
        Write-Host ""
        Write-Host "Processing $VMName" -ForegroundColor Cyan

        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ($VM.State -ne 'Running') {
            throw "$VMName is not running."
        }

        # Ask for credentials for this VM
        $Credential = Get-Credential `
            -Message "Credentials for $VMName"

        # Establish PowerShell Direct session
        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Rename Windows inside the virtual machine
        $Result = Invoke-Command `
            -Session $Session `
            -ArgumentList $VMName `
            -ScriptBlock {
                param($NewName)

                $OldName = $env:COMPUTERNAME

                if ($OldName -ne $NewName) {

                    Rename-Computer `
                        -NewName $NewName `
                        -Force `
                        -ErrorAction Stop

                    [PSCustomObject]@{
                        OldName = $OldName
                        NewName = $NewName
                        RebootRequired = $true
                    }
                }
                else {
                    [PSCustomObject]@{
                        OldName = $OldName
                        NewName = $NewName
                        RebootRequired = $false
                    }
                }
            } `
            -ErrorAction Stop

        Write-Host "$($Result.OldName) -> $($Result.NewName)" `
            -ForegroundColor Green

        [PSCustomObject]@{
            VMName = $VMName
            OldName = $Result.OldName
            NewName = $Result.NewName
            RebootRequired = $Result.RebootRequired
            Status = 'OK'
        }
    }
    catch {
        Write-Warning "${VMName}: $($_.Exception.Message)"

        [PSCustomObject]@{
            VMName = $VMName
            OldName = ''
            NewName = ''
            RebootRequired = $false
            Status = 'FAILED'
        }
    }
    finally {
        if ($Session) {
            Remove-PSSession $Session
        }
    }
}

$Results | Format-Table -AutoSize
