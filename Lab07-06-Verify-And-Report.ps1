# ==========================================================
# LAB 7 - Script 06 - Verify and Report
#
# Run ONLY on host as Administrator.
# Windows PowerShell 5.1 and Hyper-V required.
#
# Domain: contoso.com
# DNS / KDC: SEA-DC1 - 10.10.10.10
#
# Machines:
#   SEA-DC1  - Domain Controller
#   SEA-SRV1 - Member Server
#   SEA-SRV2 - Member Server
#   SEA-CL1  - Domain Client
#
# Final verification:
#   Hyper-V state and network
#   Domain membership
#   DNS and KDC discovery
#   Domain secure channels
#   Kerberos KDC and Windows Time
#   SMB TCP 445 connectivity
#   Active Directory user accounts
#   Security events: 4624, 4625, 4634,
#                    4768, 4769, 4771
#   Authentication activity and failures
#   Final PASS / FAIL / INFO / REVIEW
#
# Reports:
#   Checks CSV
#   Security events CSV
#   Event statistics CSV
#   Account statistics CSV
#   Collection status CSV
#   TXT summary
#   HTML summary
#
# Read-only script.
# No checkpoints are created.
# ==========================================================

[CmdletBinding()]
param(
    [ValidateRange(1, 168)]
    [int]$HoursBack = 8,

    [ValidateRange(100, 20000)]
    [int]$MaxEventsPerVM = 10000
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'
$DCAddress = '10.10.10.10'
$SwitchName = 'LabSwitch'

$ReportDir = 'C:\LabReports'

$Targets = @(
    [PSCustomObject]@{
        VM = 'SEA-DC1'
        IP = '10.10.10.10'
        Role = 'DC'
    }
    [PSCustomObject]@{
        VM = 'SEA-SRV1'
        IP = '10.10.10.20'
        Role = 'Member'
    }
    [PSCustomObject]@{
        VM = 'SEA-SRV2'
        IP = '10.10.10.30'
        Role = 'Member'
    }
    [PSCustomObject]@{
        VM = 'SEA-CL1'
        IP = '10.10.10.100'
        Role = 'Member'
    }
)

$SMBTests = @(
    [PSCustomObject]@{
        Source = 'SEA-CL1'
        Target = 'SEA-SRV1.contoso.com'
    }
    [PSCustomObject]@{
        Source = 'SEA-CL1'
        Target = 'SEA-SRV2.contoso.com'
    }
    [PSCustomObject]@{
        Source = 'SEA-SRV1'
        Target = 'SEA-SRV2.contoso.com'
    }
    [PSCustomObject]@{
        Source = 'SEA-SRV2'
        Target = 'SEA-SRV1.contoso.com'
    }
)

$TestUsers = @(
    [PSCustomObject]@{
        Login = 'anna.kowalska'
        ExpectedGroup = 'GG_IT_Users'
    }
    [PSCustomObject]@{
        Login = 'ewa.kaczmarek'
        ExpectedGroup = 'GG_Finance_Users'
    }
)

[int[]]$EventIDs = @(
    4624, 4625, 4634, 4768, 4769, 4771
)

$EventIDsText = $EventIDs -join ','

$EndTime = Get-Date
$StartTime = $EndTime.AddHours(-$HoursBack)

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

# ----------------------------------------------------------
# 2. Initialize host
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

New-Item `
    -Path $ReportDir `
    -ItemType Directory `
    -Force | Out-Null

$ChecksCSV = Join-Path $ReportDir `
    "LAB07-Final-Checks_$Timestamp.csv"

$EventsCSV = Join-Path $ReportDir `
    "LAB07-Final-Events_$Timestamp.csv"

$StatsCSV = Join-Path $ReportDir `
    "LAB07-Final-Event-Statistics_$Timestamp.csv"

$AccountsCSV = Join-Path $ReportDir `
    "LAB07-Final-Accounts_$Timestamp.csv"

$CollectionsCSV = Join-Path $ReportDir `
    "LAB07-Final-Collections_$Timestamp.csv"

$TXT = Join-Path $ReportDir `
    "LAB07-Final-Report_$Timestamp.txt"

$HTML = Join-Path $ReportDir `
    "LAB07-Final-Report_$Timestamp.html"

$Checks = [System.Collections.Generic.List[object]]::new()
$Events = [System.Collections.Generic.List[object]]::new()
$Collections = [System.Collections.Generic.List[object]]::new()
$ADUsers = [System.Collections.Generic.List[object]]::new()

# ----------------------------------------------------------
# 3. Helper functions
# ----------------------------------------------------------

function Add-Check {

    param(
        [string]$Machine,
        [string]$Category,
        [string]$Check,
        [string]$Expected,
        [string]$Actual,
        [ValidateSet('PASS','FAIL','INFO','REVIEW')]
        [string]$Status
    )

    $Checks.Add(
        [PSCustomObject]@{
            Machine = $Machine
            Category = $Category
            Check = $Check
            Expected = $Expected
            Actual = $Actual
            Status = $Status
        }
    )
}

function Export-LabCsv {

    param(
        [object[]]$Data,
        [string]$Path,
        [string[]]$Columns
    )

    if ($Data.Count -gt 0) {

        $Data |
            Select-Object -Property $Columns |
            Export-Csv `
                -Path $Path `
                -NoTypeInformation `
                -Encoding UTF8
    }
    else {

        $Header = (
            $Columns |
            ForEach-Object {
                '"' + ($_ -replace '"','""') + '"'
            }
        ) -join ','

        Set-Content `
            -Path $Path `
            -Value $Header `
            -Encoding UTF8
    }
}

function Get-EventCount {

    param(
        [object[]]$InputEvents,
        [int]$ID,
        [string]$Machine = ''
    )

    @(
        $InputEvents |
        Where-Object {
            $_.EventID -eq $ID -and
            (
                [string]::IsNullOrWhiteSpace($Machine) -or
                $_.Computer -eq $Machine
            )
        }
    ).Count
}

# ----------------------------------------------------------
# 4. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - FINAL VERIFICATION AND REPORT"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host "Machines: $($Targets.Count)"
Write-Host "Hours back: $HoursBack"
Write-Host "From: $StartTime"
Write-Host "To: $EndTime"
Write-Host ""

# ----------------------------------------------------------
# 5. Request credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 6. Verify Hyper-V infrastructure
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "STEP 1 - HYPER-V INFRASTRUCTURE"
Write-Host "=========================================="

foreach ($Target in $Targets) {

    $VMName = $Target.VM

    try {

        $VM = Get-VM `
            -Name $VMName `
            -ErrorAction Stop

        Add-Check `
            $VMName 'Hyper-V' 'VM exists' `
            'True' 'True' 'PASS'

        $Running = (
            [string]$VM.State -eq 'Running'
        )

        Add-Check `
            $VMName 'Hyper-V' 'VM running' `
            'True' ([string]$Running) `
            $(if ($Running) { 'PASS' } else { 'FAIL' })

        $Adapters = @(
            Get-VMNetworkAdapter `
                -VMName $VMName `
                -ErrorAction Stop
        )

        $SwitchOK = @(
            $Adapters |
            Where-Object SwitchName -eq $SwitchName
        ).Count -gt 0

        Add-Check `
            $VMName 'Hyper-V' 'LabSwitch connected' `
            $SwitchName `
            (($Adapters.SwitchName) -join ',') `
            $(if ($SwitchOK) { 'PASS' } else { 'FAIL' })

    }
    catch {

        Add-Check `
            $VMName 'Hyper-V' 'VM availability' `
            'Available' `
            $_.Exception.Message `
            'FAIL'
    }
}

# ----------------------------------------------------------
# 7. Verify guest infrastructure
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "STEP 2 - DOMAIN AND KERBEROS"
Write-Host "=========================================="

foreach ($Target in $Targets) {

    $VMName = $Target.VM
    $Session = $null

    Write-Host ""
    Write-Host "Checking $VMName ..."

    try {

        $VM = Get-VM -Name $VMName -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw 'Virtual machine is not running.'
        }

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        $Data = Invoke-Command `
            -Session $Session `
            -ArgumentList @(
                $Target.IP
                $Target.Role
                $DomainName
                $DCAddress
            ) `
            -ScriptBlock {

                param(
                    [string]$ExpectedIP,
                    [string]$Role,
                    [string]$DomainName,
                    [string]$DCAddress
                )

                $ErrorActionPreference = 'Stop'

                # Read computer domain membership.
                $Computer = Get-CimInstance `
                    -ClassName Win32_ComputerSystem `
                    -ErrorAction Stop

                # Verify expected IPv4 address.
                $Addresses = @(
                    Get-NetIPAddress `
                        -AddressFamily IPv4 `
                        -ErrorAction Stop |
                    Where-Object IPAddress -eq $ExpectedIP
                )

                $IPOK = ($Addresses.Count -gt 0)

                # Verify DNS client configuration.
                $DNSAddresses = @()

                if ($IPOK) {

                    $DNSAddresses = @(
                        (
                            Get-DnsClientServerAddress `
                                -InterfaceIndex $Addresses[0].InterfaceIndex `
                                -AddressFamily IPv4 `
                                -ErrorAction Stop
                        ).ServerAddresses
                    )
                }

                $DNSClientOK = (
                    $DCAddress -in $DNSAddresses
                )

                # Resolve domain controller DNS record.
                $DNSOK = $false

                try {

                    $DNSAnswers = @(
                        Resolve-DnsName `
                            -Name "SEA-DC1.$DomainName" `
                            -Type A `
                            -Server $DCAddress `
                            -ErrorAction Stop |
                        Where-Object IPAddress -eq $DCAddress
                    )

                    $DNSOK = ($DNSAnswers.Count -gt 0)
                }
                catch {
                    $DNSOK = $false
                }

                # Resolve Kerberos SRV records.
                $SRVOK = $false

                try {

                    $SRVRecords = @(
                        Resolve-DnsName `
                            -Name "_kerberos._tcp.$DomainName" `
                            -Type SRV `
                            -Server $DCAddress `
                            -ErrorAction Stop |
                        Where-Object {
                            $_.Type -eq 'SRV' -and
                            ([string]$_.NameTarget).TrimEnd('.') -ieq
                                "SEA-DC1.$DomainName"
                        }
                    )

                    $SRVOK = ($SRVRecords.Count -gt 0)
                }
                catch {
                    $SRVOK = $false
                }

                # Verify KDC port.
                $KDCReachable = $false

                try {

                    $KDCReachable = [bool](
                        Test-NetConnection `
                            -ComputerName $DCAddress `
                            -Port 88 `
                            -InformationLevel Quiet `
                            -WarningAction SilentlyContinue
                    )
                }
                catch {
                    $KDCReachable = $false
                }

                # Discover a domain controller.
                $DCDiscoveryOutput = @(
                    & nltest.exe "/dsgetdc:$DomainName" 2>&1
                )

                $DCDiscoveryOK = ($LASTEXITCODE -eq 0)

                # Verify machine secure channel.
                $SecureChannelOK = $true

                if ($Role -eq 'Member') {

                    $SecureChannelOutput = @(
                        & nltest.exe "/sc_verify:$DomainName" 2>&1
                    )

                    $SecureChannelOK = ($LASTEXITCODE -eq 0)
                }

                # Verify Security log availability.
                $SecurityLog = Get-WinEvent `
                    -ListLog Security `
                    -ErrorAction Stop

                # Verify Windows Time service.
                $W32Time = Get-Service `
                    -Name W32Time `
                    -ErrorAction Stop

                $TimeOutput = @(
                    & w32tm.exe /query /status 2>&1
                )

                $TimeQueryOK = ($LASTEXITCODE -eq 0)

                # Inspect Kerberos ticket cache.
                $KlistOutput = @(
                    & klist.exe tickets 2>&1
                )

                $KlistOK = ($LASTEXITCODE -eq 0)

                $TGTVisible = (
                    $KlistOK -and
                    (($KlistOutput -join "`n") -match '(?i)krbtgt/')
                )

                # Verify KDC service on domain controller.
                $KDCServiceOK = $true

                if ($Role -eq 'DC') {

                    $KDCServiceOK = (
                        [string](
                            Get-Service `
                                -Name KDC `
                                -ErrorAction Stop
                        ).Status -eq 'Running'
                    )
                }

                # Return serializable results.
                [PSCustomObject]@{
                    Computer = $env:COMPUTERNAME
                    Domain = [string]$Computer.Domain
                    DomainMember = [bool]$Computer.PartOfDomain

                    IPOK = [bool]$IPOK
                    DNSClientOK = [bool]$DNSClientOK
                    DNSAddresses = ($DNSAddresses -join ',')

                    DNSOK = [bool]$DNSOK
                    SRVOK = [bool]$SRVOK
                    KDCReachable = [bool]$KDCReachable
                    DCDiscoveryOK = [bool]$DCDiscoveryOK

                    SecureChannelOK = [bool]$SecureChannelOK
                    SecurityLogOK = [bool]$SecurityLog.IsEnabled

                    W32TimeOK = [bool](
                        [string]$W32Time.Status -eq 'Running'
                    )

                    TimeQueryOK = [bool]$TimeQueryOK

                    KlistOK = [bool]$KlistOK
                    TGTVisible = [bool]$TGTVisible

                    KDCServiceOK = [bool]$KDCServiceOK
                }

            } `
            -ErrorAction Stop

        $DomainOK = (
            $Data.DomainMember -and
            $Data.Domain -ieq $DomainName
        )

        $Tests = @(
            [PSCustomObject]@{
                Name = 'Domain membership'
                Expected = $DomainName
                Actual = $Data.Domain
                OK = $DomainOK
            }
            [PSCustomObject]@{
                Name = 'Expected IPv4 address'
                Expected = $Target.IP
                Actual = [string]$Data.IPOK
                OK = $Data.IPOK
            }
            [PSCustomObject]@{
                Name = 'DNS client configuration'
                Expected = $DCAddress
                Actual = $Data.DNSAddresses
                OK = $Data.DNSClientOK
            }
            [PSCustomObject]@{
                Name = 'Domain controller DNS resolution'
                Expected = 'True'
                Actual = [string]$Data.DNSOK
                OK = $Data.DNSOK
            }
            [PSCustomObject]@{
                Name = 'Kerberos DNS SRV'
                Expected = 'True'
                Actual = [string]$Data.SRVOK
                OK = $Data.SRVOK
            }
            [PSCustomObject]@{
                Name = 'KDC TCP 88'
                Expected = 'True'
                Actual = [string]$Data.KDCReachable
                OK = $Data.KDCReachable
            }
            [PSCustomObject]@{
                Name = 'Domain controller discovery'
                Expected = 'True'
                Actual = [string]$Data.DCDiscoveryOK
                OK = $Data.DCDiscoveryOK
            }
            [PSCustomObject]@{
                Name = 'Security event log enabled'
                Expected = 'True'
                Actual = [string]$Data.SecurityLogOK
                OK = $Data.SecurityLogOK
            }
            [PSCustomObject]@{
                Name = 'Windows Time service'
                Expected = 'Running'
                Actual = [string]$Data.W32TimeOK
                OK = $Data.W32TimeOK
            }
            [PSCustomObject]@{
                Name = 'Windows Time status query'
                Expected = 'True'
                Actual = [string]$Data.TimeQueryOK
                OK = $Data.TimeQueryOK
            }
            [PSCustomObject]@{
                Name = 'KLIST execution'
                Expected = 'True'
                Actual = [string]$Data.KlistOK
                OK = $Data.KlistOK
            }
        )

        foreach ($Test in $Tests) {

            Add-Check `
                $VMName 'Infrastructure' `
                $Test.Name `
                $Test.Expected `
                $Test.Actual `
                $(if ($Test.OK) { 'PASS' } else { 'FAIL' })
        }

        if ($Target.Role -eq 'Member') {

            Add-Check `
                $VMName 'Domain' 'Machine secure channel' `
                'True' `
                ([string]$Data.SecureChannelOK) `
                $(if ($Data.SecureChannelOK) {
                    'PASS'
                } else {
                    'FAIL'
                })
        }

        if ($Target.Role -eq 'DC') {

            Add-Check `
                $VMName 'Kerberos' 'KDC service running' `
                'True' `
                ([string]$Data.KDCServiceOK) `
                $(if ($Data.KDCServiceOK) {
                    'PASS'
                } else {
                    'FAIL'
                })
        }

        # Ticket presence is informational because
        # PowerShell Direct uses another logon session.

        Add-Check `
            $VMName 'Kerberos' 'TGT visible in remote session' `
            'Informational' `
            ([string]$Data.TGTVisible) `
            'INFO'

        Write-Host "Guest verification completed." `
            -ForegroundColor Green

    }
    catch {

        Add-Check `
            $VMName 'Connection' 'Guest verification' `
            'Completed' `
            $_.Exception.Message `
            'FAIL'

        Write-Warning (
            "Verification failed on ${VMName}: " +
            $_.Exception.Message
        )
    }
    finally {

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 8. Verify SMB connectivity
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "STEP 3 - SMB CONNECTIVITY"
Write-Host "=========================================="

# Reuse the same test source connections
# as the previous authentication laboratory.

$SMBGroups = $SMBTests | Group-Object Source

foreach ($Group in $SMBGroups) {

    $VMName = $Group.Name
    $Session = $null

    try {

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        foreach ($Test in $Group.Group) {

            $TargetName = $Test.Target

            $Result = Invoke-Command `
                -Session $Session `
                -ArgumentList $TargetName `
                -ScriptBlock {

                    param([string]$TargetName)

                    $PortOK = [bool](
                        Test-NetConnection `
                            -ComputerName $TargetName `
                            -Port 445 `
                            -InformationLevel Quiet `
                            -WarningAction SilentlyContinue
                    )

                    [PSCustomObject]@{
                        PortOK = $PortOK
                    }
                } `
                -ErrorAction Stop

            Add-Check `
                $VMName 'SMB' "TCP 445 to $TargetName" `
                'Reachable' `
                ([string]$Result.PortOK) `
                $(if ($Result.PortOK) {
                    'PASS'
                } else {
                    'FAIL'
                })

            Write-Host (
                "$VMName -> ${TargetName}: " +
                $Result.PortOK
            )
        }
    }
    catch {

        Add-Check `
            $VMName 'SMB' 'SMB connectivity tests' `
            'Completed' `
            $_.Exception.Message `
            'FAIL'

        Write-Warning (
            "SMB verification failed on ${VMName}: " +
            $_.Exception.Message
        )
    }
    finally {

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 9. Verify Active Directory users
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "STEP 4 - ACTIVE DIRECTORY USERS"
Write-Host "=========================================="

$Session = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    # Serialize input as simple strings.
    $UserText = (
        $TestUsers |
        ForEach-Object {
            "$($_.Login)|$($_.ExpectedGroup)"
        }
    ) -join ';'

    $UserResults = @(
        Invoke-Command `
            -Session $Session `
            -ArgumentList $UserText `
            -ScriptBlock {

                param([string]$UserText)

                $ErrorActionPreference = 'Stop'

                Import-Module ActiveDirectory `
                    -ErrorAction Stop

                foreach ($Entry in ($UserText -split ';')) {

                    $Parts = $Entry -split '\|', 2

                    $Login = $Parts[0]
                    $ExpectedGroup = $Parts[1]

                    try {

                        $User = Get-ADUser `
                            -Identity $Login `
                            -Properties Enabled, LockedOut `
                            -ErrorAction Stop

                        $Groups = @(
                            Get-ADPrincipalGroupMembership `
                                -Identity $User `
                                -ErrorAction Stop |
                            Select-Object -ExpandProperty Name
                        )

                        [PSCustomObject]@{
                            Login = $Login
                            SID = [string]$User.SID.Value
                            Enabled = [bool]$User.Enabled
                            LockedOut = [bool]$User.LockedOut
                            ExpectedGroup = $ExpectedGroup
                            GroupOK = [bool](
                                $ExpectedGroup -in $Groups
                            )
                            Error = ''
                        }

                    }
                    catch {

                        [PSCustomObject]@{
                            Login = $Login
                            SID = ''
                            Enabled = $false
                            LockedOut = $false
                            ExpectedGroup = $ExpectedGroup
                            GroupOK = $false
                            Error = $_.Exception.Message
                        }
                    }
                }

            } `
            -ErrorAction Stop
    )

    foreach ($User in $UserResults) {

        $ADUsers.Add($User)

        $Exists = (
            -not [string]::IsNullOrWhiteSpace($User.SID) -and
            [string]::IsNullOrWhiteSpace($User.Error)
        )

        Add-Check `
            $DCName 'AD User' "Account exists: $($User.Login)" `
            'True' ([string]$Exists) `
            $(if ($Exists) { 'PASS' } else { 'FAIL' })

        Add-Check `
            $DCName 'AD User' "Account enabled: $($User.Login)" `
            'True' ([string]$User.Enabled) `
            $(if ($Exists -and $User.Enabled) {
                'PASS'
            } else {
                'FAIL'
            })

        Add-Check `
            $DCName 'AD User' "Account unlocked: $($User.Login)" `
            'True' ([string](-not $User.LockedOut)) `
            $(if ($Exists -and -not $User.LockedOut) {
                'PASS'
            } else {
                'FAIL'
            })

        Add-Check `
            $DCName 'AD Group' "Group: $($User.Login)" `
            $User.ExpectedGroup `
            ([string]$User.GroupOK) `
            $(if ($User.GroupOK) {
                'PASS'
            } else {
                'FAIL'
            })
    }
}
catch {

    Add-Check `
        $DCName 'AD User' 'AD user verification' `
        'Completed' `
        $_.Exception.Message `
        'FAIL'

    Write-Warning (
        "Active Directory verification failed: " +
        $_.Exception.Message
    )
}
finally {

    if ($null -ne $Session) {

        Remove-PSSession `
            -Session $Session `
            -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------
# 10. Collect Security events
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "STEP 5 - SECURITY EVENT COLLECTION"
Write-Host "=========================================="

foreach ($Target in $Targets) {

    $VMName = $Target.VM
    $Session = $null

    Write-Host ""
    Write-Host "Collecting Security events: $VMName"

    try {

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # Use a string to avoid nested array
        # parameter-binding errors in PowerShell Direct.

        $Data = @(
            Invoke-Command `
                -Session $Session `
                -ArgumentList @(
                    $EventIDsText
                    $StartTime
                    $EndTime
                    $MaxEventsPerVM
                ) `
                -ScriptBlock {

                    param(
                        [string]$EventIDsText,
                        [datetime]$StartTime,
                        [datetime]$EndTime,
                        [int]$MaxEvents
                    )

                    $ErrorActionPreference = 'Stop'

                    [int[]]$IDs = @(
                        $EventIDsText -split ',' |
                        ForEach-Object { [int]$_.Trim() }
                    )

                    $Filter = @{
                        LogName = 'Security'
                        Id = $IDs
                        StartTime = $StartTime
                        EndTime = $EndTime
                    }

                    $RawEvents = @()

                    try {

                        $RawEvents = @(
                            Get-WinEvent `
                                -FilterHashtable $Filter `
                                -MaxEvents $MaxEvents `
                                -ErrorAction Stop
                        )
                    }
                    catch {

                        if (
                            $_.FullyQualifiedErrorId -match
                            'NoMatchingEventsFound'
                        ) {
                            $RawEvents = @()
                        }
                        else {
                            throw
                        }
                    }

                    foreach ($Event in $RawEvents) {

                        $XML = [xml]$Event.ToXml()
                        $Fields = @{}

                        foreach (
                            $Field in @(
                                $XML.Event.EventData.Data
                            )
                        ) {

                            if ($Field.Name) {

                                $Fields[[string]$Field.Name] = (
                                    [string]$Field.'#text'
                                )
                            }
                        }

                        # Normalize field differences
                        # between Security event types.

                        $Account = ''

                        if ($Fields.ContainsKey('TargetUserName')) {
                            $Account = $Fields['TargetUserName']
                        }
                        elseif ($Fields.ContainsKey('TargetUser')) {
                            $Account = $Fields['TargetUser']
                        }

                        $IPAddress = ''

                        if ($Fields.ContainsKey('IpAddress')) {
                            $IPAddress = $Fields['IpAddress']
                        }
                        elseif ($Fields.ContainsKey('ClientAddress')) {
                            $IPAddress = $Fields['ClientAddress']
                        }

                        [PSCustomObject]@{
                            Computer = $env:COMPUTERNAME
                            TimeCreated = $Event.TimeCreated
                            RecordID = [long]$Event.RecordId
                            EventID = [int]$Event.Id

                            Account = $Account
                            IPAddress = $IPAddress

                            LogonType = [string](
                                $Fields['LogonType']
                            )

                            ServiceName = [string](
                                $Fields['ServiceName']
                            )

                            AuthenticationPackage = [string](
                                $Fields['AuthenticationPackageName']
                            )

                            StatusCode = [string](
                                $Fields['Status']
                            )

                            SubStatus = [string](
                                $Fields['SubStatus']
                            )

                            FailureCode = [string](
                                $Fields['FailureCode']
                            )

                            TicketEncryptionType = [string](
                                $Fields['TicketEncryptionType']
                            )
                        }
                    }

                } `
                -ErrorAction Stop
        )

        foreach ($Item in $Data) {

            $LogonDescription = switch (
                [string]$Item.LogonType
            ) {
                '2'  { 'Interactive' }
                '3'  { 'Network' }
                '5'  { 'Service' }
                '7'  { 'Unlock' }
                '10' { 'RemoteInteractive' }
                '11' { 'CachedInteractive' }
                default { '' }
            }

            # Normalize account UPN for analysis.
            $NormalizedAccount = [string]$Item.Account

            if ($NormalizedAccount -match '@') {

                $NormalizedAccount = (
                    $NormalizedAccount -split '@'
                )[0]
            }

            # A ticket request may succeed or fail.
            $Outcome = switch ([int]$Item.EventID) {

                4624 { 'SUCCESS' }
                4625 { 'FAILURE' }
                4634 { 'INFO' }
                4771 { 'FAILURE' }

                { $_ -in @(4768, 4769) } {

                    if ($Item.StatusCode -eq '0x0') {
                        'SUCCESS'
                    }
                    elseif (
                        [string]::IsNullOrWhiteSpace(
                            $Item.StatusCode
                        )
                    ) {
                        'UNKNOWN'
                    }
                    else {
                        'FAILURE'
                    }
                }

                default { 'INFO' }
            }

            $Events.Add(
                [PSCustomObject]@{
                    Computer = [string]$Item.Computer
                    TimeCreated = $Item.TimeCreated
                    RecordID = [long]$Item.RecordID
                    EventID = [int]$Item.EventID
                    Account = [string]$Item.Account
                    NormalizedAccount = $NormalizedAccount
                    IPAddress = [string]$Item.IPAddress

                    LogonType = [string]$Item.LogonType
                    LogonDescription = $LogonDescription

                    ServiceName = [string]$Item.ServiceName

                    AuthenticationPackage = (
                        [string]$Item.AuthenticationPackage
                    )

                    StatusCode = [string]$Item.StatusCode
                    SubStatus = [string]$Item.SubStatus
                    FailureCode = [string]$Item.FailureCode

                    TicketEncryptionType = (
                        [string]$Item.TicketEncryptionType
                    )

                    Outcome = $Outcome
                }
            )
        }

        $Truncated = (
            $Data.Count -ge $MaxEventsPerVM
        )

        $Collections.Add(
            [PSCustomObject]@{
                Computer = $VMName
                Events = $Data.Count
                Status = 'PASS'
                Truncated = $Truncated
                Error = ''
            }
        )

        Write-Host (
            "Collected: $($Data.Count) events"
        ) -ForegroundColor Green

        if ($Truncated) {

            Write-Warning (
                "$VMName reached the event limit."
            )
        }

    }
    catch {

        $Message = $_.Exception.Message

        $Collections.Add(
            [PSCustomObject]@{
                Computer = $VMName
                Events = 0
                Status = 'FAIL'
                Truncated = $false
                Error = $Message
            }
        )

        Add-Check `
            $VMName 'Security' 'Event collection' `
            'Successful' $Message 'FAIL'

        Write-Warning (
            "Collection failed on ${VMName}: $Message"
        )
    }
    finally {

        if ($null -ne $Session) {

            Remove-PSSession `
                -Session $Session `
                -ErrorAction SilentlyContinue
        }
    }
}

# ----------------------------------------------------------
# 11. Calculate Security statistics
# ----------------------------------------------------------

$SortedEvents = @(
    $Events |
    Sort-Object TimeCreated, Computer, RecordID
)

$EventStatistics = @(
    foreach ($Target in $Targets) {

        foreach ($ID in $EventIDs) {

            [PSCustomObject]@{
                Computer = $Target.VM
                EventID = $ID
                Count = Get-EventCount `
                    -InputEvents $SortedEvents `
                    -ID $ID `
                    -Machine $Target.VM
            }
        }
    }
)

