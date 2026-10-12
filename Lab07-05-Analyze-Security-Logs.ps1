# ==========================================================
# LAB 7 - Script 05 - Analyze Security and Kerberos Logs
#
# Run on host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Domain: contoso.com
#
# Virtual machines:
#   SEA-DC1
#   SEA-SRV1
#   SEA-SRV2
#   SEA-CL1
#
# Analyzed events:
#   4624 - Successful logon
#   4625 - Failed logon
#   4634 - Logoff
#   4768 - Kerberos TGT request
#   4769 - Kerberos TGS request
#   4771 - Kerberos pre-authentication failure
#
# Reports:
#   Detailed events CSV
#   Event summary CSV
#   Account statistics CSV
#   Collection status CSV
#   Detailed TXT
#   HTML
#
# Read-only diagnostic script.
# ==========================================================

[CmdletBinding()]
param(
    [ValidateRange(1, 168)]
    [int]$HoursBack = 4,

    [ValidateRange(100, 20000)]
    [int]$MaxEventsPerVM = 5000
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$ReportDir = 'C:\LabReports'

$VMNames = @(
    'SEA-DC1'
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

[int[]]$EventIDs = @(
    4624
    4625
    4634
    4768
    4769
    4771
)

# Convert event IDs into a simple string for remoting.
# This avoids nested-array serialization issues.

$EventIDsText = $EventIDs -join ','

$EndTime = Get-Date
$StartTime = $EndTime.AddHours(-$HoursBack)

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

# ----------------------------------------------------------
# 2. Initialize environment
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

New-Item `
    -Path $ReportDir `
    -ItemType Directory `
    -Force | Out-Null

$EventsCSV = Join-Path $ReportDir `
    "LAB07-Security-Events_$Timestamp.csv"

$SummaryCSV = Join-Path $ReportDir `
    "LAB07-Security-Summary_$Timestamp.csv"

$AccountsCSV = Join-Path $ReportDir `
    "LAB07-Security-Accounts_$Timestamp.csv"

$CollectionCSV = Join-Path $ReportDir `
    "LAB07-Security-Collection_$Timestamp.csv"

$TXT = Join-Path $ReportDir `
    "LAB07-Security-Analysis_$Timestamp.txt"

$HTML = Join-Path $ReportDir `
    "LAB07-Security-Analysis_$Timestamp.html"

$Events = [System.Collections.Generic.List[object]]::new()
$CollectionResults = [System.Collections.Generic.List[object]]::new()

# ----------------------------------------------------------
# 3. Event descriptions
# ----------------------------------------------------------

$EventDescriptions = @{
    4624 = 'Successful logon'
    4625 = 'Failed logon'
    4634 = 'Logoff'
    4768 = 'Kerberos TGT request'
    4769 = 'Kerberos TGS request'
    4771 = 'Kerberos pre-authentication failure'
}

$LogonDescriptions = @{
    '2'  = 'Interactive'
    '3'  = 'Network'
    '4'  = 'Batch'
    '5'  = 'Service'
    '7'  = 'Unlock'
    '8'  = 'NetworkCleartext'
    '9'  = 'NewCredentials'
    '10' = 'RemoteInteractive'
    '11' = 'CachedInteractive'
    '12' = 'CachedRemoteInteractive'
    '13' = 'CachedUnlock'
}

# ----------------------------------------------------------
# 4. Helper functions
# ----------------------------------------------------------

function Get-EventCount {

    param(
        [object[]]$InputEvents,
        [int]$EventID,
        [string]$Computer = ''
    )

    $Filtered = @(
        $InputEvents | Where-Object {
            $_.EventID -eq $EventID -and
            (
                [string]::IsNullOrWhiteSpace($Computer) -or
                $_.Computer -eq $Computer
            )
        }
    )

    return $Filtered.Count
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

        # Create a header-only CSV when no rows exist.
        $Header = (
            $Columns |
            ForEach-Object {
                '"' + ($_ -replace '"', '""') + '"'
            }
        ) -join ','

        Set-Content `
            -Path $Path `
            -Value $Header `
            -Encoding UTF8
    }
}

