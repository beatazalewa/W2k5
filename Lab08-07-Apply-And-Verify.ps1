# ==========================================================
# LAB 8 - Script 07 - Apply and Verify Group Policies
#
# Run ONLY on the Hyper-V host as Administrator.
# Requires Windows PowerShell 5.1.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
# Workstation: SEA-CL1
# User: CONTOSO\ewa.kaczmarek
#
# GPOs:
#   LAB08-Desktop-Finance
#   LAB08-System-Workstations
#   LAB08-Security-Workstations
#
# Tasks:
#   Verify domain password and lockout policies
#   Verify GPO settings and OU links
#   Refresh client computer policies
#   Verify computer RSoP using gpresult XML
#   Verify effective registry settings
#   Verify firewall through ActiveStore
#   Attempt user RSoP verification
#   Export CSV, TXT and HTML reports
#
# No GPO is created, edited or deleted.
# No passwords are changed.
# No user accounts are deliberately locked.
# No VM checkpoints are created.
# ==========================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$HostName = $env:COMPUTERNAME

$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'
$ClientName = 'SEA-CL1'
$TestUser = 'CONTOSO\ewa.kaczmarek'

$DesktopGPO = 'LAB08-Desktop-Finance'
$SystemGPO = 'LAB08-System-Workstations'
$SecurityGPO = 'LAB08-Security-Workstations'

$FinanceOU = (
    'OU=Uzytkownicy,OU=Finanse,' +
    'OU=Centrala,DC=contoso,DC=com'
)

$WorkstationOU = (
    'OU=Stacje robocze,' +
    'OU=Centrala,DC=contoso,DC=com'
)

$ReportDir = 'C:\LabReports'
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $ReportDir (
    "LAB08-Apply-And-Verify_$Timestamp.csv"
)

$TXT = Join-Path $ReportDir (
    "LAB08-Apply-And-Verify_$Timestamp.txt"
)

$HTML = Join-Path $ReportDir (
    "LAB08-Apply-And-Verify_$Timestamp.html"
)

$Checks = New-Object 'System.Collections.Generic.List[object]'

# ----------------------------------------------------------
# 2. Host reporting helper
# ----------------------------------------------------------

function Add-LabCheck {
    param(
        [string]$Area,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [ValidateSet('PASS','FAIL','REVIEW')]
        [string]$Status
    )

    $Checks.Add([PSCustomObject]@{
        Area = $Area
        Check = $Check
        Expected = $Expected
        Actual = $Actual
        Status = $Status
    })
}

# ----------------------------------------------------------
# 3. Host precheck
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - APPLY AND VERIFY"
Write-Host "=========================================="
Write-Host ""
Write-Host "Host: $HostName"
Write-Host "Domain: $DomainName"
Write-Host "DC: $DCName"
Write-Host "Client: $ClientName"
Write-Host "User: $TestUser"
Write-Host ""

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = New-Object `
    Security.Principal.WindowsPrincipal `
    -ArgumentList $Identity

if (-not $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    throw 'Run Windows PowerShell as Administrator.'
}

Import-Module Hyper-V -ErrorAction Stop

foreach ($Name in @($DCName, $ClientName)) {
    $VM = Get-VM -Name $Name -ErrorAction Stop

    if ([string]$VM.State -ne 'Running') {
        throw "Required VM is not running: $Name"
    }
}

