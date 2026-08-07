#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ModelRoot,
    [string]$InputRoot,
    [string]$ResultRoot,
    [ValidateRange(250, 5000)][int]$SamplingIntervalMs = 500,
    [ValidateRange(1, 5)][int]$Repetitions = 1,
    [ValidateRange(5, 120)][int]$CaseTimeoutMinutes = 45
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PortableManifestPath = Join-Path $ToolRoot "portable-manifest.json"
$PortableMode = Test-Path -LiteralPath $PortableManifestPath -PathType Leaf
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $ToolRoot "..\.."))
if (-not $ModelRoot -or -not $InputRoot) {
    throw "Specify -ModelRoot and -InputRoot. See README.md beside this script for the fixed MODEL_ROOT and O_IN_07_ROOT layouts."
}
$ModelRoot = [IO.Path]::GetFullPath($ModelRoot)
$InputRoot = [IO.Path]::GetFullPath($InputRoot)
$RunId = "O10-P23-{0}-WIN-01" -f (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
if (-not $ResultRoot) {
    $ResultRoot = if ($PortableMode) {
        Join-Path $ToolRoot "results\$RunId"
    } else {
        Join-Path $RepositoryRoot "build\task23-poc\results\$RunId"
    }
}
$ResultRoot = [IO.Path]::GetFullPath($ResultRoot)
$BuildRoot = Join-Path $RepositoryRoot "build\task23-poc\windows-x64-cuda"
$RuntimeSource = Join-Path $RepositoryRoot "build\task23-poc\runtime-source"
$AggregateEvidence = Join-Path $ResultRoot "evidence.jsonl"
$ResourceEvidence = Join-Path $ResultRoot "resource-samples.jsonl"
$PreflightPath = Join-Path $ResultRoot "preflight.json"
$SummaryPath = Join-Path $ResultRoot "summary.json"
$InputManifestPath = Join-Path $InputRoot "manifest.json"
$ModelProvenancePath = Join-Path $ModelRoot "MODEL_PROVENANCE.json"
$TemplateRoot = if ($PortableMode) { Join-Path $ToolRoot "templates" } else { Join-Path $RepositoryRoot "docs\v2\requirements\templates" }
$PerformanceTemplate = Join-Path $TemplateRoot "performance-sample-record.csv"
$ResourceTemplate = Join-Path $TemplateRoot "resource-trend-record.csv"
$ReliabilityTemplate = Join-Path $TemplateRoot "reliability-event-record.csv"
$ConfigSnapshotHash = ""
$ApplicationVersion = ""
$HardwareProfileId = ""
$PortableManifest = $null

. (Join-Path $ToolRoot "gpu-capacity.ps1")

New-Item -ItemType Directory -Path $ResultRoot -Force | Out-Null

function Write-JsonFile {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Add-JsonLine {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $line = $Value | ConvertTo-Json -Depth 32 -Compress
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-File {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = "file")
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing ${Label}: $Path"
    }
}

function Assert-ExactFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][Int64]$Size,
        [Parameter(Mandatory = $true)][string]$Sha256
    )
    Assert-File -Path $Path -Label "pinned file"
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -ne $Size) {
        throw "Pinned file size mismatch: $Path (expected $Size, actual $($file.Length))"
    }
    $actualHash = Get-Sha256 -Path $Path
    if ($actualHash -ne $Sha256.ToLowerInvariant()) {
        throw "Pinned file SHA-256 mismatch: $Path"
    }
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [string]$Label = "file"
    )
    Assert-File -Path $Path -Label $Label
    if ((Get-Sha256 -Path $Path) -ne $Sha256.ToLowerInvariant()) {
        throw "$Label SHA-256 mismatch: $Path"
    }
}

function Assert-FieldInputSlots {
    $requiredSlots = @(
        @{ root = $ModelRoot; path = "MiniCPM-o-4_5-Q4_K_M.gguf"; label = "MODEL_ROOT" },
        @{ root = $ModelRoot; path = "vision\MiniCPM-o-4_5-vision-F16.gguf"; label = "MODEL_ROOT" },
        @{ root = $ModelRoot; path = "audio\MiniCPM-o-4_5-audio-F16.gguf"; label = "MODEL_ROOT" },
        @{ root = $ModelRoot; path = "LICENSE.Apache-2.0.txt"; label = "MODEL_ROOT" },
        @{ root = $ModelRoot; path = "MODEL_CARD.md"; label = "MODEL_ROOT" },
        @{ root = $ModelRoot; path = "MODEL_PROVENANCE.json"; label = "MODEL_ROOT" },
        @{ root = $InputRoot; path = "manifest.json"; label = "O_IN_07_ROOT" }
    )
    $missing = @($requiredSlots | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $_.root $_.path) -PathType Leaf)
    } | ForEach-Object { "$($_.label)\$($_.path)" })
    if ($missing.Count -ne 0) {
        throw "Field inputs are incomplete. Place the fixed files under MODEL_ROOT=$ModelRoot and O_IN_07_ROOT=$InputRoot. Missing: $($missing -join ', '). Use the templates beside this script; no compiler or download is attempted."
    }
}

function Get-PortableManifest {
    if ($null -ne $script:PortableManifest) { return $script:PortableManifest }
    Assert-File -Path $PortableManifestPath -Label "portable manifest"
    $manifest = Get-Content -LiteralPath $PortableManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.artifact_name -ne "AIJARVISV2-23-windows-x64-cuda-portable" -or
        $manifest.runtime_revision -ne "b9d15b83ee353b2eaeee4d9318c98a35a1347486" -or
        $manifest.runtime_patch_sha256 -ne "cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e" -or
        $manifest.runtime_license_sha256 -ne "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d") {
        throw "Portable package identity does not match O-C01"
    }
    foreach ($entry in @($manifest.files)) {
        $relativePath = [string]$entry.path
        if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath -match "(^|[\\/])\.\.([\\/]|$)") {
            throw "Portable manifest contains an unsafe path: $relativePath"
        }
        Assert-ExactFile -Path (Join-Path $ToolRoot $relativePath.Replace("/", "\")) `
            -Size ([int64]$entry.size) -Sha256 ([string]$entry.sha256)
    }
    $script:PortableManifest = $manifest
    return $script:PortableManifest
}

function Get-SourceCommit {
    if ($PortableMode) {
        return [string](Get-PortableManifest).source_commit
    }
    return (& git.exe -C $RepositoryRoot rev-parse HEAD).Trim()
}