$AccountStatistics = @(
    $SortedEvents |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace(
            $_.NormalizedAccount
        )
    } |
    Group-Object Computer, NormalizedAccount |
    ForEach-Object {

        $GroupEvents = @($_.Group)
        $First = $GroupEvents[0]

        [PSCustomObject]@{
            Computer = $First.Computer
            Account = $First.NormalizedAccount
            TotalEvents = $GroupEvents.Count

            SuccessfulLogons = @(
                $GroupEvents |
                Where-Object EventID -eq 4624
            ).Count

            FailedLogons = @(
                $GroupEvents |
                Where-Object EventID -eq 4625
            ).Count

            TGTRequests = @(
                $GroupEvents |
                Where-Object EventID -eq 4768
            ).Count

            TGSRequests = @(
                $GroupEvents |
                Where-Object EventID -eq 4769
            ).Count

            KerberosFailures = @(
                $GroupEvents |
                Where-Object EventID -eq 4771
            ).Count
        }
    }
)

# ----------------------------------------------------------
# 12. Verify authentication activity
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "STEP 6 - AUTHENTICATION ACTIVITY"
Write-Host "=========================================="

$TGTCount = Get-EventCount `
    -InputEvents $SortedEvents -ID 4768

$TGSCount = Get-EventCount `
    -InputEvents $SortedEvents -ID 4769