# ----------------------------------------------------------
# 5. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - SECURITY LOG ANALYSIS"
Write-Host "=========================================="
Write-Host ""

Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Domain: $DomainName"
Write-Host "Machines: $($VMNames.Count)"
Write-Host "Hours back: $HoursBack"
Write-Host "From: $StartTime"
Write-Host "To: $EndTime"
Write-Host "Event IDs: $EventIDsText"
Write-Host ""

# ----------------------------------------------------------
# 6. Request credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 7. Collect Security events
# ----------------------------------------------------------

foreach ($VMName in $VMNames) {

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Collecting events from $VMName"
    Write-Host "------------------------------------------"

    $Session = $null

    try {

        # --------------------------------------------------
        # 8. Verify virtual machine
        # --------------------------------------------------

        $VM = Get-VM `
            -Name $VMName `
            -ErrorAction Stop

        if ([string]$VM.State -ne 'Running') {
            throw "Virtual machine $VMName is not running."
        }

        # --------------------------------------------------
        # 9. Connect using PowerShell Direct
        # --------------------------------------------------

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # --------------------------------------------------
        # 10. Read Security events inside the guest
        # --------------------------------------------------

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

                    # --------------------------------------
                    # 11. Rebuild event ID array
                    # --------------------------------------

                    [int[]]$EventIDs = @(
                        $EventIDsText -split ',' |
                        ForEach-Object {
                            [int]$_.Trim()
                        }
                    )

                    # --------------------------------------
                    # 12. Validate Security log
                    # --------------------------------------

                    $SecurityLog = Get-WinEvent `
                        -ListLog Security `
                        -ErrorAction Stop

                    if (-not $SecurityLog.IsEnabled) {
                        throw 'Security event log is disabled.'
                    }

                    # --------------------------------------
                    # 13. Prepare event filter
                    # --------------------------------------

                    $Filter = @{
                        LogName = 'Security'
                        Id = $EventIDs
                        StartTime = $StartTime
                        EndTime = $EndTime
                    }

                    # --------------------------------------
                    # 14. Retrieve matching events
                    # --------------------------------------

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

                        # Get-WinEvent may throw when
                        # no events match the filter.

                        $IsNoMatch = (
                            $_.FullyQualifiedErrorId -match
                            'NoMatchingEventsFound'
                        )

                        if ($IsNoMatch) {
                            $RawEvents = @()
                        }
                        else {
                            throw
                        }
                    }

                    # --------------------------------------
                    # 15. Parse matching events
                    # --------------------------------------

                    foreach ($Event in $RawEvents) {

                        $EventXML = [xml]$Event.ToXml()

                        $Fields = @{}

                        foreach (
                            $Field in @(
                                $EventXML.Event.EventData.Data
                            )
                        ) {

                            $FieldName = [string]$Field.Name

                            if (
                                -not [string]::IsNullOrWhiteSpace(
                                    $FieldName
                                )
                            ) {

                                $Fields[$FieldName] = (
                                    [string]$Field.'#text'
                                )
                            }
                        }

                        # ----------------------------------
                        # 16. Read event fields
                        # ----------------------------------

                        $Account = ''
                        $AccountDomain = ''
                        $IPAddress = ''
                        $Workstation = ''
                        $LogonType = ''
                        $ServiceName = ''
                        $AuthPackage = ''
                        $StatusCode = ''
                        $SubStatus = ''
                        $FailureCode = ''
                        $EncryptionType = ''
                        $PreAuthType = ''
                        $LogonID = ''

                        if (
                            $Fields.ContainsKey(
                                'TargetUserName'
                            )
                        ) {
                            $Account = (
                                $Fields['TargetUserName']
                            )
                        }
                        elseif (
                            $Fields.ContainsKey(
                                'TargetUser'
                            )
                        ) {
                            $Account = $Fields['TargetUser']
                        }

                        if (
                            $Fields.ContainsKey(
                                'TargetDomainName'
                            )
                        ) {
                            $AccountDomain = (
                                $Fields['TargetDomainName']
                            )
                        }
                        elseif (
                            $Fields.ContainsKey(
                                'TargetDomain'
                            )
                        ) {
                            $AccountDomain = (
                                $Fields['TargetDomain']
                            )
                        }

                        if (
                            $Fields.ContainsKey('IpAddress')
                        ) {
                            $IPAddress = $Fields['IpAddress']
                        }
                        elseif (
                            $Fields.ContainsKey(
                                'ClientAddress'
                            )
                        ) {
                            $IPAddress = (
                                $Fields['ClientAddress']
                            )
                        }

                        if (
                            $Fields.ContainsKey(
                                'WorkstationName'
                            )
                        ) {
                            $Workstation = (
                                $Fields['WorkstationName']
                            )
                        }

                        if (
                            $Fields.ContainsKey('LogonType')
                        ) {
                            $LogonType = $Fields['LogonType']
                        }

                        if (
                            $Fields.ContainsKey(
                                'ServiceName'
                            )
                        ) {
                            $ServiceName = (
                                $Fields['ServiceName']
                            )
                        }

                        if (
                            $Fields.ContainsKey(
                                'AuthenticationPackageName'
                            )
                        ) {
                            $AuthPackage = (
                                $Fields[
                                    'AuthenticationPackageName'
                                ]
                            )
                        }

                        if (
                            $Fields.ContainsKey('Status')
                        ) {
                            $StatusCode = $Fields['Status']
                        }

                        if (
                            $Fields.ContainsKey('SubStatus')
                        ) {
                            $SubStatus = $Fields['SubStatus']
                        }

                        if (
                            $Fields.ContainsKey(
                                'FailureCode'
                            )
                        ) {
                            $FailureCode = (
                                $Fields['FailureCode']
                            )
                        }

                        if (
                            $Fields.ContainsKey(
                                'TicketEncryptionType'
                            )
                        ) {
                            $EncryptionType = (
                                $Fields[
                                    'TicketEncryptionType'
                                ]
                            )
                        }

                        if (
                            $Fields.ContainsKey('PreAuthType')
                        ) {
                            $PreAuthType = (
                                $Fields['PreAuthType']
                            )
                        }

                        if (
                            $Fields.ContainsKey(
                                'TargetLogonId'
                            )
                        ) {
                            $LogonID = (
                                $Fields['TargetLogonId']
                            )
                        }

                        # ----------------------------------
                        # 17. Return structured event
                        # ----------------------------------

                        [PSCustomObject]@{
                            Computer = $env:COMPUTERNAME
                            TimeCreated = $Event.TimeCreated
                            EventID = [int]$Event.Id
                            RecordID = [long]$Event.RecordId

                            Account = $Account
                            AccountDomain = $AccountDomain
                            IPAddress = $IPAddress
                            Workstation = $Workstation

                            LogonType = $LogonType
                            LogonID = $LogonID

                            ServiceName = $ServiceName
                            AuthenticationPackage = $AuthPackage

                            StatusCode = $StatusCode
                            SubStatus = $SubStatus
                            FailureCode = $FailureCode

                            TicketEncryptionType = $EncryptionType
                            PreAuthType = $PreAuthType
                        }

                    }

                } `
                -ErrorAction Stop
        )

        # --------------------------------------------------
        # 18. Classify events on the host
        # --------------------------------------------------

        $CollectedCount = 0

        foreach ($Item in $Data) {

            $ID = [int]$Item.EventID

            $Description = $EventDescriptions[$ID]

            if (-not $Description) {
                $Description = 'Other security event'
            }

            $LogonDescription = ''

            $LogonKey = [string]$Item.LogonType

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $LogonKey
                )
            ) {

                $LogonDescription = (
                    $LogonDescriptions[$LogonKey]
                )

                if (-not $LogonDescription) {
                    $LogonDescription = 'Other'
                }
            }

            # ----------------------------------------------
            # 19. Classify event outcome
            # ----------------------------------------------

            $Classification = switch ($ID) {

                4624 { 'SUCCESS' }
                4625 { 'FAILURE' }
                4634 { 'INFO' }
                4771 { 'FAILURE' }

                4768 {
                    if (
                        $Item.StatusCode -eq '0x0'
                    ) {
                        'SUCCESS'
                    }
                    elseif (
                        -not [string]::IsNullOrWhiteSpace(
                            [string]$Item.StatusCode
                        )
                    ) {
                        'FAILURE'
                    }
                    else {
                        'UNKNOWN'
                    }
                }

                4769 {
                    if (
                        $Item.StatusCode -eq '0x0'
                    ) {
                        'SUCCESS'
                    }
                    elseif (
                        -not [string]::IsNullOrWhiteSpace(
                            [string]$Item.StatusCode
                        )
                    ) {
                        'FAILURE'
                    }
                    else {
                        'UNKNOWN'
                    }
                }

                default { 'INFO' }
            }

            # ----------------------------------------------
            # 20. Add event to collection
            # ----------------------------------------------

            $Events.Add(
                [PSCustomObject]@{
                    Computer = [string]$Item.Computer
                    TimeCreated = $Item.TimeCreated
                    EventID = $ID
                    Description = $Description
                    Classification = $Classification
                    RecordID = [long]$Item.RecordID

                    Account = [string]$Item.Account
                    AccountDomain = [string]$Item.AccountDomain
                    IPAddress = [string]$Item.IPAddress
                    Workstation = [string]$Item.Workstation

                    LogonType = [string]$Item.LogonType
                    LogonDescription = $LogonDescription
                    LogonID = [string]$Item.LogonID

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

                    PreAuthType = [string]$Item.PreAuthType
                }
            )

            $CollectedCount++
        }

        # --------------------------------------------------
        # 21. Record collection status
        # --------------------------------------------------

        $Truncated = (
            $CollectedCount -ge $MaxEventsPerVM
        )

        $CollectionResults.Add(
            [PSCustomObject]@{
                Computer = $VMName
                Events = $CollectedCount
                Status = 'PASS'
                Truncated = $Truncated
                Error = ''
            }
        )

        Write-Host (
            "Collected events: $CollectedCount"
        ) -ForegroundColor Green

        if ($Truncated) {

            Write-Warning (
                "$VMName reached MaxEventsPerVM. " +
                "The analysis may be incomplete."
            )
        }

    }
    catch {

        # --------------------------------------------------
        # 22. Handle individual VM failure
        # --------------------------------------------------

        $Message = $_.Exception.Message

        $CollectionResults.Add(
            [PSCustomObject]@{
                Computer = $VMName
                Events = 0
                Status = 'FAIL'
                Truncated = $false
                Error = $Message
            }
        )

        Write-Warning (
            "Security log collection failed on " +
            "${VMName}: $Message"
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
# 23. Sort events
# ----------------------------------------------------------

$SortedEvents = @(
    $Events |
    Sort-Object TimeCreated, Computer, RecordID
)

# ----------------------------------------------------------
# 24. Build event summary
# ----------------------------------------------------------

$Summary = @(
    foreach ($VMName in $VMNames) {

        foreach ($ID in $EventIDs) {

            $Count = Get-EventCount `
                -InputEvents $SortedEvents `
                -EventID $ID `
                -Computer $VMName

            [PSCustomObject]@{
                Computer = $VMName
                EventID = $ID
                Description = $EventDescriptions[$ID]
                Count = $Count
            }
        }
    }
)