function Test-JsonlEvent {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Event)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if (-not $line) { continue }
        try {
            if (($line | ConvertFrom-Json).event -eq $Event) { return $true }
        } catch {
            throw "Invalid JSONL in $Path"
        }
    }
    return $false
}

function Get-GpuSnapshot {
    $line = & nvidia-smi.exe --query-gpu=index,name,uuid,driver_version,memory.total,memory.used,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if (-not $line) { throw "nvidia-smi did not return a GPU snapshot" }
    $parts = @($line -split "," | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 7) { throw "Unexpected nvidia-smi GPU output" }
    return [pscustomobject]@{
        index = [int]$parts[0]
        name = $parts[1]
        uuid = $parts[2]
        driver_version = $parts[3]
        memory_total_mib = [int]$parts[4]
        memory_used_mib = [int]$parts[5]
        utilization_gpu_percent = [int]$parts[6]
    }
}

function Get-ComputeApplications {
    $rows = @(& nvidia-smi.exe --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>$null)
    $applications = @()
    foreach ($row in $rows) {
        if (-not $row) { continue }
        $parts = @($row -split "," | ForEach-Object { $_.Trim() })
        if ($parts.Count -ge 3 -and $parts[0] -match "^\d+$") {
            $applications += [pscustomobject]@{
                pid = [int]$parts[0]
                process_name = $parts[1]
                used_memory_mib = if ($parts[2] -match "^\d+$") { [int]$parts[2] } else { $null }
            }
        }
    }
    return @($applications)
}

function Get-MonotonicUs {
    return [Diagnostics.Stopwatch]::GetTimestamp() * 1000000.0 / [Diagnostics.Stopwatch]::Frequency
}