$LogonCount = Get-EventCount `
    -InputEvents $SortedEvents -ID 4624

$FailedLogonCount = Get-EventCount `
    -InputEvents $SortedEvents -ID 4625

$PreAuthFailureCount = Get-EventCount `
    -InputEvents $SortedEvents -ID 4771

# An observed event is evidence of activity,
# not a strict infrastructure availability test.

Add-Check `
    $DCName 'Kerberos' 'TGT requests observed' `
    'Informational' `
    ([string]$TGTCount) `
    'INFO'

Add-Check `
    $DCName 'Kerberos' 'TGS requests observed' `
    'Informational' `
    ([string]$TGSCount) `
    'INFO'

Add-Check `
    'ALL' 'Logon' 'Successful logons observed' `
    'Informational' `
    ([string]$LogonCount) `
    'INFO'

# ----------------------------------------------------------
# 13. Analyze failed logons
# ----------------------------------------------------------

$FailedEvents = @(
    $SortedEvents |
    Where-Object {
        $_.EventID -in @(4625, 4771)
    }
)

Add-Check `
    'ALL' 'Security' 'Authentication failures observed' `
    'Review if present' `
    ([string]$FailedEvents.Count) `
    $(if ($FailedEvents.Count -gt 0) {
        'REVIEW'
    } else {
        'INFO'
    })

# Focus on the previously observed user.
$EwaFailures = @(
    $SortedEvents |
    Where-Object {
        $_.Computer -eq 'SEA-CL1' -and
        $_.EventID -eq 4625 -and
        $_.NormalizedAccount -ieq 'ewa.kaczmarek'
    }
)

Add-Check `
    'SEA-CL1' 'Security' 'Ewa failed logons' `
    'Review if present' `
    ([string]$EwaFailures.Count) `
    $(if ($EwaFailures.Count -gt 0) {
        'REVIEW'
    } else {
        'INFO'
    })

$EwaFailureDetails = @(
    $EwaFailures |
    Select-Object `
        TimeCreated,
        Computer,
        Account,
        IPAddress,
        LogonType,
        LogonDescription,
        StatusCode,
        SubStatus |
    Sort-Object TimeCreated
)

