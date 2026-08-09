#requires -Version 5.1

Set-StrictMode -Version Latest

function Get-Task23CodepointCount {
    param([AllowEmptyString()][string]$Value)
    $count = 0
    for ($index = 0; $index -lt $Value.Length; ++$index) {
        if ([char]::IsHighSurrogate($Value[$index]) -and $index + 1 -lt $Value.Length -and
            [char]::IsLowSurrogate($Value[$index + 1])) {
            ++$index
        }
        ++$count
    }
    return $count
}

function ConvertFrom-Task23CompleteJson {
    param([AllowEmptyString()][string]$Raw)
    try {
        return [pscustomobject]@{ complete = $true; value = ($Raw | ConvertFrom-Json) }
    } catch {
        return [pscustomobject]@{ complete = $false; value = $null }
    }
}

function Get-Task23BatchValidation {
    param(
        [Parameter(Mandatory = $true)]$Parsed,
        [Parameter(Mandatory = $true)][string[]]$StyleIds,
        [Parameter(Mandatory = $true)][int]$MinimumItems,
        [Parameter(Mandatory = $true)][int]$MaximumItems,
        [Parameter(Mandatory = $true)][int]$BudgetChars,
        [AllowEmptyString()][string]$Raw
    )
    $result = [ordered]@{
        schema_valid = $false
        schema_error = "invalid_root"
        batch_count = 0
        response_chars = Get-Task23CodepointCount -Value $Raw
        batches = $null
    }
    if ($null -eq $Parsed -or $null -eq $Parsed.PSObject.Properties["batches"]) { return [pscustomobject]$result }
    $batches = @($Parsed.batches)
    $result.batch_count = $batches.Count
    $result.batches = $batches
    if ($batches.Count -ne 3) {
        $result.schema_error = "batch_count"
        return [pscustomobject]$result
    }
    for ($index = 0; $index -lt 3; ++$index) {
        $batch = $batches[$index]
        if ($null -eq $batch -or $null -eq $batch.PSObject.Properties["style_id"] -or
            [string]$batch.style_id -ne $StyleIds[$index] -or $null -eq $batch.PSObject.Properties["items"]) {
            $result.schema_error = "batch_schema"
            return [pscustomobject]$result
        }
        $items = @($batch.items)
        if ($items.Count -lt $MinimumItems -or $items.Count -gt $MaximumItems) {
            $result.schema_error = "batch_schema"
            return [pscustomobject]$result
        }
        foreach ($item in $items) {
            if ($item -isnot [string] -or [string]::IsNullOrEmpty([string]$item)) {
                $result.schema_error = "batch_schema"
                return [pscustomobject]$result
            }
        }
    }
    if ($BudgetChars -gt 0 -and $result.response_chars -gt $BudgetChars) {
        $result.schema_error = "budget_exceeded"
        return [pscustomobject]$result
    }
    $result.schema_valid = $true
    $result.schema_error = $null
    return [pscustomobject]$result
}

