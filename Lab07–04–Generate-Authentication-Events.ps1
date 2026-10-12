# ==========================================================
# LAB 7 - Script 04 - Generate Authentication Events
#
# Run ONLY on host as Administrator.
# Requires Windows PowerShell 5.1 and Hyper-V.
#
# Domain: contoso.com
# Domain controller: SEA-DC1
#
# Test machines:
#   SEA-SRV1
#   SEA-SRV2
#   SEA-CL1
#
# Actions:
#   Inspect Kerberos audit policy
#   Request Kerberos service tickets
#   Attempt authenticated SMB connections
#   Collect new Security events
#   Export CSV, TXT and HTML reports
#
# The script does not change audit policies,
# clear ticket caches or intentionally fail logons.
# ==========================================================

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------
# 1. Configuration
# ----------------------------------------------------------

$DomainName = 'contoso.com'
$DCName = 'SEA-DC1'
$ReportDir = 'C:\LabReports'

$Targets = @(
    [PSCustomObject]@{
        VM = 'SEA-CL1'
        SMBTarget = 'SEA-SRV1.contoso.com'
    }
    [PSCustomObject]@{
        VM = 'SEA-SRV1'
        SMBTarget = 'SEA-SRV2.contoso.com'
    }
    [PSCustomObject]@{
        VM = 'SEA-SRV2'
        SMBTarget = 'SEA-SRV1.contoso.com'
    }
)

$EventIDs = @(4624,4625,4634,4768,4769,4771)

# ----------------------------------------------------------
# 2. Initialize host environment
# ----------------------------------------------------------

Import-Module Hyper-V -ErrorAction Stop

New-Item `
    -Path $ReportDir `
    -ItemType Directory `
    -Force | Out-Null

$Timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

$CSV = Join-Path $ReportDir `
    "LAB07-Authentication-Events_$Timestamp.csv"

$TXT = Join-Path $ReportDir `
    "LAB07-Authentication-Events_$Timestamp.txt"

$HTML = Join-Path $ReportDir `
    "LAB07-Authentication-Events_$Timestamp.html"

$ActionsCSV = Join-Path $ReportDir `
    "LAB07-Authentication-Actions_$Timestamp.csv"

$AuditTXT = Join-Path $ReportDir `
    "LAB07-Audit-Policy_$Timestamp.txt"

$Actions = [System.Collections.Generic.List[object]]::new()
$Events = [System.Collections.Generic.List[object]]::new()
$CollectionErrors = [System.Collections.Generic.List[string]]::new()

# ----------------------------------------------------------
# 3. Display header
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - GENERATE AUTHENTICATION EVENTS"
Write-Host "=========================================="
Write-Host ""
Write-Host "Host: $env:COMPUTERNAME"
Write-Host "Domain: $DomainName"
Write-Host "Domain controller: $DCName"
Write-Host "Test machines: $($Targets.Count)"
Write-Host ""

# ----------------------------------------------------------
# 4. Request domain administrator credentials
# ----------------------------------------------------------

$Credential = Get-Credential `
    -UserName 'CONTOSO\Administrator' `
    -Message 'Enter domain Administrator password'

if ($null -eq $Credential) {
    throw 'Credentials were not provided.'
}

# ----------------------------------------------------------
# 5. Verify required virtual machines
# ----------------------------------------------------------

$RequiredVMs = @(
    $DCName
    'SEA-SRV1'
    'SEA-SRV2'
    'SEA-CL1'
)

foreach ($VMName in $RequiredVMs) {

    $VM = Get-VM `
        -Name $VMName `
        -ErrorAction Stop

    if ([string]$VM.State -ne 'Running') {
        throw "Required virtual machine is not running: $VMName"
    }
}

# ----------------------------------------------------------
# 6. Inspect audit policy on domain controller
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - AUDIT POLICY INSPECTION"
Write-Host "=========================================="

$Session = $null