# ----------------------------------------------------------
# 14. Verify collection completeness
# ----------------------------------------------------------

$CollectionFailed = @(
    $Collections |
    Where-Object Status -eq 'FAIL'
).Count

$TruncatedCount = @(
    $Collections |
    Where-Object Truncated -eq $true
).Count

Add-Check `
    'ALL' 'Security' 'Security collection coverage' `
    "$($Targets.Count) successful collections" `
    "$(@($Collections | Where-Object Status -eq 'PASS').Count) successful collections" `
    $(if ($CollectionFailed -eq 0 -and
           $Collections.Count -eq $Targets.Count) {
        'PASS'
    } else {
        'FAIL'
    })

if ($TruncatedCount -gt 0) {

    Add-Check `
        'ALL' 'Security' 'Event collection limit' `
        'No truncated collections' `
        "$TruncatedCount truncated" `
        'REVIEW'
}

# ----------------------------------------------------------
# 15. Calculate final result
# ----------------------------------------------------------

$Passed = @(
    $Checks |
    Where-Object Status -eq 'PASS'
).Count

$Failed = @(
    $Checks |
    Where-Object Status -eq 'FAIL'
).Count

$Info = @(
    $Checks |
    Where-Object Status -eq 'INFO'
).Count

$Review = @(
    $Checks |
    Where-Object Status -eq 'REVIEW'
).Count