# ----------------------------------------------------------
# 25. Build account statistics
# ----------------------------------------------------------

$AccountStatistics = @(
    $SortedEvents |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace(
            $_.Account
        )
    } |
    Group-Object Computer, Account |
    ForEach-Object {

        $GroupEvents = @($_.Group)
        $First = $GroupEvents[0]

        [PSCustomObject]@{
            Computer = $First.Computer
            Account = $First.Account
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
# 26. Export detailed events CSV
# ----------------------------------------------------------

$EventColumns = @(
    'Computer'
    'TimeCreated'
    'EventID'
    'Description'
    'Classification'
    'RecordID'
    'Account'
    'AccountDomain'
    'IPAddress'
    'Workstation'
    'LogonType'
    'LogonDescription'
    'LogonID'
    'ServiceName'
    'AuthenticationPackage'
    'StatusCode'
    'SubStatus'
    'FailureCode'
    'TicketEncryptionType'
    'PreAuthType'
)

Export-LabCsv `
    -Data $SortedEvents `
    -Path $EventsCSV `
    -Columns $EventColumns

# ----------------------------------------------------------
# 27. Export event summary CSV
# ----------------------------------------------------------

$Summary |
    Export-Csv `
        -Path $SummaryCSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 28. Export account statistics CSV
# ----------------------------------------------------------

$AccountColumns = @(
    'Computer'
    'Account'
    'TotalEvents'
    'SuccessfulLogons'
    'FailedLogons'
    'TGTRequests'
    'TGSRequests'
    'KerberosFailures'
)

Export-LabCsv `
    -Data $AccountStatistics `
    -Path $AccountsCSV `
    -Columns $AccountColumns

# ----------------------------------------------------------
# 29. Export collection status CSV
# ----------------------------------------------------------

$CollectionResults |
    Export-Csv `
        -Path $CollectionCSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 30. Calculate final statistics
# ----------------------------------------------------------

$CollectionPassed = @(
    $CollectionResults |
    Where-Object Status -eq 'PASS'
).Count

$CollectionFailed = @(
    $CollectionResults |
    Where-Object Status -eq 'FAIL'
).Count

$TruncatedVMs = @(
    $CollectionResults |
    Where-Object Truncated -eq $true
).Count

$TotalEvents = $SortedEvents.Count

$LogonSuccess = Get-EventCount `
    -InputEvents $SortedEvents `
    -EventID 4624

$LogonFailure = Get-EventCount `
    -InputEvents $SortedEvents `
    -EventID 4625

$LogoffCount = Get-EventCount `
    -InputEvents $SortedEvents `
    -EventID 4634

$TGTRequests = Get-EventCount `
    -InputEvents $SortedEvents `
    -EventID 4768

$TGSRequests = Get-EventCount `
    -InputEvents $SortedEvents `
    -EventID 4769

$PreAuthFailures = Get-EventCount `
    -InputEvents $SortedEvents `
    -EventID 4771

# ----------------------------------------------------------
# 31. Build detailed TXT report
# ----------------------------------------------------------

$Header = @"
LAB 7 - SECURITY LOG ANALYSIS REPORT

Host: $env:COMPUTERNAME
Domain: $DomainName
Date: $(Get-Date)

Analysis window:
From: $StartTime
To: $EndTime

Collected events: $TotalEvents
Collection passed: $CollectionPassed
Collection failed: $CollectionFailed
Truncated VM collections: $TruncatedVMs

4624 - Successful logons: $LogonSuccess
4625 - Failed logons: $LogonFailure
4634 - Logoffs: $LogoffCount
4768 - TGT requests: $TGTRequests
4769 - TGS requests: $TGSRequests
4771 - Kerberos pre-auth failures: $PreAuthFailures

NOTE:
4768 and 4769 are ticket request events.
Check StatusCode before treating them as successful.

"@

$CollectionText = $CollectionResults |
    Format-Table `
        Computer, Events, Status, Truncated, Error `
        -AutoSize |
    Out-String -Width 240

$SummaryText = $Summary |
    Format-Table `
        Computer, EventID, Description, Count `
        -AutoSize |
    Out-String -Width 240

$AccountsText = $AccountStatistics |
    Sort-Object TotalEvents -Descending |
    Format-Table -AutoSize |
    Out-String -Width 240

$EventsText = $SortedEvents |
    Select-Object `
        Computer,
        TimeCreated,
        EventID,
        Classification,
        Account,
        IPAddress,
        LogonDescription,
        ServiceName,
        StatusCode,
        FailureCode |
    Format-Table -AutoSize |
    Out-String -Width 240

$ReportContent = @(
    $Header
    'COLLECTION RESULTS'
    $CollectionText
    'EVENT STATISTICS'
    $SummaryText
    'ACCOUNT STATISTICS'
    $AccountsText
    'DETAILED SECURITY EVENTS'
    $EventsText
) -join "`r`n"

$ReportContent |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 32. Build HTML report
# ----------------------------------------------------------

$CSS = @"
<style>
body {
    font-family: Arial, sans-serif;
    margin: 32px;
    background: #f5f9fb;
    color: #294554;
}
h1, h2 {
    color: #146393;
}
table {
    border-collapse: collapse;
    width: 100%;
    background: #ffffff;
    margin-bottom: 25px;
}
th {
    background: #146393;
    color: #ffffff;
    padding: 10px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 8px;
    vertical-align: top;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
.summary {
    padding: 14px;
    background: #ffffff;
    border: 1px solid #dce6eb;
    margin-bottom: 20px;
}
</style>
"@

$HTMLIntro = @"
<h1>LAB 7 - Security Log Analysis</h1>

<div class="summary">
<p><strong>Domain:</strong> $DomainName</p>
<p><strong>From:</strong> $StartTime</p>
<p><strong>To:</strong> $EndTime</p>
<p><strong>Total events:</strong> $TotalEvents</p>
<p><strong>Collection passed:</strong> $CollectionPassed</p>
<p><strong>Collection failed:</strong> $CollectionFailed</p>
<p><strong>Truncated collections:</strong> $TruncatedVMs</p>
</div>
"@

$CollectionHTML = $CollectionResults |
    ConvertTo-Html -Fragment |
    Out-String

$SummaryHTML = $Summary |
    ConvertTo-Html -Fragment |
    Out-String

$AccountsHTML = $AccountStatistics |
    ConvertTo-Html -Fragment |
    Out-String

$EventsHTML = $SortedEvents |
    Select-Object `
        Computer,
        TimeCreated,
        EventID,
        Description,
        Classification,
        Account,
        IPAddress,
        LogonDescription,
        ServiceName,
        StatusCode,
        FailureCode |
    ConvertTo-Html -Fragment |
    Out-String

$HTMLBody = @"
$HTMLIntro

<h2>Collection results</h2>
$CollectionHTML

<h2>Event statistics</h2>
$SummaryHTML

<h2>Account statistics</h2>
$AccountsHTML

<h2>Detailed Security events</h2>
$EventsHTML
"@

ConvertTo-Html `
    -Title 'LAB 7 - Security Log Analysis' `
    -Head $CSS `
    -Body $HTMLBody |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 33. Display collection results
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - SECURITY LOG COLLECTION"
Write-Host "=========================================="
Write-Host ""

$CollectionResults |
    Format-Table `
        Computer,
        Events,
        Status,
        Truncated `
        -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 34. Display event statistics
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - EVENT STATISTICS"
Write-Host "=========================================="
Write-Host ""

$Summary |
    Format-Table `
        Computer,
        EventID,
        Description,
        Count `
        -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 35. Display account statistics
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - ACCOUNT STATISTICS"
Write-Host "=========================================="
Write-Host ""

$AccountStatistics |
    Sort-Object TotalEvents -Descending |
    Select-Object -First 20 |
    Format-Table `
        Computer,
        Account,
        TotalEvents,
        SuccessfulLogons,
        FailedLogons,
        TGTRequests,
        TGSRequests,
        KerberosFailures `
        -AutoSize |
    Out-Host

# ----------------------------------------------------------
# 36. Display final statistics
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - FINAL SECURITY ANALYSIS"
Write-Host "=========================================="
Write-Host ""

Write-Host "Collected events: $TotalEvents"
Write-Host ""

Write-Host "4624 - Successful logons: $LogonSuccess"
Write-Host "4625 - Failed logons: $LogonFailure"
Write-Host "4634 - Logoffs: $LogoffCount"
Write-Host "4768 - TGT requests: $TGTRequests"
Write-Host "4769 - TGS requests: $TGSRequests"
Write-Host "4771 - Kerberos failures: $PreAuthFailures"

Write-Host ""
Write-Host "Collection passed: $CollectionPassed" `
    -ForegroundColor Green

Write-Host "Collection failed: $CollectionFailed" `
    -ForegroundColor Yellow

Write-Host "Truncated collections: $TruncatedVMs" `
    -ForegroundColor Cyan

Write-Host ""
Write-Host "Reports exported:"
Write-Host "Events CSV:     $EventsCSV"
Write-Host "Summary CSV:    $SummaryCSV"
Write-Host "Accounts CSV:   $AccountsCSV"
Write-Host "Collection CSV: $CollectionCSV"
Write-Host "TXT:            $TXT"
Write-Host "HTML:           $HTML"

# ----------------------------------------------------------
# 37. Final validation
# ----------------------------------------------------------

if ($CollectionFailed -gt 0) {

    Write-Warning (
        "LAB 7 - Some Security logs could not be collected."
    )
}
elseif ($TruncatedVMs -gt 0) {

    Write-Warning (
        "LAB 7 - At least one VM reached the event limit. " +
        "Results may be incomplete."
    )
}
elseif ($TotalEvents -eq 0) {

    Write-Warning (
        "LAB 7 - No matching Security events were found " +
        "in the selected time window."
    )
}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 7 - SECURITY LOG ANALYSIS COMPLETED"
    Write-Host "=========================================="
}