try {

    $Session = New-PSSession `
        -VMName $DCName `
        -Credential $Credential `
        -ErrorAction Stop

    $AuditData = Invoke-Command `
        -Session $Session `
        -ScriptBlock {

            $ErrorActionPreference = 'Stop'

            # Query existing advanced audit configuration
            $AuditOutput = @(
                & auditpol.exe /get /category:* 2>&1
            )

            $ExitCode = $LASTEXITCODE

            if ($ExitCode -ne 0) {
                throw "AUDITPOL failed with exit code $ExitCode."
            }

            # Return the audit configuration as text
            [PSCustomObject]@{
                Computer = $env:COMPUTERNAME
                ExitCode = [int]$ExitCode
                Output = ($AuditOutput -join "`r`n")
            }
        } `
        -ErrorAction Stop

    $AuditData.Output |
        Out-File `
            -FilePath $AuditTXT `
            -Encoding UTF8

    Write-Host "Audit policy exported: $AuditTXT" `
        -ForegroundColor Green

}
finally {

    if ($null -ne $Session) {
        Remove-PSSession $Session
    }
}

# ----------------------------------------------------------
# 7. Record baseline Security event IDs
# ----------------------------------------------------------

# Event RecordId is used to distinguish new events
# from entries generated before this laboratory.

Write-Host ""
Write-Host "Recording Security event baselines..." `
    -ForegroundColor Cyan

$Baseline = @{}

foreach ($VMName in $RequiredVMs) {

    $Session = $null

    try {

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        $LastRecordId = Invoke-Command `
            -Session $Session `
            -ScriptBlock {

                $Latest = Get-WinEvent `
                    -LogName Security `
                    -MaxEvents 1 `
                    -ErrorAction Stop

                [long]$Latest.RecordId
            } `
            -ErrorAction Stop

        $Baseline[$VMName] = [long]$LastRecordId

        Write-Host "$VMName baseline: $LastRecordId"

    }
    catch {

        throw (
            "Unable to read Security log baseline on " +
            "${VMName}: $($_.Exception.Message)"
        )
    }
    finally {

        if ($null -ne $Session) {
            Remove-PSSession $Session
        }
    }
}

# ----------------------------------------------------------
# 8. Generate authentication activity
# ----------------------------------------------------------

foreach ($Target in $Targets) {

    $VMName = $Target.VM
    $SMBTarget = $Target.SMBTarget

    $Session = $null

    Write-Host ""
    Write-Host "------------------------------------------"
    Write-Host "Generating activity from $VMName"
    Write-Host "Target: $SMBTarget"
    Write-Host "------------------------------------------"

    try {

        # --------------------------------------------------
        # 9. Connect using PowerShell Direct
        # --------------------------------------------------

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        # --------------------------------------------------
        # 10. Generate controlled authentication activity
        # --------------------------------------------------

        $Data = Invoke-Command `
            -Session $Session `
            -ArgumentList $SMBTarget, $DomainName `
            -ScriptBlock {

                param(
                    [string]$SMBTarget,
                    [string]$DomainName
                )

                $ErrorActionPreference = 'Stop'

                $CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

                # ------------------------------------------
                # 11. Check domain controller discovery
                # ------------------------------------------

                $DCOutput = @(
                    & nltest.exe "/dsgetdc:$DomainName" 2>&1
                )

                $DCExit = $LASTEXITCODE

                # ------------------------------------------
                # 12. Check Kerberos ticket cache
                # ------------------------------------------

                $TicketsBefore = @(
                    & klist.exe tickets 2>&1
                )

                $KlistBeforeExit = $LASTEXITCODE

                # ------------------------------------------
                # 13. Request a CIFS service ticket
                # ------------------------------------------

                $SPN = "cifs/$SMBTarget"

                $TicketOutput = @(
                    & klist.exe get $SPN 2>&1
                )

                $TicketExit = $LASTEXITCODE

                # ------------------------------------------
                # 14. Query ticket cache after request
                # ------------------------------------------

                $TicketsAfter = @(
                    & klist.exe tickets 2>&1
                )

                $KlistAfterExit = $LASTEXITCODE

                $TicketVisible = (
                    $KlistAfterExit -eq 0 -and
                    (($TicketsAfter -join "`n") -match
                        [regex]::Escape($SPN))
                )

                # ------------------------------------------
                # 15. Verify SMB TCP connectivity
                # ------------------------------------------

                $SMBPortOK = $false

                try {

                    $SMBPortOK = [bool](
                        Test-NetConnection `
                            -ComputerName $SMBTarget `
                            -Port 445 `
                            -InformationLevel Quiet `
                            -WarningAction SilentlyContinue
                    )

                }
                catch {
                    $SMBPortOK = $false
                }

                # ------------------------------------------
                # 16. Request authenticated SMB access
                # ------------------------------------------

                # IPC$ is used to request an SMB session.
                # No user files are created or modified.

                $UNC = "\\$SMBTarget\IPC$"

                $SMBAccessOK = $false
                $SMBError = ''

                try {

                    $Null = Get-Item `
                        -LiteralPath $UNC `
                        -ErrorAction Stop

                    $SMBAccessOK = $true

                }
                catch {

                    $SMBError = $_.Exception.Message
                }

                # ------------------------------------------
                # 17. Return action results
                # ------------------------------------------

                [PSCustomObject]@{
                    Computer = $env:COMPUTERNAME
                    Identity = [string]$CurrentIdentity.Name
                    Target = $SMBTarget
                    SPN = $SPN
                    DCDiscoveryOK = [bool]($DCExit -eq 0)
                    KlistBeforeOK = [bool]($KlistBeforeExit -eq 0)
                    TicketRequestOK = [bool]($TicketExit -eq 0)
                    TicketVisible = [bool]$TicketVisible
                    SMBPortOK = [bool]$SMBPortOK
                    SMBAccessOK = [bool]$SMBAccessOK
                    TicketOutput = ($TicketOutput -join ' ')
                    SMBError = $SMBError
                }

            } `
            -ErrorAction Stop

        # --------------------------------------------------
        # 18. Record the action result
        # --------------------------------------------------

        $ActionStatus = if (
            $Data.DCDiscoveryOK -and
            $Data.SMBPortOK
        ) {
            'PASS'
        }
        else {
            'FAIL'
        }

        $Actions.Add(
            [PSCustomObject]@{
                Machine = $VMName
                Identity = $Data.Identity
                Target = $SMBTarget
                SPN = $Data.SPN
                DCDiscoveryOK = $Data.DCDiscoveryOK
                TicketRequestOK = $Data.TicketRequestOK
                TicketVisible = $Data.TicketVisible
                SMBPortOK = $Data.SMBPortOK
                SMBAccessOK = $Data.SMBAccessOK
                TicketDetails = $Data.TicketOutput
                SMBError = $Data.SMBError
                Status = $ActionStatus
            }
        )

        Write-Host "DC discovery: $($Data.DCDiscoveryOK)"
        Write-Host "KLIST ticket request: $($Data.TicketRequestOK)"
        Write-Host "SMB TCP 445: $($Data.SMBPortOK)"
        Write-Host "SMB authentication: $($Data.SMBAccessOK)"

    }
    catch {

        $Message = $_.Exception.Message

        $Actions.Add(
            [PSCustomObject]@{
                Machine = $VMName
                Identity = ''
                Target = $SMBTarget
                SPN = "cifs/$SMBTarget"
                DCDiscoveryOK = $false
                TicketRequestOK = $false
                TicketVisible = $false
                SMBPortOK = $false
                SMBAccessOK = $false
                TicketDetails = ''
                SMBError = $Message
                Status = 'FAIL'
            }
        )

        Write-Warning (
            "Activity generation failed on ${VMName}: $Message"
        )
    }
    finally {

        if ($null -ne $Session) {
            Remove-PSSession $Session
        }
    }
}

# ----------------------------------------------------------
# 19. Collect newly generated Security events
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - SECURITY EVENT COLLECTION"
Write-Host "=========================================="

foreach ($VMName in $RequiredVMs) {

    $Session = $null

    try {

        $Session = New-PSSession `
            -VMName $VMName `
            -Credential $Credential `
            -ErrorAction Stop

        $EventsFromVM = Invoke-Command `
            -Session $Session `
            -ArgumentList $Baseline[$VMName], $EventIDs `
            -ScriptBlock {

                param(
                    [long]$StartRecordId,
                    [int[]]$EventIDs
                )

                $ErrorActionPreference = 'Stop'

                # Read events newer than the baseline
                $RawEvents = @(
                    Get-WinEvent `
                        -FilterHashtable @{
                            LogName = 'Security'
                            Id = $EventIDs
                        } `
                        -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.RecordId -gt $StartRecordId
                    }
                )

                foreach ($Event in $RawEvents) {

                    # Extract structured Security event data
                    $EventXML = [xml]$Event.ToXml()

                    $Fields = @{}

                    foreach ($Field in $EventXML.Event.EventData.Data) {

                        if ($Field.Name) {
                            $Fields[[string]$Field.Name] = [string]$Field.'#text'
                        }
                    }

                    $Account = if ($Fields.ContainsKey('TargetUserName')) {
                        $Fields['TargetUserName']
                    }
                    elseif ($Fields.ContainsKey('TargetUser')) {
                        $Fields['TargetUser']
                    }
                    else {
                        ''
                    }

                    $IPAddress = if ($Fields.ContainsKey('IpAddress')) {
                        $Fields['IpAddress']
                    }
                    else {
                        ''
                    }

                    $Service = if ($Fields.ContainsKey('ServiceName')) {
                        $Fields['ServiceName']
                    }
                    else {
                        ''
                    }

                    $LogonType = if ($Fields.ContainsKey('LogonType')) {
                        $Fields['LogonType']
                    }
                    else {
                        ''
                    }

                    [PSCustomObject]@{
                        Computer = $env:COMPUTERNAME
                        TimeCreated = $Event.TimeCreated
                        RecordId = [long]$Event.RecordId
                        EventID = [int]$Event.Id
                        Account = $Account
                        IPAddress = $IPAddress
                        Service = $Service
                        LogonType = $LogonType
                        Message = [string]$Event.Message
                    }
                }

            } `
            -ErrorAction Stop

        foreach ($Event in $EventsFromVM) {
            $Events.Add($Event)
        }

        Write-Host (
            "$VMName - new matching Security events: " +
            @($EventsFromVM).Count
        ) -ForegroundColor Green

    }
    catch {

        $Message = "$VMName : $($_.Exception.Message)"

        $CollectionErrors.Add($Message)

        Write-Warning $Message

    }
    finally {

        if ($null -ne $Session) {
            Remove-PSSession $Session
        }
    }
}