$TotalChecks = $Checks.Count
$TotalEvents = $SortedEvents.Count

$FinalStatus = if ($Failed -gt 0) {
    'FAIL - INFRASTRUCTURE REQUIRES ATTENTION'
}
elseif ($CollectionFailed -gt 0) {
    'FAIL - INCOMPLETE SECURITY COLLECTION'
}
elseif ($Review -gt 0) {
    'PASS - WITH ITEMS TO REVIEW'
}
else {
    'PASS'
}

# ----------------------------------------------------------
# 16. Export CSV reports
# ----------------------------------------------------------

$Checks |
    Export-Csv `
        -Path $ChecksCSV `
        -NoTypeInformation `
        -Encoding UTF8

Export-LabCsv `
    -Data $SortedEvents `
    -Path $EventsCSV `
    -Columns @(
        'Computer'
        'TimeCreated'
        'RecordID'
        'EventID'
        'Account'
        'NormalizedAccount'
        'IPAddress'
        'LogonType'
        'LogonDescription'
        'ServiceName'
        'AuthenticationPackage'
        'StatusCode'
        'SubStatus'
        'FailureCode'
        'TicketEncryptionType'
        'Outcome'
    )

$EventStatistics |
    Export-Csv `
        -Path $StatsCSV `
        -NoTypeInformation `
        -Encoding UTF8

Export-LabCsv `
    -Data $AccountStatistics `
    -Path $AccountsCSV `
    -Columns @(
        'Computer'
        'Account'
        'TotalEvents'
        'SuccessfulLogons'
        'FailedLogons'
        'TGTRequests'
        'TGSRequests'
        'KerberosFailures'
    )