New-Item -Path $ReportDir `
    -ItemType Directory -Force | Out-Null

# ----------------------------------------------------------
# 4. Credentials and PowerShell Direct sessions
# ----------------------------------------------------------

$CredentialParameters = @{
    UserName = 'CONTOSO\Administrator'
    Message = 'Enter domain Administrator password'
}

$Credential = Get-Credential @CredentialParameters

if ($null -eq $Credential) {
    throw 'Credentials were not supplied.'
}

$DCSession = $null
$ClientSession = $null
$DCData = @()
$ClientData = @()

try {
    $DCSession = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    $ClientSession = New-PSSession `
        -VMName $ClientName `
        -Credential $Credential `
        -ErrorAction Stop

    # ------------------------------------------------------
    # 5. Verify domain configuration on SEA-DC1
    # ------------------------------------------------------

    Write-Host "Checking Active Directory and GPO settings..."

    $DCData = @(
        Invoke-Command -Session $DCSession -ArgumentList @(
            $DomainName,
            $FinanceOU,
            $WorkstationOU,
            $TestUser,
            $DesktopGPO,
            $SystemGPO,
            $SecurityGPO
        ) -ScriptBlock {

            param(
                [string]$DomainName,
                [string]$FinanceOU,
                [string]$WorkstationOU,
                [string]$TestUser,
                [string]$DesktopGPO,
                [string]$SystemGPO,
                [string]$SecurityGPO
            )

            $ErrorActionPreference = 'Stop'

            Import-Module ActiveDirectory
            Import-Module GroupPolicy

            $Domain = Get-ADDomain -ErrorAction Stop

            if ($Domain.DNSRoot -ine $DomainName) {
                throw "Unexpected domain: $($Domain.DNSRoot)"
            }

            $Policy = Get-ADDefaultDomainPasswordPolicy `
                -Identity $DomainName

            # Return individual domain policy checks.
            $DomainTests = @(
                @{
                    Name = 'Minimum password length'
                    Expected = '12'
                    Actual = [string]$Policy.MinPasswordLength
                    OK = ($Policy.MinPasswordLength -eq 12)
                }
                @{
                    Name = 'Password history'
                    Expected = '24'
                    Actual = [string]$Policy.PasswordHistoryCount
                    OK = ($Policy.PasswordHistoryCount -eq 24)
                }
                @{
                    Name = 'Password complexity'
                    Expected = 'True'
                    Actual = [string]$Policy.ComplexityEnabled
                    OK = ($Policy.ComplexityEnabled -eq $true)
                }
                @{
                    Name = 'Lockout threshold'
                    Expected = '5'
                    Actual = [string]$Policy.LockoutThreshold
                    OK = ($Policy.LockoutThreshold -eq 5)
                }
                @{
                    Name = 'Lockout duration'
                    Expected = '15 minutes'
                    Actual = "$($Policy.LockoutDuration.TotalMinutes) minutes"
                    OK = ($Policy.LockoutDuration.TotalMinutes -eq 15)
                }
                @{
                    Name = 'Lockout reset interval'
                    Expected = '15 minutes'
                    Actual = "$($Policy.LockoutObservationWindow.TotalMinutes) minutes"
                    OK = ($Policy.LockoutObservationWindow.TotalMinutes -eq 15)
                }
            )

            foreach ($Test in $DomainTests) {
                [PSCustomObject]@{
                    RecordType = 'CHECK'
                    Area = 'Domain account policy'
                    Name = [string]$Test.Name
                    Expected = [string]$Test.Expected
                    Actual = [string]$Test.Actual
                    Status = if ($Test.OK) { 'PASS' } else { 'FAIL' }
                }
            }

            # Verify that all expected GPOs exist and
            # have direct links to their intended OUs.
            $Definitions = @(
                @{
                    Name = $DesktopGPO
                    OU = $FinanceOU
                }
                @{
                    Name = $SystemGPO
                    OU = $WorkstationOU
                }
                @{
                    Name = $SecurityGPO
                    OU = $WorkstationOU
                }
            )

            foreach ($Definition in $Definitions) {

                $GPO = Get-GPO -Name $Definition.Name `
                    -Domain $DomainName -ErrorAction Stop

                $Inheritance = Get-GPInheritance `
                    -Target $Definition.OU `
                    -Domain $DomainName -ErrorAction Stop

                $Links = @(
                    $Inheritance.GpoLinks |
                    Where-Object {
                        [string]$_.GpoId -eq [string]$GPO.Id
                    }
                )

                $Linked = (
                    $Links.Count -eq 1 -and
                    [string]$Links[0].Enabled -in @('Yes','True')
                )

                [PSCustomObject]@{
                    RecordType = 'CHECK'
                    Area = 'GPO links'
                    Name = $Definition.Name
                    Expected = 'Direct link enabled'
                    Actual = [string]$Linked
                    Status = if ($Linked) { 'PASS' } else { 'FAIL' }
                }
            }

            # Verify workstation and user OU membership.
            $Computer = Get-ADComputer -Identity 'SEA-CL1'

            $ComputerParent = (
                $Computer.DistinguishedName -split ',', 2
            )[1]

            [PSCustomObject]@{
                RecordType = 'CHECK'
                Area = 'Active Directory objects'
                Name = 'SEA-CL1 OU membership'
                Expected = $WorkstationOU
                Actual = $ComputerParent
                Status = if ($ComputerParent -ieq $WorkstationOU) {
                    'PASS'
                } else { 'FAIL' }
            }

            $SamAccountName = ($TestUser -split '\\')[-1]
            $User = Get-ADUser -Identity $SamAccountName

            $UserParent = (
                $User.DistinguishedName -split ',', 2
            )[1]

            [PSCustomObject]@{
                RecordType = 'CHECK'
                Area = 'Active Directory objects'
                Name = 'Finance user OU membership'
                Expected = $FinanceOU
                Actual = $UserParent
                Status = if ($UserParent -ieq $FinanceOU) {
                    'PASS'
                } else { 'FAIL' }
            }

            # Verify the two desktop settings in the GPO.
            $ExplorerKey = (
                'HKCU\Software\Microsoft\Windows\' +
                'CurrentVersion\Policies\Explorer'
            )

            $Desktop = Get-GPO -Name $DesktopGPO `
                -Domain $DomainName

            foreach ($Item in @(
                @{ Name = 'NoControlPanel'; Expected = 1 },
                @{ Name = 'NoRun'; Expected = 1 }
            )) {

                $Value = Get-GPRegistryValue `
                    -Guid $Desktop.Id `
                    -Domain $DomainName `
                    -Key $ExplorerKey `
                    -ValueName $Item.Name `
                    -ErrorAction Stop

                [PSCustomObject]@{
                    RecordType = 'CHECK'
                    Area = 'Desktop GPO configuration'
                    Name = $Item.Name
                    Expected = "DWORD $($Item.Expected)"
                    Actual = "DWORD $($Value.Value)"
                    Status = if (
                        [int]$Value.Value -eq $Item.Expected -and
                        [string]$Value.Type -eq 'DWord'
                    ) { 'PASS' } else { 'FAIL' }
                }
            }

            # Verify workstation system and security
            # registry settings directly in the GPOs.
            $AU = (
                'HKLM\Software\Policies\Microsoft\' +
                'Windows\WindowsUpdate\AU'
            )

            $Cloud = (
                'HKLM\Software\Policies\Microsoft\' +
                'Windows\CloudContent'
            )

            $Sys = (
                'HKLM\Software\Microsoft\Windows\' +
                'CurrentVersion\Policies\System'
            )

            $FW = (
                'HKLM\Software\Policies\Microsoft\' +
                'WindowsFirewall\DomainProfile'
            )

            $Definitions = @(
                @{ GPO=$SystemGPO; Name='NoAutoUpdate'; Key=$AU; Value=0 }
                @{ GPO=$SystemGPO; Name='AUOptions'; Key=$AU; Value=2 }
                @{ GPO=$SystemGPO; Name='NoAutoRebootWithLoggedOnUsers'; Key=$AU; Value=1 }
                @{ GPO=$SystemGPO; Name='DisableWindowsConsumerFeatures'; Key=$Cloud; Value=1 }
                @{ GPO=$SystemGPO; Name='EnableFirstLogonAnimation'; Key=$Sys; Value=0 }
                @{ GPO=$SecurityGPO; Name='EnableFirewall'; Key=$FW; Value=1 }
                @{ GPO=$SecurityGPO; Name='DefaultInboundAction'; Key=$FW; Value=1 }
                @{ GPO=$SecurityGPO; Name='DefaultOutboundAction'; Key=$FW; Value=0 }
                @{ GPO=$SecurityGPO; Name='DisableNotifications'; Key=$FW; Value=0 }
                @{ GPO=$SecurityGPO; Name='ConsentPromptBehaviorAdmin'; Key=$Sys; Value=5 }
                @{ GPO=$SecurityGPO; Name='PromptOnSecureDesktop'; Key=$Sys; Value=1 }
            )

            foreach ($Definition in $Definitions) {

                $GPO = Get-GPO -Name $Definition.GPO `
                    -Domain $DomainName

                $Value = Get-GPRegistryValue `
                    -Guid $GPO.Id `
                    -Domain $DomainName `
                    -Key $Definition.Key `
                    -ValueName $Definition.Name `
                    -ErrorAction Stop

                [PSCustomObject]@{
                    RecordType = 'CHECK'
                    Area = "$($Definition.GPO) configuration"
                    Name = $Definition.Name
                    Expected = "DWORD $($Definition.Value)"
                    Actual = "DWORD $($Value.Value)"
                    Status = if (
                        [int]$Value.Value -eq $Definition.Value -and
                        [string]$Value.Type -eq 'DWord'
                    ) { 'PASS' } else { 'FAIL' }
                }
            }
        } -ErrorAction Stop
    )

    # ------------------------------------------------------
    # 6. Verify actual client configuration on SEA-CL1
    # ------------------------------------------------------

    Write-Host "Refreshing and verifying SEA-CL1 policies..."

    $ClientData = @(
        Invoke-Command -Session $ClientSession -ArgumentList @(
            $SystemGPO,
            $SecurityGPO,
            $TestUser,
            $DesktopGPO
        ) -ScriptBlock {

            param(
                [string]$SystemGPO,
                [string]$SecurityGPO,
                [string]$TestUser,
                [string]$DesktopGPO
            )

            $ErrorActionPreference = 'Stop'

            function Emit-ClientCheck {
                param(
                    [string]$Area,
                    [string]$Name,
                    [string]$Expected,
                    [string]$Actual,
                    [string]$Status
                )

                [PSCustomObject]@{
                    RecordType = 'CHECK'
                    Area = $Area
                    Name = $Name
                    Expected = $Expected
                    Actual = $Actual
                    Status = $Status
                }
            }

            # ----------------------------------------------
            # 6A. Refresh computer policies
            # ----------------------------------------------

            $UpdateText = (
                & gpupdate.exe /target:computer /force 2>&1 |
                Out-String
            )

            $UpdateCode = $LASTEXITCODE

            Emit-ClientCheck 'Client Group Policy' `
                'gpupdate computer' 'Exit code 0' `
                ([string]$UpdateCode) `
                $(if ($UpdateCode -eq 0) { 'PASS' } else { 'FAIL' })

            [PSCustomObject]@{
                RecordType = 'DIAGNOSTIC'
                Name = 'gpupdate output'
                Text = $UpdateText
            }

            # ----------------------------------------------
            # 6B. Verify computer gpresult
            # ----------------------------------------------

            $ComputerXML = Join-Path $env:TEMP (
                'LAB08-07-Computer-' +
                [guid]::NewGuid().ToString('N') + '.xml'
            )

            try {
                $ComputerText = (
                    & gpresult.exe /scope computer /r 2>&1 |
                    Out-String
                )

                $TextExitCode = $LASTEXITCODE

                $XMLOutput = (
                    & gpresult.exe /scope computer `
                        /x $ComputerXML /f 2>&1 |
                    Out-String
                )

                $XMLExitCode = $LASTEXITCODE

                Emit-ClientCheck 'Client Group Policy' `
                    'gpresult computer' 'Exit code 0' `
                    ([string]$TextExitCode) `
                    $(if ($TextExitCode -eq 0) {
                        'PASS'
                    } else { 'FAIL' })

                [PSCustomObject]@{
                    RecordType = 'DIAGNOSTIC'
                    Name = 'gpresult computer'
                    Text = $ComputerText
                }

                if (
                    $XMLExitCode -eq 0 -and
                    (Test-Path -LiteralPath $ComputerXML)
                ) {
                    [xml]$XML = Get-Content `
                        -LiteralPath $ComputerXML -Raw

                    $Nodes = @(
                        $XML.SelectNodes(
                            "//*[local-name()='ComputerResults']" +
                            "//*[local-name()='GPO']"
                        )
                    )

                    foreach ($ExpectedName in @(
                        $SystemGPO,
                        $SecurityGPO
                    )) {

                        $Applied = $false

                        foreach ($Node in $Nodes) {
                            $NameNode = $Node.SelectSingleNode(
                                "./*[local-name()='Name']"
                            )

                            $FilterNode = $Node.SelectSingleNode(
                                "./*[local-name()='FilterAllowed']"
                            )

                            $EnabledNode = $Node.SelectSingleNode(
                                "./*[local-name()='Enabled']"
                            )

                            if (
                                $null -ne $NameNode -and
                                $NameNode.InnerText -eq $ExpectedName -and
                                $null -ne $FilterNode -and
                                $FilterNode.InnerText -eq 'true' -and
                                (
                                    $null -eq $EnabledNode -or
                                    $EnabledNode.InnerText -eq 'true'
                                )
                            ) {
                                $Applied = $true
                            }
                        }

                        Emit-ClientCheck 'Applied computer GPOs' `
                            $ExpectedName 'True' `
                            ([string]$Applied) `
                            $(if ($Applied) {
                                'PASS'
                            } else { 'FAIL' })
                    }
                }
                else {
                    foreach ($ExpectedName in @(
                        $SystemGPO,
                        $SecurityGPO
                    )) {
                        Emit-ClientCheck 'Applied computer GPOs' `
                            $ExpectedName 'True' `
                            'RSoP XML unavailable' 'REVIEW'
                    }
                }
            }
            finally {
                Remove-Item -LiteralPath $ComputerXML `
                    -Force -ErrorAction SilentlyContinue
            }

            # ----------------------------------------------
            # 6C. Verify client machine registry values
            # ----------------------------------------------

            $AU = (
                'HKLM:\Software\Policies\Microsoft\' +
                'Windows\WindowsUpdate\AU'
            )

            $Cloud = (
                'HKLM:\Software\Policies\Microsoft\' +
                'Windows\CloudContent'
            )

            $Sys = (
                'HKLM:\Software\Microsoft\Windows\' +
                'CurrentVersion\Policies\System'
            )

            $FW = (
                'HKLM:\Software\Policies\Microsoft\' +
                'WindowsFirewall\DomainProfile'
            )

            $Settings = @(
                @{ Name='NoAutoUpdate'; Path=$AU; Value=0 }
                @{ Name='AUOptions'; Path=$AU; Value=2 }
                @{ Name='NoAutoRebootWithLoggedOnUsers'; Path=$AU; Value=1 }
                @{ Name='DisableWindowsConsumerFeatures'; Path=$Cloud; Value=1 }
                @{ Name='EnableFirstLogonAnimation'; Path=$Sys; Value=0 }
                @{ Name='EnableFirewall'; Path=$FW; Value=1 }
                @{ Name='DefaultInboundAction'; Path=$FW; Value=1 }
                @{ Name='DefaultOutboundAction'; Path=$FW; Value=0 }
                @{ Name='DisableNotifications'; Path=$FW; Value=0 }
                @{ Name='ConsentPromptBehaviorAdmin'; Path=$Sys; Value=5 }
                @{ Name='PromptOnSecureDesktop'; Path=$Sys; Value=1 }
            )

            foreach ($Setting in $Settings) {

                $Actual = $null
                $Details = ''

                try {
                    $Actual = (Get-ItemProperty `
                        -Path $Setting.Path `
                        -Name $Setting.Name `
                        -ErrorAction Stop).($Setting.Name)
                }
                catch {
                    $Details = $_.Exception.Message
                }

                $OK = (
                    $null -ne $Actual -and
                    [int]$Actual -eq [int]$Setting.Value
                )

                $ActualText = if ($null -ne $Actual) {
                    "DWORD $Actual"
                }
                else {
                    "Missing: $Details"
                }

                Emit-ClientCheck 'Client registry' `
                    $Setting.Name `
                    "DWORD $($Setting.Value)" `
                    $ActualText `
                    $(if ($OK) { 'PASS' } else { 'FAIL' })
            }

            # ----------------------------------------------
            # 6D. Verify effective firewall configuration
            # ----------------------------------------------

            try {
                $Firewall = Get-NetFirewallProfile `
                    -PolicyStore ActiveStore `
                    -Name Domain `
                    -ErrorAction Stop

                $FirewallTests = @(
                    @{
                        Name = 'Domain firewall enabled'
                        Expected = 'True'
                        Actual = [string]$Firewall.Enabled
                    }
                    @{
                        Name = 'Default inbound action'
                        Expected = 'Block'
                        Actual = [string]$Firewall.DefaultInboundAction
                    }
                    @{
                        Name = 'Default outbound action'
                        Expected = 'Allow'
                        Actual = [string]$Firewall.DefaultOutboundAction
                    }
                )

                foreach ($Test in $FirewallTests) {
                    Emit-ClientCheck 'Effective firewall' `
                        $Test.Name $Test.Expected $Test.Actual `
                        $(if ($Test.Expected -eq $Test.Actual) {
                            'PASS'
                        } else { 'FAIL' })
                }
            }
            catch {
                Emit-ClientCheck 'Effective firewall' `
                    'ActiveStore query' 'Successful' `
                    $_.Exception.Message 'FAIL'
            }

            # ----------------------------------------------
            # 6E. Attempt user-side RSoP verification
            # ----------------------------------------------

            # User RSoP requires available user session data.
            # Do not treat missing session data as a failed GPO.

            $UserXML = Join-Path $env:TEMP (
                'LAB08-07-User-' +
                [guid]::NewGuid().ToString('N') + '.xml'
            )

            try {
                $UserText = (
                    & gpresult.exe /user $TestUser `
                        /scope user /r 2>&1 |
                    Out-String
                )

                $UserTextCode = $LASTEXITCODE

                [PSCustomObject]@{
                    RecordType = 'DIAGNOSTIC'
                    Name = 'gpresult finance user'
                    Text = $UserText
                }

                $UserXMLOutput = (
                    & gpresult.exe /user $TestUser `
                        /scope user /x $UserXML /f 2>&1 |
                    Out-String
                )

                $UserXMLCode = $LASTEXITCODE
                $UserApplied = $false
                $UserRSoPAvailable = $false

                if (
                    $UserXMLCode -eq 0 -and
                    (Test-Path -LiteralPath $UserXML)
                ) {
                    [xml]$UserDocument = Get-Content `
                        -LiteralPath $UserXML -Raw

                    $UserNodes = @(
                        $UserDocument.SelectNodes(
                            "//*[local-name()='UserResults']" +
                            "//*[local-name()='GPO']"
                        )
                    )

                    $UserRSoPAvailable = $true

                    foreach ($Node in $UserNodes) {
                        $NameNode = $Node.SelectSingleNode(
                            "./*[local-name()='Name']"
                        )

                        $FilterNode = $Node.SelectSingleNode(
                            "./*[local-name()='FilterAllowed']"
                        )

                        $EnabledNode = $Node.SelectSingleNode(
                            "./*[local-name()='Enabled']"
                        )

                        if (
                            $null -ne $NameNode -and
                            $NameNode.InnerText -eq $DesktopGPO -and
                            $null -ne $FilterNode -and
                            $FilterNode.InnerText -eq 'true' -and
                            (
                                $null -eq $EnabledNode -or
                                $EnabledNode.InnerText -eq 'true'
                            )
                        ) {
                            $UserApplied = $true
                        }
                    }
                }

                $UserStatus = if (-not $UserRSoPAvailable) {
                    'REVIEW'
                }
                elseif ($UserApplied) {
                    'PASS'
                }
                else {
                    'FAIL'
                }

                Emit-ClientCheck 'Applied user GPOs' `
                    $DesktopGPO 'True' `
                    $(if ($UserRSoPAvailable) {
                        [string]$UserApplied
                    } else {
                        'User RSoP unavailable'
                    }) $UserStatus

            }
            finally {
                Remove-Item -LiteralPath $UserXML `
                    -Force -ErrorAction SilentlyContinue
            }

        } -ErrorAction Stop
    )

}
finally {
    if ($null -ne $ClientSession) {
        Remove-PSSession $ClientSession `
            -ErrorAction SilentlyContinue
    }

    if ($null -ne $DCSession) {
        Remove-PSSession $DCSession `
            -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------
# 7. Validate and combine flat result records
# ----------------------------------------------------------

$DCChecks = @(
    $DCData | Where-Object RecordType -eq 'CHECK'
)

$ClientChecks = @(
    $ClientData | Where-Object RecordType -eq 'CHECK'
)

$Diagnostics = @(
    $ClientData | Where-Object RecordType -eq 'DIAGNOSTIC'
)

$ExpectedDCChecks = 24
$ExpectedClientChecks = 19

if ($DCChecks.Count -ne $ExpectedDCChecks) {
    throw (
        "Expected $ExpectedDCChecks DC checks; " +
        "received $($DCChecks.Count)."
    )
}

if ($ClientChecks.Count -ne $ExpectedClientChecks) {
    throw (
        "Expected $ExpectedClientChecks client checks; " +
        "received $($ClientChecks.Count)."
    )
}

foreach ($Item in @($DCChecks) + @($ClientChecks)) {
    Add-LabCheck `
        -Area ([string]$Item.Area) `
        -Check ([string]$Item.Name) `
        -Expected ([string]$Item.Expected) `
        -Actual ([string]$Item.Actual) `
        -Status ([string]$Item.Status)
}

# ----------------------------------------------------------
# 8. Calculate statistics
# ----------------------------------------------------------

$Passed = @($Checks | Where-Object Status -eq 'PASS').Count
$Failed = @($Checks | Where-Object Status -eq 'FAIL').Count
$Review = @($Checks | Where-Object Status -eq 'REVIEW').Count
$Total = $Checks.Count

# ----------------------------------------------------------
# 9. Export CSV
# ----------------------------------------------------------

$Checks | Export-Csv `
    -Path $CSV `
    -NoTypeInformation `
    -Encoding UTF8

# ----------------------------------------------------------
# 10. Generate TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 8 - SCRIPT 07 - APPLY AND VERIFY
============================================================

Host: $HostName
Domain: $DomainName
Domain controller: $DCName
Client: $ClientName
Finance user: $TestUser

Date: $(Get-Date)

Expected GPOs:
$DesktopGPO
$SystemGPO
$SecurityGPO

TOTAL CHECKS: $Total
PASS: $Passed
FAIL: $Failed
REVIEW: $Review

============================================================
VERIFICATION RESULTS
============================================================

"@

$CheckText = $Checks |
    Format-Table Area,Check,Expected,Actual,Status -AutoSize |
    Out-String -Width 260

$DiagnosticText = foreach ($Item in $Diagnostics) {
    "============================================================"
    "DIAGNOSTIC: $($Item.Name)"
    "============================================================"
    [string]$Item.Text
    ""
}

$FullReport = (
    $Header +
    $CheckText +
    "`r`n" +
    ($DiagnosticText -join "`r`n")
)

$FullReport | Out-File `
    -FilePath $TXT `
    -Encoding UTF8

# ----------------------------------------------------------
# 11. Generate HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    background: #f5f9fb;
    color: #294554;
    padding: 28px;
}
h1, h2 { color: #146393; }
table {
    border-collapse: collapse;
    width: 100%;
    background: #ffffff;
}
th {
    background: #146393;
    color: #ffffff;
    text-align: left;
    padding: 9px;
}
td {
    border: 1px solid #dce6eb;
    padding: 8px;
}
tr:nth-child(even) { background: #f5f9fb; }
</style>
"@

$Intro = @"
<h1>LAB 8 - Apply and Verify</h1>
<p><strong>Host:</strong> $HostName</p>
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>Client:</strong> $ClientName</p>
<p><strong>PASS:</strong> $Passed</p>
<p><strong>FAIL:</strong> $Failed</p>
<p><strong>REVIEW:</strong> $Review</p>
<h2>Verification results</h2>
"@

$Checks | ConvertTo-Html `
    -Title 'LAB 8 - Apply and Verify' `
    -Head $CSS `
    -PreContent $Intro |
    Out-File -FilePath $HTML -Encoding UTF8

# ----------------------------------------------------------
# 12. Display final results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 8 - APPLY AND VERIFY RESULTS"
Write-Host "=========================================="
Write-Host ""

$Checks |
    Format-Table Area,Check,Expected,Actual,Status -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Total: $Total"
Write-Host "PASS: $Passed" -ForegroundColor Green
Write-Host "FAIL: $Failed" -ForegroundColor Red
Write-Host "REVIEW: $Review" -ForegroundColor Yellow

Write-Host ""
Write-Host "Reports on $HostName :"
Write-Host "CSV: $CSV"
Write-Host "TXT: $TXT"
Write-Host "HTML: $HTML"

# ----------------------------------------------------------
# 13. Final outcome
# ----------------------------------------------------------

if ($Failed -gt 0) {
    throw 'LAB08-07 failed. Review the TXT report.'
}

if ($Review -gt 0) {
    Write-Warning (
        "LAB08-07 has items requiring review. " +
        "Check the Finance user RSoP section."
    )
}
else {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 8 - ALL GROUP POLICIES VERIFIED"
    Write-Host "==========================================" `
        -ForegroundColor Green
}
