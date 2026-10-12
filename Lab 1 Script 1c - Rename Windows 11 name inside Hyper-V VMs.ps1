# =====================================================
# LAB 1 Script 1c - Rename Windows 11 name inside Hyper-V VMs
# Run on Hyper-V host as Administrator
# =====================================================

Invoke-Command `
    -VMName 'SEA-CL1' `
    -Credential (Get-Credential `
        -UserName '.\Admin' `
        -Message 'Enter password for SEA-CL1') `
    -ScriptBlock {
        Rename-Computer `
            -NewName 'SEA-CL1' `
            -Force
    }

Restart-VM -Name 'SEA-CL1'