$Collections |
    Export-Csv `
        -Path $CollectionsCSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 17. Build TXT report
# ----------------------------------------------------------

$Header = @"
============================================================
LAB 7 - FINAL VERIFICATION REPORT
============================================================

Host: $env:COMPUTERNAME
Domain: $DomainName
Generated: $(Get-Date)

Analysis window:
From: $StartTime
To: $EndTime

FINAL STATUS:
$FinalStatus

Checks: $TotalChecks
PASS: $Passed
FAIL: $Failed
INFO: $Info
REVIEW: $Review

Security events: $TotalEvents

4624 - Successful logons: $LogonCount
4625 - Failed logons: $FailedLogonCount
4768 - TGT requests: $TGTCount
4769 - TGS requests: $TGSCount
4771 - Kerberos pre-auth failures: $PreAuthFailureCount

Ewa failed logons on SEA-CL1: $($EwaFailures.Count)

INTERPRETATION NOTES:

PASS:
The required check succeeded.

FAIL:
An infrastructure or collection check failed.

INFO:
Observed activity or contextual information.
A missing ticket in a PowerShell Direct session
does not necessarily indicate a Kerberos failure.

REVIEW:
An observed condition requires interpretation.
Failed logons do not automatically fail this lab.

"@

$ChecksText = $Checks |
    Format-Table `
        Machine, Category, Check, Actual, Status `
        -AutoSize |
    Out-String -Width 240

$StatsText = $EventStatistics |
    Format-Table -AutoSize |
    Out-String -Width 240

$AccountText = $AccountStatistics |
    Sort-Object TotalEvents -Descending |
    Format-Table -AutoSize |
    Out-String -Width 240

$EwaText = $EwaFailureDetails |
    Format-Table -AutoSize |
    Out-String -Width 240

$CollectionText = $Collections |
    Format-Table -AutoSize |
    Out-String -Width 240

@(
    $Header

    '------------------------------------------------------'
    'FINAL INFRASTRUCTURE CHECKS'
    '------------------------------------------------------'
    $ChecksText

    '------------------------------------------------------'
    'SECURITY COLLECTION STATUS'
    '------------------------------------------------------'
    $CollectionText

    '------------------------------------------------------'
    'EVENT STATISTICS'
    '------------------------------------------------------'
    $StatsText

    '------------------------------------------------------'
    'ACCOUNT STATISTICS'
    '------------------------------------------------------'
    $AccountText

    '------------------------------------------------------'
    'EWA - FAILED LOGON DETAILS'
    '------------------------------------------------------'
    $EwaText

) -join "`r`n" |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 18. Build HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    background: #f5f9fb;
    color: #294554;
    margin: 32px;
    line-height: 1.5;
}
h1, h2 {
    color: #146393;
}
.summary {
    padding: 18px;
    border: 1px solid #dce6eb;
    background: #ffffff;
    margin-bottom: 24px;
}
table {
    width: 100%;
    border-collapse: collapse;
    background: #ffffff;
    margin-bottom: 28px;
}
th {
    background: #146393;
    color: #ffffff;
    text-align: left;
    padding: 9px;
}
td {
    border: 1px solid #dce6eb;
    padding: 7px;
    vertical-align: top;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
.note {
    border-left: 4px solid #146393;
    padding: 12px 16px;
    background: #ffffff;
    margin-bottom: 20px;
}
</style>
"@

$StatusHTML = [System.Net.WebUtility]::HtmlEncode(
    $FinalStatus
)

$HTMLIntro = @"
<h1>LAB 7 - Final Verification Report</h1>

<div class="summary">
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>Host:</strong> $env:COMPUTERNAME</p>
<p><strong>Analysis window:</strong> $StartTime - $EndTime</p>
<p><strong>Final status:</strong> $StatusHTML</p>
<p>
<strong>PASS:</strong> $Passed |
<strong>FAIL:</strong> $Failed |
<strong>INFO:</strong> $Info |
<strong>REVIEW:</strong> $Review
</p>
<p><strong>Security events:</strong> $TotalEvents</p>
<p><strong>Ewa failed logons:</strong> $($EwaFailures.Count)</p>
</div>

<div class="note">
<p>
PowerShell Direct sessions have separate logon tokens and
Kerberos ticket caches. Failed logons are reviewed separately
from infrastructure availability checks.
</p>
</div>
"@

$ChecksHTML = $Checks |
    ConvertTo-Html -Fragment |
    Out-String

$CollectionsHTML = $Collections |
    ConvertTo-Html -Fragment |
    Out-String

$StatsHTML = $EventStatistics |
    ConvertTo-Html -Fragment |
    Out-String

$AccountsHTML = $AccountStatistics |
    ConvertTo-Html -Fragment |
    Out-String

$EwaHTML = $EwaFailureDetails |
    ConvertTo-Html -Fragment |
    Out-String

$HTMLBody = @"
$HTMLIntro

<h2>Final infrastructure checks</h2>
$ChecksHTML

<h2>Security collection status</h2>
$CollectionsHTML

<h2>Event statistics</h2>
$StatsHTML

<h2>Account statistics</h2>
$AccountsHTML

<h2>Ewa - failed logon analysis</h2>
$EwaHTML
"@

ConvertTo-Html `
    -Title 'LAB 7 - Final Verification' `
    -Head $CSS `
    -Body $HTMLBody |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 19. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - FINAL CHECK RESULTS"