function Get-QuotedArgument {
    param([string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Write-TemplateCsv {
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][object[]]$Rows
    )
    $headers = @((Get-Content -LiteralPath $Template -TotalCount 1) -split ",")
    if ($Rows.Count -eq 0) {
        $headers -join "," | Set-Content -LiteralPath $Destination -Encoding UTF8
        return
    }
    $objects = foreach ($row in $Rows) {
        $ordered = [ordered]@{}
        foreach ($header in $headers) {
            $property = $row.PSObject.Properties[$header]
            $ordered[$header] = if ($null -ne $property) { $property.Value } else { "" }
        }
        [pscustomobject]$ordered
    }
    $objects | Export-Csv -LiteralPath $Destination -NoTypeInformation -Encoding UTF8
}

function Get-NearestRank {
    param([double[]]$Values, [double]$Percentile)
    if ($Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $index = [Math]::Ceiling($Percentile * $sorted.Count) - 1
    return $sorted[[Math]::Max(0, $index)]
}

function Invoke-Preflight {
    Assert-FieldInputSlots
    if (-not [Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw "Windows x64 is required"
    }
    if ([Environment]::OSVersion.Version.Build -lt 22000) {
        throw "Windows 11 build 22000 or later is required"
    }
    $requiredCommands = if ($PortableMode) {
        @("nvidia-smi.exe")
    } else {
        @("git.exe", "cmake.exe", "nvcc.exe", "nvidia-smi.exe")
    }
    foreach ($command in $requiredCommands) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Required command is missing: $command"
        }
    }
    $portableManifest = if ($PortableMode) { Get-PortableManifest } else { $null }

    $physicalAdapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object Status -eq "Up")
    if ($physicalAdapters.Count -ne 0) {
        throw "Disconnect physical network adapters before the offline PoC: $($physicalAdapters.Name -join ', ')"
    }

    $gpu = Get-GpuSnapshot
    $gpuEligibility = Get-Task23GpuEligibility -MemoryTotalMiB $gpu.memory_total_mib
    if (-not $gpuEligibility.portable_run_gate_met) {
        throw "The portable PoC requires an NVIDIA GPU with at least 12GB nominal VRAM; nvidia-smi reports $($gpu.memory_total_mib) MiB"
    }
    $existingGpuProcesses = @(Get-ComputeApplications)
    if ($existingGpuProcesses.Count -ne 0) {
        throw "GPU must be exclusive before the run; existing compute PIDs: $($existingGpuProcesses.pid -join ', ')"
    }

    Assert-ExactFile -Path (Join-Path $ModelRoot "MiniCPM-o-4_5-Q4_K_M.gguf") `
        -Size 5026714400 -Sha256 "1237a97ee081b8abebc47aa7dad565701e8f5f904cdc92f6723ac4281bbc0932"
    Assert-ExactFile -Path (Join-Path $ModelRoot "vision\MiniCPM-o-4_5-vision-F16.gguf") `
        -Size 1095113184 -Sha256 "1453678cc4e4fe18de241952962e234f265cb8dda780773526103ab8ba82f421"
    Assert-ExactFile -Path (Join-Path $ModelRoot "audio\MiniCPM-o-4_5-audio-F16.gguf") `
        -Size 660167904 -Sha256 "d5b188ac7feaf98e17175c3f9bd14bf269301bfd187439fdaa3e3a494fc32ef7"
    foreach ($name in @("LICENSE.Apache-2.0.txt", "MODEL_CARD.md", "MODEL_PROVENANCE.json")) {
        $path = Join-Path $ModelRoot $name
        Assert-File -Path $path -Label "model license/provenance material"
        if ((Get-Item -LiteralPath $path).Length -eq 0) { throw "Empty model material: $path" }
    }
    $forbiddenModelFiles = @(Get-ChildItem -LiteralPath $ModelRoot -Recurse -File | Where-Object {
        $_.Name -match "(?i)(default_ref_audio|token2wav|projector|tts.*\.gguf)"
    })
    if ($forbiddenModelFiles.Count -ne 0) {
        throw "TTS, projector, token2wav, or reference-audio files are forbidden in MODEL_ROOT"
    }
    $provenance = Get-Content -LiteralPath $ModelProvenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($provenance.repo_id -ne "openbmb/MiniCPM-o-4_5-gguf" -or
        $provenance.revision -ne "502eec5b03eaee9d0d2ce17a176e3490103c9a63" -or
        $provenance.quantization -ne "Q4_K_M LLM with F16 vision and audio projectors" -or
        -not $provenance.attribution -or -not $provenance.upstream_notice -or
        @($provenance.files).Count -ne 3) {
        throw "MODEL_PROVENANCE.json does not identify the pinned model and notice decision"
    }
    $expectedModelFiles = @{
        "MiniCPM-o-4_5-Q4_K_M.gguf" = @{ size = 5026714400; sha256 = "1237a97ee081b8abebc47aa7dad565701e8f5f904cdc92f6723ac4281bbc0932" }
        "vision/MiniCPM-o-4_5-vision-F16.gguf" = @{ size = 1095113184; sha256 = "1453678cc4e4fe18de241952962e234f265cb8dda780773526103ab8ba82f421" }
        "audio/MiniCPM-o-4_5-audio-F16.gguf" = @{ size = 660167904; sha256 = "d5b188ac7feaf98e17175c3f9bd14bf269301bfd187439fdaa3e3a494fc32ef7" }
    }
    foreach ($entry in @($provenance.files)) {
        $expected = $expectedModelFiles[[string]$entry.path]
        if ($null -eq $expected -or [int64]$entry.size -ne [int64]$expected.size -or
            ([string]$entry.sha256).ToLowerInvariant() -ne $expected.sha256) {
            throw "MODEL_PROVENANCE.json contains a non-pinned file identity: $($entry.path)"
        }
    }

    Assert-File -Path $InputManifestPath -Label "O-IN-07 manifest"
    $manifest = Get-Content -LiteralPath $InputManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.input_id -ne "O-IN-07" -or -not $manifest.deidentified -or
        -not $manifest.rights_confirmed -or $manifest.authorization_ref -match "^REPLACE_" -or
        [int64]$manifest.duration_ms -lt 30000 -or @($manifest.style_ids).Count -ne 3 -or
        @($manifest.chunks).Count -lt 10) {
        throw "O-IN-07 manifest identity, rights, duration, styles, or chunk count is invalid"
    }
    foreach ($metadata in @(
        @{ path = $manifest.authorization_record; hash = $manifest.authorization_sha256; label = "authorization" },
        @{ path = $manifest.gold_record; hash = $manifest.gold_sha256; label = "gold record" }
    )) {
        if ($metadata.hash -match "^REPLACE_") { throw "Missing $($metadata.label) SHA-256" }
        $path = Join-Path $InputRoot ([string]$metadata.path)
        Assert-Sha256 -Path $path -Sha256 ([string]$metadata.hash) -Label $metadata.label
    }
    $previousOffset = -1
    $previousSequence = 0
    foreach ($chunk in @($manifest.chunks)) {
        if ([int64]$chunk.sequence -le $previousSequence -or
            [int64]$chunk.offset_ms -le $previousOffset -or
            [int64]$chunk.duration_ms -ne 3000 -or -not $chunk.marker) {
            throw "O-IN-07 sequence/offsets must increase, each duration must be 3000 ms, and markers must be non-empty"
        }
        if ($previousOffset -ge 0 -and ([int64]$chunk.offset_ms - $previousOffset) -gt 3000) {
            throw "O-IN-07 has an input timeline gap greater than 3000 ms"
        }
        $previousSequence = [int64]$chunk.sequence
        $previousOffset = [int64]$chunk.offset_ms
        foreach ($asset in @(
            @{ path = $chunk.audio; hash = $chunk.audio_sha256 },
            @{ path = $chunk.image; hash = $chunk.image_sha256 }
        )) {
            if ($asset.hash -match "^REPLACE_") { throw "O-IN-07 asset SHA-256 is missing" }
            $assetPath = Join-Path $InputRoot ([string]$asset.path)
            Assert-Sha256 -Path $assetPath -Sha256 ([string]$asset.hash) -Label "O-IN-07 asset"
        }
    }
    if ($previousOffset -lt 30000) { throw "O-IN-07 chunk timeline must reach at least 30000 ms" }

    if ($PortableMode) {
        $runtimeRevision = [string]$portableManifest.runtime_revision
        $runtimePatchSha256 = [string]$portableManifest.runtime_patch_sha256
        $runtimeLicenseSha256 = [string]$portableManifest.runtime_license_sha256
    } else {
        $vendorManifestPath = Join-Path $RepositoryRoot "third_party\runtime\VENDOR.json"
        $vendorManifest = Get-Content -LiteralPath $vendorManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($vendorManifest.upstream.revision -ne "b9d15b83ee353b2eaeee4d9318c98a35a1347486") {
            throw "Pinned runtime revision mismatch"
        }
        Assert-Sha256 -Path (Join-Path $RepositoryRoot "third_party\runtime\patches\0001-text-input-runtime.patch") `
            -Sha256 "cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e" -Label "runtime patch"
        Assert-Sha256 -Path (Join-Path $RepositoryRoot "third_party\runtime\LICENSE.llama.cpp-omni") `
            -Sha256 "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d" -Label "runtime license"
        $runtimeRevision = [string]$vendorManifest.upstream.revision
        $runtimePatchSha256 = [string]$vendorManifest.patches[0].sha256
        $runtimeLicenseSha256 = Get-Sha256 -Path (Join-Path $RepositoryRoot "third_party\runtime\LICENSE.llama.cpp-omni")
    }

    $head = Get-SourceCommit
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors
    $computer = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1 Manufacturer, Model, TotalPhysicalMemory
    $powerScheme = (& powercfg.exe /getactivescheme 2>$null | Out-String).Trim()
    return [pscustomobject]@{
        schema_version = 1
        run_id = $RunId
        status = "passed"
        execution_mode = if ($PortableMode) { "portable_prebuilt" } else { "source_build" }
        checked_at = (Get-Date).ToUniversalTime().ToString("o")
        repository_head = $head
        os_version = [Environment]::OSVersion.Version.ToString()
        os_architecture = "x64"
        cpu = $cpu
        computer = $computer
        active_power_scheme = $powerScheme
        gpu = $gpu
        gpu_eligibility = $gpuEligibility
        task23_formal_minimum_met = $gpuEligibility.task23_formal_minimum_met
        initial_compute_applications = $existingGpuProcesses
        model_root = $ModelRoot
        model_provenance_sha256 = Get-Sha256 -Path $ModelProvenancePath
        model_license_sha256 = Get-Sha256 -Path (Join-Path $ModelRoot "LICENSE.Apache-2.0.txt")
        model_card_sha256 = Get-Sha256 -Path (Join-Path $ModelRoot "MODEL_CARD.md")
        model_files = @($provenance.files | ForEach-Object {
            [pscustomobject]@{ path = $_.path; size = $_.size; sha256 = $_.sha256 }
        })
        input_manifest = $InputManifestPath
        input_manifest_sha256 = Get-Sha256 -Path $InputManifestPath
        authorization_record_sha256 = Get-Sha256 -Path (Join-Path $InputRoot ([string]$manifest.authorization_record))
        gold_record_sha256 = Get-Sha256 -Path (Join-Path $InputRoot ([string]$manifest.gold_record))
        runtime_revision = $runtimeRevision
        runtime_patch_sha256 = $runtimePatchSha256
        runtime_license_sha256 = $runtimeLicenseSha256
        tts_files_present = 0
        reference_audio_present = $false
        physical_network_adapters_up = 0
    }
}

function Prepare-RuntimeSource {
    if (Test-Path -LiteralPath $RuntimeSource) {
        Remove-Item -LiteralPath $RuntimeSource -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $RepositoryRoot "third_party\runtime\vendor") `
        -Destination $RuntimeSource -Recurse -Force
    $defaultReferenceAudio = Join-Path $RuntimeSource "tools\omni\assets\default_ref_audio"
    if (Test-Path -LiteralPath $defaultReferenceAudio) {
        Remove-Item -LiteralPath $defaultReferenceAudio -Recurse -Force
    }
    if (Test-Path -LiteralPath $defaultReferenceAudio) {
        throw "Failed to remove default reference audio from the isolated runtime source"
    }
    Push-Location $RuntimeSource
    try {
        & git.exe apply (Join-Path $RepositoryRoot "third_party\runtime\patches\0001-text-input-runtime.patch")
        if ($LASTEXITCODE -ne 0) { throw "Failed to apply pinned runtime patch" }
    } finally {
        Pop-Location
    }
}