# ----------------------------------------------------------
# 20. Export action report
# ----------------------------------------------------------

$Actions |
    Export-Csv `
        -Path $ActionsCSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 21. Export Security events
# ----------------------------------------------------------

$SortedEvents = @(
    $Events |
    Sort-Object Computer, TimeCreated, RecordId
)

$SortedEvents |
    Select-Object `
        Computer,
        TimeCreated,
        RecordId,
        EventID,
        Account,
        IPAddress,
        Service,
        LogonType,
        Message |
    Export-Csv `
        -Path $CSV `
        -NoTypeInformation `
        -Encoding UTF8

# ----------------------------------------------------------
# 22. Calculate statistics
# ----------------------------------------------------------

$SuccessfulActions = @(
    $Actions | Where-Object Status -eq 'PASS'
).Count

$FailedActions = @(
    $Actions | Where-Object Status -eq 'FAIL'
).Count

$CollectedEvents = $SortedEvents.Count

$TGTEvents = @(
    $SortedEvents | Where-Object EventID -eq 4768
).Count

$TGSEvents = @(
    $SortedEvents | Where-Object EventID -eq 4769
).Count

$SuccessfulLogons = @(
    $SortedEvents | Where-Object EventID -eq 4624
).Count

$FailedLogons = @(
    $SortedEvents | Where-Object EventID -eq 4625
).Count

$PreAuthFailures = @(
    $SortedEvents | Where-Object EventID -eq 4771
).Count

# ----------------------------------------------------------
# 23. Export TXT report
# ----------------------------------------------------------

$Header = @"
LAB 7 - AUTHENTICATION EVENT GENERATION

Host: $env:COMPUTERNAME
Domain: $DomainName
Date: $(Get-Date)

Successful infrastructure actions: $SuccessfulActions
Failed infrastructure actions: $FailedActions

Collected Security events: $CollectedEvents

4768 - TGT requests: $TGTEvents
4769 - TGS requests: $TGSEvents
4624 - Successful logons: $SuccessfulLogons
4625 - Failed logons: $FailedLogons
4771 - Kerberos pre-authentication failures: $PreAuthFailures

Collection errors: $($CollectionErrors.Count)

NOTE:
PowerShell Direct ticket requests may not produce
interactive-user Kerberos authentication events.

"@

$ActionText = $Actions |
    Format-Table `
        Machine,
        Target,
        DCDiscoveryOK,
        TicketRequestOK,
        SMBPortOK,
        SMBAccessOK,
        Status `
        -AutoSize |
    Out-String -Width 220

$EventText = $SortedEvents |
    Format-Table `
        Computer,
        TimeCreated,
        EventID,
        Account,
        Service,
        LogonType `
        -AutoSize |
    Out-String -Width 220

$ErrorsText = $CollectionErrors -join "`r`n"

@(
    $Header
    'AUTHENTICATION ACTIONS'
    $ActionText
    'SECURITY EVENTS'
    $EventText
    'COLLECTION ERRORS'
    $ErrorsText
) -join "`r`n" |
    Out-File `
        -FilePath $TXT `
        -Encoding UTF8

# ----------------------------------------------------------
# 24. Export HTML report
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
}
th {
    background: #146393;
    color: #ffffff;
    padding: 9px;
    text-align: left;
}
td {
    border: 1px solid #dce6eb;
    padding: 8px;
}
tr:nth-child(even) {
    background: #f5f9fb;
}
</style>
"@

$ActionHTML = $Actions |
    ConvertTo-Html -Fragment |
    Out-String

$EventHTML = $SortedEvents |
    Select-Object `
        Computer,
        TimeCreated,
        EventID,
        Account,
        IPAddress,
        Service,
        LogonType |
    ConvertTo-Html -Fragment |
    Out-String