Write-Host "=========================================="
Write-Host ""

$Checks |
    Format-Table `
        Machine,
        Category,
        Check,
        Status `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - SECURITY SUMMARY"
Write-Host "=========================================="
Write-Host ""

$EventStatistics |
    Format-Table `
        Computer,
        EventID,
        Count `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - FINAL RESULT"
Write-Host "=========================================="
Write-Host ""

Write-Host "Final status: $FinalStatus"
Write-Host ""
Write-Host "Total checks: $TotalChecks"
Write-Host "PASS:   $Passed" -ForegroundColor Green
Write-Host "FAIL:   $Failed" -ForegroundColor Red
Write-Host "INFO:   $Info" -ForegroundColor Cyan
Write-Host "REVIEW: $Review" -ForegroundColor Yellow

Write-Host ""
Write-Host "Collected Security events: $TotalEvents"
Write-Host "Successful logons: $LogonCount"
Write-Host "Failed logons: $FailedLogonCount"
Write-Host "TGT requests: $TGTCount"
Write-Host "TGS requests: $TGSCount"
Write-Host "Pre-auth failures: $PreAuthFailureCount"
Write-Host ""
Write-Host "Ewa failed logons: $($EwaFailures.Count)"

Write-Host ""
Write-Host "Reports exported:"
Write-Host "Checks CSV:      $ChecksCSV"
Write-Host "Events CSV:      $EventsCSV"
Write-Host "Event stats CSV: $StatsCSV"
Write-Host "Accounts CSV:    $AccountsCSV"
Write-Host "Collection CSV:  $CollectionsCSV"
Write-Host "TXT:             $TXT"
Write-Host "HTML:            $HTML"

# ----------------------------------------------------------
# 20. Final verification status
# ----------------------------------------------------------

if ($Failed -gt 0) {

    Write-Warning (
        "LAB 7 - Final verification identified " +
        "$Failed failed checks."
    )
}
elseif ($Review -gt 0) {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 7 - PASSED WITH REVIEW ITEMS"
    Write-Host "==========================================" `
        -ForegroundColor Yellow

    Write-Host (
        "Infrastructure checks passed. " +
        "Review authentication findings in the reports."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 7 - FINAL VERIFICATION PASSED"
    Write-Host "=========================================="
}
