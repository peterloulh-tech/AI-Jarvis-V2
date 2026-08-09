# O Reference Harness v2

## Purpose

This directory is the external reference standard for the Locked MiniCPM-o / `llama.cpp-omni` behavior used by AI Jarvis V2. It is intentionally independent from the V2 Product Adapter, Worker, IPC, Overlay, privacy policy, and generation/slot state machine. Task 23 remains a Legacy Diagnostic PoC; this Harness consumes its evidence and proven infrastructure without treating its model semantics as authoritative.

## Locked Baseline

- Model: `openbmb/MiniCPM-o-4_5-gguf@502eec5b03eaee9d0d2ce17a176e3490103c9a63`, Q4_K_M LLM + F16 vision + F16 audio.
- Runtime: `tc-mb/llama.cpp-omni@b9d15b83ee353b2eaeee4d9318c98a35a1347486` plus patch SHA-256 `cc8b1c4a...`.
- TTS and reference audio are disabled. The Harness does not change the Locked default startup LISTEN count.
- Sources of truth: [`OFFICIAL_BASELINE_INDEX.md`](../../docs/v2/memory/OFFICIAL_BASELINE_INDEX.md) and [`O_RUNTIME_FOUR_WAY_DELTA.md`](../../docs/v2/memory/O_RUNTIME_FOUR_WAY_DELTA.md). Their full contents are not duplicated here.

## Architecture

`manifest/profile → thin Locked C API RAII shim → begin/push/wait/end → raw result log → streaming aggregation → optional V2 contract validator → summary`

The shim only converts parameters and paths, owns resources, maps `user_seq` back to input timing, and exposes raw C results. `main.cpp` schedules manifest offsets and records observable boundaries. `aggregation.cpp` retains every fragment and separates runtime boundaries from payload completion. None of these files import or implement `IOmniRuntime` or product policy.

## Profiles

- `official-runtime-reference`: uses the Locked no-ref/no-TTS plain-system branch and Locked default duplex wording. It verifies load/input, native startup LISTEN, later autonomous LISTEN/SPEAK, fragments, order, timing, input exhaustion, timeout, drain and cleanup. Plain text is valid; three-batch JSON is not a runtime success condition.
- `v2-contract`: runs on the same Harness/runtime with the V2 JSON prompt and a separate thin validator. It requires root `batches`, exactly three ordered batches, matching `style_id`, and non-empty `items` arrays.

## Runtime vs payload completion

The Locked C result has no reliable official EOS/finished field. `runtime_boundary_reason` therefore records only observations: `listen_transition`, `generation_change`, `session_end_drain`, `input_exhausted`, `failure`, or `timeout`; every boundary explicitly records `official_eos: false`. `payload_complete` means aggregated JSON parsed, and `schema_valid` means the V2 validator passed. Payload completion never manufactures runtime EOS. A boundary with unfinished JSON remains `payload_incomplete`.

## Reuse map

| Class | Files/assets | Decision |
|---|---|---|
| REUSE-BUILD | `.github/workflows/aijarvisv2-92-reference-harness.yml`, Task23 CUDA 12.8.1 setup, pinned checkout/patch, MSVC preflight, CMake install, portable manifest/license/artifact route | Same successful chain; only source directory, target and package contents change. Workflow is manual dispatch only. |
| REUSE-INFRA | `gpu-capacity.ps1`, locked model hashes, provenance pattern, result isolation, GPU snapshots, hard process timeout/kill, SHA-256 result list | Reused directly or minimally adapted. |
| REVIEW | `src/locked_runtime.cpp`, `src/main.cpp`, `src/aggregation.cpp` | Re-decided from Locked cadence/session/fragment/drain/result semantics. |
| DROP/LEGACY | Task23 `poc_main.cpp` product-like adapter shape, per-fragment final JSON validation, 3-second-only assumptions and exploratory modes | Preserved in Task23 but not inherited. |
| Original author | fixed file conversion is handled by the Locked runtime; Task17-approved downmix/window and capture remain available for future Product Adapter work | No live screen/microphone chain is pulled into this deterministic Harness. |

## Fixtures and tests

- `official-1hz`: the existing O-IN-07 33 × 1000 ms fixture is consumed directly; files, continuous offsets, 16 kHz mono 16-bit PCM, audio recomposition, vision mapping, markers and SHA-256 are checked.
- `legacy-3s-replay`: 11 × 3000 ms assets are mechanically reconstructed from the same 1 Hz content and match the 2026-08-09 source snapshot hashes.
- `fixtures/results/legacy-four-fragments.jsonl` preserves the four real SPEAK fragments. They remain ordered raw fragments and aggregate to `payload_incomplete`, never `invalid_final_payload`.
- `fixtures/results/complete-three-batch-fragments.jsonl` proves aggregate → JSON parse → schema → three-batch PASS.
- C++ tests cover generation change, LISTEN, timeout/incomplete, failed result separation, order rejection, summary counters and profile separation.

Run the complete zero-GPU suite:

```bash
node tools/o-reference-harness-v2/tests/run-offline-tests.js
```

`dry-run` writes `run-metadata.json`, ordered `inputs.jsonl`, and `summary.json` without loading a model. Output directories must be new/empty.

## Results

Dynamic runs write run metadata (model/revisions/commit/profile/prompt/platform), ordered input records, `raw-results.jsonl`, `aggregations.json`, `runtime-boundaries.jsonl`, `summary.json`, runner logs/environment telemetry and `sha256sums.txt`. Summary counters include model/input, LISTEN/SPEAK, fragments, aggregates, complete/incomplete payloads, valid three-batch payloads and runtime failures.

## Build

`BUILD_REQUIRED`: Task23's binary cannot represent the corrected aggregation/completion semantics, so the new target is `o-reference-harness-v2`. The CMake/runtime/CUDA/package route is the proven Task23 route with no model embedded. This task prepares but does not execute the Windows/CUDA build.

The GitHub workflow is `workflow_dispatch` only. It builds Windows x64 with CUDA architectures `86;89;120`, packages the external-model runner and deterministic fixtures, then runs all four profile/cadence dry-run combinations without loading a model.

## Windows dynamic test

After Task 92 review, Task 93 may dispatch the workflow, download the Artifact, place the three locked GGUF files under `MODEL_ROOT`, then run:

```powershell
./run-o-reference-harness-v2.ps1 -Profile official-runtime-reference -Cadence official-1hz -ModelRoot D:\models\MiniCPM-o-4_5-gguf
./run-o-reference-harness-v2.ps1 -Profile v2-contract -Cadence official-1hz -ModelRoot D:\models\MiniCPM-o-4_5-gguf
./run-o-reference-harness-v2.ps1 -Profile official-runtime-reference -Cadence legacy-3s-replay -ModelRoot D:\models\MiniCPM-o-4_5-gguf
```

Windows/NVIDIA model load, CUDA execution, native LISTEN/SPEAK distribution, latency, VRAM and cleanup remain `DYNAMIC-ONLY` until Task 93 produces real evidence.