function Build-Harness {
    Prepare-RuntimeSource
    if (Test-Path -LiteralPath $BuildRoot) {
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
    $configureLog = Join-Path $ResultRoot "cmake-configure.log"
    $buildLog = Join-Path $ResultRoot "cmake-build.log"
    & cmake.exe -S $ToolRoot -B $BuildRoot -G "Visual Studio 17 2022" -A x64 `
        -DGGML_CUDA=ON -DGGML_CUDA_NCCL=OFF `
        "-DJARVIS_RUNTIME_UPSTREAM_SOURCE_DIR=$RuntimeSource" 2>&1 | Tee-Object -FilePath $configureLog
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
    & cmake.exe --build $BuildRoot --config Release --target aijarvisv2-task23-poc --parallel `
        2>&1 | Tee-Object -FilePath $buildLog
    if ($LASTEXITCODE -ne 0) { throw "PoC harness build failed" }
    $executable = Join-Path $BuildRoot "Release\aijarvisv2-task23-poc.exe"
    Assert-File -Path $executable -Label "PoC harness"
    Write-JsonFile -Path (Join-Path $ResultRoot "build-manifest.json") -Value ([ordered]@{
        schema_version = 1; run_id = $RunId; generator = "Visual Studio 17 2022"; architecture = "x64"
        ggml_cuda = $true; ggml_cuda_nccl = $false
        runtime_revision = "b9d15b83ee353b2eaeee4d9318c98a35a1347486"
        runtime_patch_sha256 = "cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e"
        harness_source_sha256 = Get-Sha256 -Path (Join-Path $ToolRoot "poc_main.cpp")
        cmake_source_sha256 = Get-Sha256 -Path (Join-Path $ToolRoot "CMakeLists.txt")
        executable_sha256 = Get-Sha256 -Path $executable
        tts_enabled = $false; reference_audio = ""; model_instance_limit = 1
        default_reference_audio_present = Test-Path -LiteralPath (Join-Path $RuntimeSource "tools\omni\assets\default_ref_audio\default_ref_audio.wav")
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
    })
    return $executable
}

function Resolve-Harness {
    if (-not $PortableMode) { return (Build-Harness) }
    $executable = Join-Path $ToolRoot "bin\aijarvisv2-task23-poc.exe"
    Assert-File -Path $executable -Label "prebuilt PoC harness"
    $portableBuildManifest = Join-Path $ToolRoot "portable-build-manifest.json"
    Assert-File -Path $portableBuildManifest -Label "portable build manifest"
    Copy-Item -LiteralPath $portableBuildManifest -Destination (Join-Path $ResultRoot "build-manifest.json") -Force
    return $executable
}

function Add-ResourceSample {
    param([string]$CaseId, [int]$ProcessId)
    $gpu = Get-GpuSnapshot
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    Add-JsonLine -Path $ResourceEvidence -Value ([ordered]@{
        schema_version = 1
        run_id = $RunId
        case_id = $CaseId
        process_id = $ProcessId
        monotonic_timestamp_us = [int64](Get-MonotonicUs)
        utc_timestamp = (Get-Date).ToUniversalTime().ToString("o")
        gpu = $gpu
        process_working_set_mib = if ($process) { [Math]::Round($process.WorkingSet64 / 1MB, 3) } else { $null }
        process_private_mib = if ($process) { [Math]::Round($process.PrivateMemorySize64 / 1MB, 3) } else { $null }
        handle_count = if ($process) { $process.HandleCount } else { $null }
    })
}

function Invoke-Harness {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)]$Case,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][int]$Generation
    )
    $caseEvidence = Join-Path $ResultRoot "$($Case.id).jsonl"
    $stdout = Join-Path $ResultRoot "$($Case.id).stdout.log"
    $stderr = Join-Path $ResultRoot "$($Case.id).stderr.log"
    $arguments = @(
        "--mode", $Mode,
        "--model-root", $ModelRoot,
        "--input-manifest", $InputManifestPath,
        "--output", $caseEvidence,
        "--run-id", $RunId,
        "--case-id", $Case.id,
        "--tier", $Case.tier,
        "--budget-chars", [string]$Case.budget_chars,
        "--context-seconds", [string]$Case.context_seconds,
        "--hard-timeout-seconds", [string]$Case.hard_timeout_seconds,
        "--run-generation", [string]$Generation
    )
    $argumentText = ($arguments | ForEach-Object { Get-QuotedArgument -Value ([string]$_) }) -join " "
    $baseline = Get-GpuSnapshot
    $process = Start-Process -FilePath $Executable -ArgumentList $argumentText -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden
    $deadline = (Get-Date).AddMinutes($CaseTimeoutMinutes)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        Add-ResourceSample -CaseId $Case.id -ProcessId $process.Id
        Start-Sleep -Milliseconds $SamplingIntervalMs
        $process.Refresh()
    }
    $runnerOutcome = "completed"
    if (-not $process.HasExited) {
        & taskkill.exe /PID $process.Id /T /F *> $null
        $runnerOutcome = "runner_timeout"
    }
    $process.WaitForExit()
    Add-ResourceSample -CaseId $Case.id -ProcessId $process.Id
    $cleanupDeadline = (Get-Date).AddSeconds(90)
    do {
        $computeApplications = @(Get-ComputeApplications)
        $gpuPidRemaining = @($computeApplications | Where-Object pid -eq $process.Id).Count -gt 0
        $processRemaining = $null -ne (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
        if (-not $gpuPidRemaining -and -not $processRemaining) { break }
        Start-Sleep -Milliseconds $SamplingIntervalMs
    } while ((Get-Date) -lt $cleanupDeadline)
    $after = Get-GpuSnapshot
    $normalCleanup = $runnerOutcome -eq "completed" -and $process.ExitCode -eq 0 -and
        -not $gpuPidRemaining -and -not $processRemaining
    if (Test-Path -LiteralPath $caseEvidence) {
        [IO.File]::AppendAllText($AggregateEvidence, [IO.File]::ReadAllText($caseEvidence))
    }
    Add-JsonLine -Path $AggregateEvidence -Value ([ordered]@{
        schema_version = 1; run_id = $RunId; case_id = $Case.id; event = "normal_stop_summary"
        process_id = $process.Id; process_exit_code = $process.ExitCode; runner_outcome = $runnerOutcome
        process_remaining = $processRemaining; process_gpu_allocation_remaining = $gpuPidRemaining
        vram_before_mib = $baseline.memory_used_mib; vram_after_mib = $after.memory_used_mib
        vram_delta_mib = $after.memory_used_mib - $baseline.memory_used_mib
        outcome = if ($normalCleanup) { "success" } else { "failure" }
        utc_timestamp = (Get-Date).ToUniversalTime().ToString("o")
    })
    return [pscustomobject]@{
        case_id = $Case.id
        scenario_ids = $Case.scenario_ids
        exit_code = $process.ExitCode
        runner_outcome = $runnerOutcome
        normal_cleanup = $normalCleanup
        evidence = $caseEvidence
    }
}

function Invoke-HardKillCheck {
    param([Parameter(Mandatory = $true)][string]$Executable, [Parameter(Mandatory = $true)]$Case)
    $caseEvidence = Join-Path $ResultRoot "$($Case.id).jsonl"
    $stdout = Join-Path $ResultRoot "$($Case.id).stdout.log"
    $stderr = Join-Path $ResultRoot "$($Case.id).stderr.log"
    $arguments = @(
        "--mode", "hard-kill-fixture", "--model-root", $ModelRoot,
        "--input-manifest", $InputManifestPath, "--output", $caseEvidence,
        "--run-id", $RunId, "--case-id", $Case.id, "--tier", "standard",
        "--budget-chars", "0", "--context-seconds", "20",
        "--hard-timeout-seconds", "12", "--run-generation", "900"
    )
    $argumentText = ($arguments | ForEach-Object { Get-QuotedArgument -Value ([string]$_) }) -join " "
    $baseline = Get-GpuSnapshot
    $process = Start-Process -FilePath $Executable -ArgumentList $argumentText -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden
    $ready = $false
    $deadline = (Get-Date).AddMinutes($CaseTimeoutMinutes)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        Add-ResourceSample -CaseId $Case.id -ProcessId $process.Id
        $ready = Test-JsonlEvent -Path $caseEvidence -Event "hard_kill_ready"
        if ($ready) { break }
        Start-Sleep -Milliseconds $SamplingIntervalMs
        $process.Refresh()
    }
    $hardTimeoutSeconds = 12
    if ($ready) {
        $timeoutDeadline = (Get-Date).AddSeconds($hardTimeoutSeconds)
        while (-not $process.HasExited -and (Get-Date) -lt $timeoutDeadline) {
            Add-ResourceSample -CaseId $Case.id -ProcessId $process.Id
            Start-Sleep -Milliseconds $SamplingIntervalMs
            $process.Refresh()
        }
    }
    $childrenBefore = @(Get-CimInstance Win32_Process | Where-Object ParentProcessId -eq $process.Id | Select-Object -ExpandProperty ProcessId)
    $killRequestedAt = [int64](Get-MonotonicUs)
    $killIssued = -not $process.HasExited
    if ($killIssued) {
        & taskkill.exe /PID $process.Id /T /F *> $null
    }
    $process.WaitForExit()
    $cleanupDeadline = (Get-Date).AddSeconds(90)
    $trackedPids = @($process.Id) + $childrenBefore
    do {
        Start-Sleep -Milliseconds $SamplingIntervalMs
        $remaining = @($trackedPids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        $computeApplications = @(Get-ComputeApplications)
        $gpuPidRemaining = @($computeApplications | Where-Object { $_.pid -in $trackedPids }).Count -gt 0
    } while (($remaining.Count -ne 0 -or $gpuPidRemaining) -and
             (Get-Date) -lt $cleanupDeadline)
    $after = Get-GpuSnapshot
    $cleanupCompletedAt = [int64](Get-MonotonicUs)
    $orphanCount = @($remaining).Count
    $outcome = if ($ready -and $killIssued -and $orphanCount -eq 0 -and -not $gpuPidRemaining) { "success" } else { "failure" }
    if (Test-Path -LiteralPath $caseEvidence) {
        [IO.File]::AppendAllText($AggregateEvidence, [IO.File]::ReadAllText($caseEvidence))
    }
    Add-JsonLine -Path $AggregateEvidence -Value ([ordered]@{
        schema_version = 1; run_id = $RunId; case_id = $Case.id; event = "hard_kill_summary"
        process_id = $process.Id; children_before = $childrenBefore; ready = $ready; kill_issued = $killIssued
        hard_timeout_seconds = $hardTimeoutSeconds
        kill_requested_at_us = $killRequestedAt; cleanup_completed_at_us = $cleanupCompletedAt
        orphan_process_count = $orphanCount; process_gpu_allocation_remaining = $gpuPidRemaining
        vram_before_mib = $baseline.memory_used_mib; vram_after_mib = $after.memory_used_mib
        vram_delta_mib = $after.memory_used_mib - $baseline.memory_used_mib
        outcome = $outcome; utc_timestamp = (Get-Date).ToUniversalTime().ToString("o")
    })
    return [pscustomobject]@{
        schema_version = 1; reliability_run_id = $RunId; scenario_id = "BENCH-023"
        fault_id = "P03-HARD-KILL"; run_id = $RunId; run_generation = 900; mode = "O"
        sample_group = $Case.id; app_version = $ApplicationVersion
        config_snapshot_hash = $ConfigSnapshotHash; input_asset_hash = Get-Sha256 -Path $InputManifestPath
        hardware_profile_id = $HardwareProfileId; model_id = "MiniCPM-o-4_5-gguf"
        model_version = "502eec5b03eaee9d0d2ce17a176e3490103c9a63"; quantization = "Q4_K_M"
        runtime_version = "b9d15b83ee353b2eaeee4d9318c98a35a1347486"; component = "O-C01-poc"
        event_name = "hard_timeout_kill"; monotonic_timestamp_us = $killRequestedAt
        utc_timestamp = (Get-Date).ToUniversalTime().ToString("o"); fault_type = "forced_process_termination"
        signal_source = "task23-runner-12s-hard-timeout"; error_code = ""; process_id = $process.Id
        related_processes = ($childrenBefore -join "|"); control_action = "taskkill /T /F after 12s hard timeout"
        recovery_action = "none"; attempt_index = 1; new_run_generation = ""
        expected_action = "terminate process tree and release model allocation"
        actual_action = $outcome; expected_max_residue = 0; actual_residue = $orphanCount
        old_generation_accepted_count = ""; new_work_after_block_count = 0
        remaining_processes = ($remaining.Id -join "|"); orphan_process_count = $orphanCount
        vram_after_mib = $after.memory_used_mib; ui_control_result = "not_applicable_poc"
        isolation_result = $outcome; cleanup_result = $outcome; outcome = $outcome
        evidence_ref = "evidence.jsonl#hard_kill_summary"; review_status = "pending_review"
    }
}

function New-CaseMatrix {
    $cases = @(
        [pscustomobject]@{ id = "p02-standard-context20"; tier = "standard"; budget_chars = 0; context_seconds = 20; hard_timeout_seconds = 12; scenario_ids = "O10|BENCH-001|BENCH-002|BENCH-003|BENCH-005" },
        [pscustomobject]@{ id = "p04-tier-low"; tier = "low"; budget_chars = 0; context_seconds = 20; hard_timeout_seconds = 12; scenario_ids = "BENCH-002" },
        [pscustomobject]@{ id = "p04-tier-high"; tier = "high"; budget_chars = 0; context_seconds = 20; hard_timeout_seconds = 12; scenario_ids = "BENCH-002|BENCH-003" },
        [pscustomobject]@{ id = "p04-budget225"; tier = "custom"; budget_chars = 225; context_seconds = 20; hard_timeout_seconds = 12; scenario_ids = "BENCH-004" },
        [pscustomobject]@{ id = "p04-budget350"; tier = "custom"; budget_chars = 350; context_seconds = 20; hard_timeout_seconds = 16; scenario_ids = "BENCH-004" },
        [pscustomobject]@{ id = "p04-budget500"; tier = "custom"; budget_chars = 500; context_seconds = 20; hard_timeout_seconds = 20; scenario_ids = "BENCH-004" },
        [pscustomobject]@{ id = "p04-context15"; tier = "standard"; budget_chars = 0; context_seconds = 15; hard_timeout_seconds = 12; scenario_ids = "BENCH-005" },
        [pscustomobject]@{ id = "p04-context30"; tier = "standard"; budget_chars = 0; context_seconds = 30; hard_timeout_seconds = 12; scenario_ids = "BENCH-005" }
    )
    $expanded = @()
    foreach ($case in $cases) {
        for ($repeat = 1; $repeat -le $Repetitions; $repeat++) {
            $expanded += [pscustomobject]@{
                id = if ($Repetitions -eq 1) { $case.id } else { "$($case.id)-r$repeat" }
                tier = $case.tier; budget_chars = $case.budget_chars
                context_seconds = $case.context_seconds; hard_timeout_seconds = $case.hard_timeout_seconds
                scenario_ids = $case.scenario_ids
            }
        }
    }
    return @($expanded)
}

function Write-RunConfig {
    $path = Join-Path $ResultRoot "run-config.json"
    Write-JsonFile -Path $path -Value ([ordered]@{
        schema_version = 1; run_id = $RunId; task_id = "AIJARVISV2-23"; candidate = "O-C01"
        execution_mode = if ($PortableMode) { "portable_prebuilt" } else { "source_build" }
        model_root = $ModelRoot; input_manifest = $InputManifestPath
        sampling_interval_ms = $SamplingIntervalMs; repetitions = $Repetitions
        case_timeout_minutes = $CaseTimeoutMinutes; hard_kill_timeout_seconds = 12
        model_instance_limit = 1; session_limit = 1; text_generation_stream_limit = 1
        tts_enabled = $false; reference_audio = ""; extra_model_calls_allowed = 0
        cases = @(New-CaseMatrix)
    })
    return Get-Sha256 -Path $path
}

function Finalize-Results {
    param([object[]]$CaseRuns, [object[]]$ReliabilityRows, $Preflight)
    $evidence = @()
    if (Test-Path -LiteralPath $AggregateEvidence) {
        foreach ($line in Get-Content -LiteralPath $AggregateEvidence -Encoding UTF8) {
            if ($line) { $evidence += ($line | ConvertFrom-Json) }
        }
    }
    $resourceSamples = @()
    if (Test-Path -LiteralPath $ResourceEvidence) {
        foreach ($line in Get-Content -LiteralPath $ResourceEvidence -Encoding UTF8) {
            if ($line) { $resourceSamples += ($line | ConvertFrom-Json) }
        }
    }
    $caseLookup = @{}
    foreach ($run in $CaseRuns) { $caseLookup[$run.case_id] = $run }

    $performanceRows = @()
    foreach ($event in @($evidence | Where-Object event -eq "duplex_result")) {
        $run = $caseLookup[[string]$event.case_id]
        $performanceRows += [pscustomobject]@{
            schema_version = 1; scenario_run_id = $RunId
            scenario_id = if ($run) { $run.scenario_ids } else { "O10" }
            sample_group = $event.case_id; run_id = $RunId; run_generation = $event.run_generation
            mode = "O"; app_version = $Preflight.repository_head; model_id = "MiniCPM-o-4_5-gguf"
            model_version = "502eec5b03eaee9d0d2ce17a176e3490103c9a63"
            quantization = "Q4_K_M"; runtime_version = "b9d15b83ee353b2eaeee4d9318c98a35a1347486"
            hardware_profile_id = $HardwareProfileId; driver_version = $Preflight.gpu.driver_version
            config_snapshot_hash = $ConfigSnapshotHash; input_asset_hash = $Preflight.input_manifest_sha256
            concurrency = 1; image_count = 1; tier = $event.tier; budget_chars = $event.budget_chars
            timeout_limit_s = $event.hard_timeout_seconds; route = "duplex"; event_name = "duplex_result"
            task_id = "AIJARVISV2-23"; event_id = $event.frame_id; batch_id = ""; slot_id = "O-single"
            monotonic_timestamp_us = $event.monotonic_timestamp_us; utc_timestamp = $event.utc_timestamp
            outcome = if ($event.ok) { if ($event.hard_timeout_exceeded) { "timeout" } else { "success" } } else { "failure" }
            error_code = ""; duration_us = [int64]([double]$event.ms_total * 1000)
            throughput_window_us = ""; throughput_valid_count = ""; vram_mib = ""; ram_mib = ""
            handle_count = ""; gpu_percent = ""; queue_depth = ""; queue_limit = ""
            content_age_ms = ""; evidence_ref = "evidence.jsonl#frame-$($event.frame_id)"; review_status = "pending_review"
        }
    }
    $resourceRows = foreach ($sample in $resourceSamples) {
        [pscustomobject]@{
            schema_version = 1; scenario_run_id = $RunId; scenario_id = "O10|BENCH-001"
            window_id = $sample.case_id; window_type = "task23-poc"; sample_group = $sample.case_id
            run_id = $RunId; run_generation = ""; mode = "O"; phase = "runtime"
            app_version = $Preflight.repository_head; model_id = "MiniCPM-o-4_5-gguf"
            model_version = "502eec5b03eaee9d0d2ce17a176e3490103c9a63"; quantization = "Q4_K_M"
            runtime_version = "b9d15b83ee353b2eaeee4d9318c98a35a1347486"
            hardware_profile_id = $HardwareProfileId; driver_version = $sample.gpu.driver_version
            config_snapshot_hash = $ConfigSnapshotHash; input_asset_hash = $Preflight.input_manifest_sha256
            sampling_tool = "nvidia-smi+Get-Process"; sampling_interval_ms = $SamplingIntervalMs
            monotonic_timestamp_us = $sample.monotonic_timestamp_us; utc_timestamp = $sample.utc_timestamp
            process_set = $sample.process_id; vram_mib = $sample.gpu.memory_used_mib
            ram_working_set_mib = $sample.process_working_set_mib; ram_commit_mib = $sample.process_private_mib
            handle_count = $sample.handle_count; gpu_percent = $sample.gpu.utilization_gpu_percent
            model_busy = ""; queue_depths = ""; queue_limits = ""; log_size_mib = ""; history_size_mib = ""
            eviction_count = ""; rollover_count = ""; restart_count = ""; reset_count = ""
            remaining_processes = ""; outcome = "observed"; error_code = ""
            evidence_ref = "resource-samples.jsonl"
        }
    }
    Write-TemplateCsv -Template $PerformanceTemplate -Destination (Join-Path $ResultRoot "performance-sample-record.csv") -Rows @($performanceRows)
    Write-TemplateCsv -Template $ResourceTemplate -Destination (Join-Path $ResultRoot "resource-trend-record.csv") -Rows @($resourceRows)
    Write-TemplateCsv -Template $ReliabilityTemplate -Destination (Join-Path $ResultRoot "reliability-event-record.csv") -Rows @($ReliabilityRows)

    $groups = @()
    foreach ($group in @($performanceRows | Group-Object sample_group)) {
        $success = @($group.Group | Where-Object outcome -eq "success")
        $durations = [double[]]@($success | ForEach-Object { [double]$_.duration_us / 1000.0 })
        $groups += [pscustomobject]@{
            sample_group = $group.Name; total = $group.Count; success = $success.Count
            failure = @($group.Group | Where-Object outcome -eq "failure").Count
            timeout = @($group.Group | Where-Object outcome -eq "timeout").Count
            min_ms = if ($durations.Count) { ($durations | Measure-Object -Minimum).Minimum } else { $null }
            max_ms = if ($durations.Count) { ($durations | Measure-Object -Maximum).Maximum } else { $null }
            p50_ms = Get-NearestRank -Values $durations -Percentile 0.50
            p95_ms = Get-NearestRank -Values $durations -Percentile 0.95
        }
    }
    $sessionSummaries = @($evidence | Where-Object event -eq "session_summary")
    $normalStopSummaries = @($evidence | Where-Object event -eq "normal_stop_summary")
    $rebuildSummaries = @($evidence | Where-Object event -eq "session_rebuild_completed")
    $hardKillSummary = @($evidence | Where-Object event -eq "hard_kill_summary" | Select-Object -Last 1)
    $requiredGroups = @("p02-standard-context20", "p04-tier-low", "p04-tier-high", "p04-budget225", "p04-budget350", "p04-budget500", "p04-context15", "p04-context30")
    $missingGroups = @()
    foreach ($requiredGroup in $requiredGroups) {
        $hasSessionSummary = @($sessionSummaries | Where-Object { ($_.case_id -replace '-r\d+$', '') -eq $requiredGroup }).Count -gt 0
        $hasRawResult = @($evidence | Where-Object { $_.event -eq "duplex_result" -and ($_.case_id -replace '-r\d+$', '') -eq $requiredGroup }).Count -gt 0
        $hasResourceSample = @($resourceSamples | Where-Object { ($_.case_id -replace '-r\d+$', '') -eq $requiredGroup }).Count -gt 0
        if (-not ($hasSessionSummary -and $hasRawResult -and $hasResourceSample)) { $missingGroups += $requiredGroup }
    }
    $p02Recorded = @($sessionSummaries | Where-Object { $_.case_id -like "p02-standard-context20*" }).Count -gt 0
    $p02Passed = @($sessionSummaries | Where-Object { $_.case_id -like "p02-standard-context20*" -and $_.outcome -eq "success" }).Count -gt 0
    $p04Covered = $missingGroups.Count -eq 0
    $rebuildRecorded = $rebuildSummaries.Count -gt 0
    $rebuildPassed = @($rebuildSummaries | Where-Object { $_.outcome -eq "success" -and $_.old_generation_accepted_count -eq 0 }).Count -gt 0
    $normalStopRecorded = $normalStopSummaries.Count -eq $CaseRuns.Count
    $normalStopPassed = $normalStopRecorded -and @($normalStopSummaries | Where-Object outcome -ne "success").Count -eq 0
    $hardKillRecorded = $hardKillSummary.Count -gt 0
    $hardKillPassed = $hardKillSummary.Count -gt 0 -and $hardKillSummary[0].outcome -eq "success"
    $p03Recorded = $normalStopRecorded -and $rebuildRecorded -and $hardKillRecorded
    $p03Passed = $normalStopPassed -and $rebuildPassed -and $hardKillPassed
    $evidenceComplete = $p02Recorded -and $p03Recorded -and $p04Covered
    $formalEvidenceComplete = $evidenceComplete -and [bool]$Preflight.task23_formal_minimum_met
    $candidateAssessment = if (-not $evidenceComplete) { "not_demonstrated" } `
        elseif (-not $Preflight.task23_formal_minimum_met) { "supplemental_only_pending_review" } `
        elseif ($p02Passed -and $p03Passed) { "feasible_pending_review" } `
        else { "infeasible_pending_review" }
    $summary = [ordered]@{
        schema_version = 1; run_id = $RunId; task_id = "AIJARVISV2-23"; candidate = "O-C01"
        generated_at = (Get-Date).ToUniversalTime().ToString("o"); preflight = "passed"
        p02_recorded = $p02Recorded; p02_dynamic_closed_loop = $p02Passed
        p03_recorded = $p03Recorded; p03_normal_stop_cleanup = $normalStopPassed
        p03_cancellation_api_available = $false; p03_cancellation_gap_recorded = $true
        p03_session_end_semantics = "drain"; p03_rebuild = $rebuildPassed
        p03_hard_timeout_kill_cleanup = $hardKillPassed
        p04_required_groups_recorded = $p04Covered; p04_missing_groups = $missingGroups
        evidence_complete = $evidenceComplete
        task23_formal_minimum_met = [bool]$Preflight.task23_formal_minimum_met
        task23_formal_evidence_complete = $formalEvidenceComplete
        evidence_scope = $Preflight.gpu_eligibility.evidence_scope
        candidate_assessment = $candidateAssessment
        o_risk_23_01 = if ($formalEvidenceComplete) { "candidate_for_review_and_closure" } else { "open" }
        statistics_rule = "nearest-rank Q(p)=x[ceil(p*N)]; failures and timeouts excluded from success latency percentiles"
        groups = $groups; case_runs = $CaseRuns
        evidence_files = @("evidence.jsonl", "resource-samples.jsonl", "performance-sample-record.csv", "resource-trend-record.csv", "reliability-event-record.csv")
    }
    Write-JsonFile -Value $summary -Path $SummaryPath

    $hashLines = @()
    foreach ($file in Get-ChildItem -LiteralPath $ResultRoot -File | Where-Object Name -ne "sha256sums.txt" | Sort-Object Name) {
        $hashLines += "$(Get-Sha256 -Path $file.FullName)  $($file.Name)"
    }
    $hashLines | Set-Content -LiteralPath (Join-Path $ResultRoot "sha256sums.txt") -Encoding ASCII
}

$preflight = $null
try {
    $preflight = Invoke-Preflight
} catch {
    $blocked = [ordered]@{
        schema_version = 1; run_id = $RunId; status = "blocked"; phase = "preflight"
        reason = $_.Exception.Message; dynamic_model_calls = 0; generated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    Write-JsonFile -Value $blocked -Path $PreflightPath
    Write-JsonFile -Value $blocked -Path $SummaryPath
    throw
}

$ConfigSnapshotHash = Write-RunConfig
$preflight | Add-Member -NotePropertyName config_snapshot_sha256 -NotePropertyValue $ConfigSnapshotHash -Force
Write-JsonFile -Value $preflight -Path $PreflightPath
$ApplicationVersion = if ($preflight.repository_head.Length -gt 12) {
    $preflight.repository_head.Substring(0, 12)
} else {
    $preflight.repository_head
}
$gpuNameSlug = ([string]$preflight.gpu.name).ToLowerInvariant() -replace "[^a-z0-9]+", "-"
$gpuNameSlug = $gpuNameSlug.Trim("-")
$HardwareProfileId = "windows11-nvidia-$gpuNameSlug-$($preflight.gpu.memory_total_mib)mib"
$caseRuns = @()
$reliabilityRows = @()
try {
    $executable = Resolve-Harness
    $generation = 1
    foreach ($case in New-CaseMatrix) {
        $caseRuns += Invoke-Harness -Executable $executable -Case $case -Mode "case" -Generation $generation
        ++$generation
    }

    $rebuildCase = [pscustomobject]@{
        id = "p03-session-rebuild"; tier = "standard"; budget_chars = 0
        context_seconds = 20; hard_timeout_seconds = 12; scenario_ids = "O10|BENCH-023"
    }
    $caseRuns += Invoke-Harness -Executable $executable -Case $rebuildCase -Mode "rebuild" -Generation 800
    $hardKillCase = [pscustomobject]@{ id = "p03-hard-kill" }
    $reliabilityRows = @(Invoke-HardKillCheck -Executable $executable -Case $hardKillCase)
    Finalize-Results -CaseRuns $caseRuns -ReliabilityRows $reliabilityRows -Preflight $preflight
} catch {
    Add-JsonLine -Path $AggregateEvidence -Value ([ordered]@{
        schema_version = 1; run_id = $RunId; case_id = "runner"; event = "execution_failure"
        reason = $_.Exception.Message; generated_at = (Get-Date).ToUniversalTime().ToString("o")
    })
    Finalize-Results -CaseRuns $caseRuns -ReliabilityRows $reliabilityRows -Preflight $preflight
    throw
}

Write-Host "AIJARVISV2-23 field evidence: $ResultRoot"
