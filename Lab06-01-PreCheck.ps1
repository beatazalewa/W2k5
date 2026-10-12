# ==========================================================
# LAB 6 - Script 01 - Host and Domain Readiness Check
#
# Run on Phost in elevated Windows PowerShell 5.1.
#
# Required virtual machines:
#   SEA-DC1
#   SEA-SRV1
#   SEA-SRV2
#   SEA-CL1
#
# Domain: contoso.com
# Network: LabSwitch
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
    'SEA-DC1'
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

$ReportDir = 'C:\LabReports'

New-Item `
    -ItemType Directory `
    -Path $ReportDir `
    -Force | Out-Null

$Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$Csv = Join-Path `
    $ReportDir `
    "LAB06-PreCheck_$Stamp.csv"

# ----------------------------------------------------------
# 3. Verify Hyper-V virtual machines
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - HYPER-V READINESS"
Write-Host "=========================================="
Write-Host ""

$Rows = foreach ($Name in $VMNames) {

    $VM = Get-VM `
        -Name $Name `
        -ErrorAction SilentlyContinue

    $Adapters = if ($null -ne $VM) {

        @(
            Get-VMNetworkAdapter `
                -VMName $Name `
                -ErrorAction SilentlyContinue
        )

    }
    else {
        @()
    }

    $SwitchOK = @(
        $Adapters | Where-Object {
            $_.SwitchName -eq 'LabSwitch'
        }
    ).Count -gt 0

    $Running = (
        $null -ne $VM -and
        [string]$VM.State -eq 'Running'
    )

    [PSCustomObject]@{
        VM        = $Name
        Exists    = ($null -ne $VM)
        Running   = $Running
        LabSwitch = $SwitchOK

        Status = if ($Running -and $SwitchOK) {
            'PASS'
        }
        else {
            'FAIL'
        }
    }
}

# ----------------------------------------------------------
# 4. Display and export Hyper-V results
# ----------------------------------------------------------

$Rows |
    Format-Table -AutoSize |
    Out-Host

$Rows |
    Export-Csv `
        -Path $Csv `
        -Encoding UTF8 `
        -NoTypeInformation

Write-Host ""
Write-Host "Report: $Csv"

$FailedVMs = @(
    $Rows | Where-Object {
        $_.Status -eq 'FAIL'
    }
).Count

if ($FailedVMs -gt 0) {

    throw 'Required Hyper-V prerequisites failed.'
}

# ----------------------------------------------------------
# 5. Verify domain controller and DNS readiness
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 6 - DOMAIN CONTROLLER AND DNS READINESS"
Write-Host "=========================================="
Write-Host ""

$Admin = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter SEA-DC1 domain Administrator password'

$Session = $null

try {

    # ------------------------------------------------------
    # 6. Connect to SEA-DC1 using PowerShell Direct
    # ------------------------------------------------------

    $Session = New-PSSession `
        -VMName 'SEA-DC1' `
        -Credential $Admin `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 7. Run checks inside the domain controller
    # ------------------------------------------------------

    $DC = Invoke-Command `
        -Session $Session `
        -ScriptBlock {

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory `
                -ErrorAction Stop

            # Get Active Directory domain information
            $Domain = Get-ADDomain `
                -ErrorAction Stop

            # Verify DNS A record
            $DnsAnswers = @(
                Resolve-DnsName `
                    -Name 'SEA-DC1.contoso.com' `
                    -Type A `
                    -Server '10.10.10.10' `
                    -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress -eq '10.10.10.10'
                }
            )

            # Read service statuses as strings
            $NtdsStatus = [string](
                Get-Service `
                    -Name 'NTDS' `
                    -ErrorAction Stop
            ).Status

            $DnsStatus = [string](
                Get-Service `
                    -Name 'DNS' `
                    -ErrorAction Stop
            ).Status

            # Calculate checks inside the guest
            $DomainOK = (
                [string]$Domain.DNSRoot -eq 'contoso.com'
            )

            $DnsAOK = (
                $DnsAnswers.Count -gt 0
            )

            $NtdsOK = (
                $NtdsStatus -eq 'Running'
            )

            $DnsServiceOK = (
                $DnsStatus -eq 'Running'
            )

            $Ready = (
                $DomainOK -and
                $DnsAOK -and
                $NtdsOK -and
                $DnsServiceOK
            )

            # Return serializable results to the host
            [PSCustomObject]@{
                Domain         = [string]$Domain.DNSRoot
                DNS_A_OK       = [bool]$DnsAOK
                NTDS           = $NtdsStatus
                DNS            = $DnsStatus
                DomainOK       = [bool]$DomainOK
                NTDS_OK        = [bool]$NtdsOK
                DNS_Service_OK = [bool]$DnsServiceOK
                Ready          = [bool]$Ready
            }

        } `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 8. Display domain controller results
    # ------------------------------------------------------

    Write-Host ""
    Write-Host "DOMAIN CONTROLLER VERIFICATION"
    Write-Host ""

    $DC |
        Format-List `
            Domain,
            DNS_A_OK,
            NTDS,
            DNS,
            DomainOK,
            NTDS_OK,
            DNS_Service_OK,
            Ready |
        Out-Host

    # ------------------------------------------------------
    # 9. Validate final result
    # ------------------------------------------------------

    if (-not $DC.Ready) {

        throw (
            'Domain controller or DNS readiness check ' +
            'failed. Review the individual values above.'
        )
    }

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 6 - PRECHECK PASSED"
    Write-Host "==========================================" `
        -ForegroundColor Green

}
finally {

    # ------------------------------------------------------
    # 10. Close PowerShell Direct session
    # ------------------------------------------------------

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}