$HTMLBody = @"
<h1>LAB 7 - Authentication Events</h1>

<p>Domain: $DomainName</p>
<p>Successful actions: $SuccessfulActions</p>
<p>Failed actions: $FailedActions</p>
<p>Collected events: $CollectedEvents</p>

<h2>Authentication activity</h2>
$ActionHTML

<h2>Security events</h2>
$EventHTML
"@

ConvertTo-Html `
    -Title 'LAB 7 - Authentication Events' `
    -Head $CSS `
    -Body $HTMLBody |
    Out-File `
        -FilePath $HTML `
        -Encoding UTF8

# ----------------------------------------------------------
# 25. Display final report
# ----------------------------------------------------------

Write-Host ""
Write-Host "=========================================="
Write-Host "LAB 7 - AUTHENTICATION EVENT REPORT"
Write-Host "=========================================="
Write-Host ""

$Actions |
    Format-Table `
        Machine,
        Target,
        TicketRequestOK,
        SMBAccessOK,
        Status `
        -AutoSize |
    Out-Host

Write-Host ""
Write-Host "Successful actions: $SuccessfulActions"
Write-Host "Failed actions: $FailedActions"
Write-Host "Collected events: $CollectedEvents"

Write-Host ""
Write-Host "4768 - TGT requests: $TGTEvents"
Write-Host "4769 - TGS requests: $TGSEvents"
Write-Host "4624 - Successful logons: $SuccessfulLogons"
Write-Host "4625 - Failed logons: $FailedLogons"
Write-Host "4771 - Pre-auth failures: $PreAuthFailures"

Write-Host ""
Write-Host "Collection errors: $($CollectionErrors.Count)"

Write-Host ""
Write-Host "Reports exported:"
Write-Host "Actions CSV: $ActionsCSV"
Write-Host "Events CSV:  $CSV"
Write-Host "TXT:         $TXT"
Write-Host "HTML:        $HTML"
Write-Host "Audit TXT:   $AuditTXT"

# ----------------------------------------------------------
# 26. Final validation
# ----------------------------------------------------------

if (
    $FailedActions -gt 0 -or
    $CollectionErrors.Count -gt 0
) {

    Write-Warning (
        "LAB 7 - Some infrastructure checks or event " +
        "collections require attention."
    )

}
else {

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "LAB 7 - EVENT GENERATION COMPLETED"
    Write-Host "==========================================" 
}

