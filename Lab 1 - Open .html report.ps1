# ==========================================================
# LAB 1 - Open .html report
# Run ONLY on Hyper-V host as Administrator
# ==========================================================

Get-ChildItem 'C:\LabReports\LAB01-VM-Report_*.html' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 |
    ForEach-Object {
        Start-Process $_.FullName
    }