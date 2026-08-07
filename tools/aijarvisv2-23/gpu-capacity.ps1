function Get-Task23GpuEligibility {
    param([Parameter(Mandatory = $true)][Int64]$MemoryTotalMiB)

    $runGateMet = $MemoryTotalMiB -ge 12000
    $formalMinimumMet = $MemoryTotalMiB -ge 16000
    return [pscustomobject]@{
        reported_memory_total_mib = $MemoryTotalMiB
        reported_memory_total_gib = [Math]::Round($MemoryTotalMiB / 1024.0, 3)
        portable_run_minimum_mib = 12000
        task23_formal_minimum_mib = 16000
        portable_run_gate_met = $runGateMet
        task23_formal_minimum_met = $formalMinimumMet
        evidence_scope = if ($formalMinimumMet) {
            "task23_formal_16gb_minimum_met"
        } elseif ($runGateMet) {
            "supplemental_below_16gb"
        } else {
            "below_portable_run_minimum"
        }
    }
}