function New-Task23AggregateRecord {
    param(
        [Parameter(Mandatory = $true)]$Current,
        [Parameter(Mandatory = $true)][string]$CompletionBasis,
        $ParsedResult,
        [Parameter(Mandatory = $true)][string[]]$StyleIds,
        [Parameter(Mandatory = $true)][int]$MinimumItems,
        [Parameter(Mandatory = $true)][int]$MaximumItems,
        [Parameter(Mandatory = $true)][int]$BudgetChars
    )
    $complete = $null -ne $ParsedResult -and [bool]$ParsedResult.complete
    $validation = if ($complete) {
        Get-Task23BatchValidation -Parsed $ParsedResult.value -StyleIds $StyleIds `
            -MinimumItems $MinimumItems -MaximumItems $MaximumItems -BudgetChars $BudgetChars -Raw ([string]$Current.text)
    } else {
        [pscustomobject]@{
            schema_valid = $false; schema_error = "incomplete_json"; batch_count = 0
            response_chars = Get-Task23CodepointCount -Value ([string]$Current.text); batches = $null
        }
    }
    return [pscustomobject]([ordered]@{
        aggregate_id = [int]$Current.aggregate_id
        generation_id = [int]$Current.generation_id
        first_asset_sequence = [int64]$Current.first_asset_sequence
        last_asset_sequence = [int64]$Current.last_asset_sequence
        fragment_count = [int]$Current.fragment_count
        aggregated_text = [string]$Current.text
        completion_basis = $CompletionBasis
        json_parse_complete = $complete
        schema_valid = [bool]$validation.schema_valid
        schema_error = $validation.schema_error
        batch_count = [int]$validation.batch_count
        response_chars = [int]$validation.response_chars
        batches = $validation.batches
    })
}

function Invoke-Task23SpeakAggregation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$FragmentPath,
        [Parameter(Mandatory = $true)][string]$SummaryPath,
        [Parameter(Mandatory = $true)][string[]]$StyleIds,
        [Parameter(Mandatory = $true)][int]$MinimumItems,
        [Parameter(Mandatory = $true)][int]$MaximumItems,
        [Parameter(Mandatory = $true)][int]$BudgetChars
    )
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $events = @()
    foreach ($line in Get-Content -LiteralPath $InputPath -Encoding UTF8) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { $events += ($line | ConvertFrom-Json) }
    }
    $fragments = @()
    $aggregates = @()
    $current = $null
    $nextAggregateId = 1
    $failedResults = 0
    $listenResults = 0
    $speakResults = 0

    foreach ($event in $events) {
        if ($event.event -ne "duplex_result") { continue }
        $generation = [int]$event.run_generation
        if ($null -ne $current -and [int]$current.generation_id -ne $generation) {
            $aggregates += New-Task23AggregateRecord -Current $current `
                -CompletionBasis "generation_change_without_complete_json" -ParsedResult $null `
                -StyleIds $StyleIds -MinimumItems $MinimumItems -MaximumItems $MaximumItems -BudgetChars $BudgetChars
            $current = $null
        }
        if (-not [bool]$event.ok) {
            ++$failedResults
            if ($null -ne $current) {
                $aggregates += New-Task23AggregateRecord -Current $current `
                    -CompletionBasis "failed_result_boundary" -ParsedResult $null `
                    -StyleIds $StyleIds -MinimumItems $MinimumItems -MaximumItems $MaximumItems -BudgetChars $BudgetChars
                $current = $null
            }
            continue
        }
        if (-not [bool]$event.is_speak) {
            ++$listenResults
            if ($null -ne $current) {
                $aggregates += New-Task23AggregateRecord -Current $current `
                    -CompletionBasis "listen_boundary_without_complete_json" -ParsedResult $null `
                    -StyleIds $StyleIds -MinimumItems $MinimumItems -MaximumItems $MaximumItems -BudgetChars $BudgetChars
                $current = $null
            }
            continue
        }

        ++$speakResults
        if ($null -eq $current) {
            $current = [ordered]@{
                aggregate_id = $nextAggregateId; generation_id = $generation
                first_asset_sequence = [int64]$event.asset_sequence
                last_asset_sequence = [int64]$event.asset_sequence
                fragment_count = 0; text = ""
            }
            ++$nextAggregateId
        }
        $current.last_asset_sequence = [int64]$event.asset_sequence
        ++$current.fragment_count
        $rawFragment = if ($null -eq $event.raw_response) { "" } else { [string]$event.raw_response }
        $current.text = [string]$current.text + $rawFragment
        $parsed = ConvertFrom-Task23CompleteJson -Raw ([string]$current.text)
        $validationStatus = "awaiting_completion"
        if ($parsed.complete) {
            $validation = Get-Task23BatchValidation -Parsed $parsed.value -StyleIds $StyleIds `
                -MinimumItems $MinimumItems -MaximumItems $MaximumItems -BudgetChars $BudgetChars -Raw ([string]$current.text)
            $validationStatus = if ($validation.schema_valid) { "completed_valid_json" } else { "completed_invalid_schema" }
        }
        $fragments += [pscustomobject]([ordered]@{
            aggregate_id = [int]$current.aggregate_id
            generation_id = $generation
            fragment_index = [int]$current.fragment_count
            asset_sequence = [int64]$event.asset_sequence
            user_seq = [int64]$event.user_seq
            frame_id = [int64]$event.frame_id
            monotonic_timestamp_us = $event.monotonic_timestamp_us
            utc_timestamp = $event.utc_timestamp
            raw_fragment = $rawFragment
            aggregate_chars_after_fragment = Get-Task23CodepointCount -Value ([string]$current.text)
            validation_status = $validationStatus
        })
        if ($parsed.complete) {
            $aggregates += New-Task23AggregateRecord -Current $current `
                -CompletionBasis "aggregate_json_parse_complete" -ParsedResult $parsed `
                -StyleIds $StyleIds -MinimumItems $MinimumItems -MaximumItems $MaximumItems -BudgetChars $BudgetChars
            $current = $null
        }
    }
    if ($null -ne $current) {
        $aggregates += New-Task23AggregateRecord -Current $current `
            -CompletionBasis "evidence_end_without_complete_json" -ParsedResult $null `
            -StyleIds $StyleIds -MinimumItems $MinimumItems -MaximumItems $MaximumItems -BudgetChars $BudgetChars
    }
    $validCount = @($aggregates | Where-Object schema_valid).Count
    $summary = [ordered]@{
        schema_version = 1
        completion_rule = "contiguous ok:true SPEAK fragments in one run_generation; close at complete JSON or explicit result boundary"
        completion_field_available = $false
        speak_results = $speakResults
        listen_results = $listenResults
        failed_results = $failedResults
        fragment_count = $fragments.Count
        aggregate_count = $aggregates.Count
        valid_three_batch_aggregates = $validCount
        fragments = @($fragments)
        aggregates = @($aggregates)
    }
    $fragmentLines = @($fragments | ForEach-Object { $_ | ConvertTo-Json -Depth 16 -Compress })
    $fragmentText = $fragmentLines -join [Environment]::NewLine
    if ($fragmentLines.Count) { $fragmentText += [Environment]::NewLine }
    [IO.File]::WriteAllText($FragmentPath, $fragmentText, $Utf8NoBom)
    [IO.File]::WriteAllText($SummaryPath, ($summary | ConvertTo-Json -Depth 32) + [Environment]::NewLine, $Utf8NoBom)
    return [pscustomobject]$summary
}
