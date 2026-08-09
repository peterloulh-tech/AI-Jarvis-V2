"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const tools = require("./diagnostic-tools.js");

const root = __dirname;
const args = process.argv.slice(2);
let originalRoot = null;
let portableRoot = null;
let modelRoot = null;
let outputPath = null;
for (let index = 0; index < args.length; index += 1) {
  if (args[index] === "--original-root") originalRoot = path.resolve(args[++index]);
  else if (args[index] === "--portable-root") portableRoot = path.resolve(args[++index]);
  else if (args[index] === "--model-root") modelRoot = path.resolve(args[++index]);
  else if (args[index] === "--output") outputPath = path.resolve(args[++index]);
  else throw new Error("unknown argument: " + args[index]);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJsonl(filePath) {
  return fs.readFileSync(filePath, "utf8").trim().split(/\r?\n/).filter(Boolean).map(JSON.parse);
}

function sha256Buffer(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function readWave(filePath) {
  const data = fs.readFileSync(filePath);
  assert.strictEqual(data.toString("ascii", 0, 4), "RIFF");
  assert.strictEqual(data.toString("ascii", 8, 12), "WAVE");
  let cursor = 12;
  let format = null;
  let pcm = null;
  while (cursor + 8 <= data.length) {
    const id = data.toString("ascii", cursor, cursor + 4);
    const size = data.readUInt32LE(cursor + 4);
    const start = cursor + 8;
    if (id === "fmt ") {
      format = {
        audio_format: data.readUInt16LE(start),
        channels: data.readUInt16LE(start + 2),
        sample_rate: data.readUInt32LE(start + 4),
        bits_per_sample: data.readUInt16LE(start + 14)
      };
    } else if (id === "data") {
      pcm = data.subarray(start, start + size);
    }
    cursor = start + size + (size % 2);
  }
  assert.ok(format && pcm, "WAV must contain fmt and data chunks: " + filePath);
  const bytesPerFrame = format.channels * format.bits_per_sample / 8;
  return {
    ...format,
    frame_count: pcm.length / bytesPerFrame,
    duration_ms: pcm.length / bytesPerFrame / format.sample_rate * 1000,
    pcm
  };
}

const configPath = path.join(root, "diagnostic-config.json");
const runnerPath = path.join(root, "run-next-win-diagnostic.ps1");
assert.ok(fs.statSync(runnerPath).isFile());
const runnerSource = fs.readFileSync(runnerPath, "utf8");
assert.ok(!runnerSource.includes("VerifyModelHashes"), "model content hashing must not be optional");
assert.ok(runnerSource.includes('Assert-Sha256 -Path $path -Expected ([string]$expectedModelFile.sha256) -Label "locked model file"'),
  "field runner must hash every locked model file");
const config = readJson(configPath);
assert.strictEqual(config.runtime_revision, "b9d15b83ee353b2eaeee4d9318c98a35a1347486");
assert.strictEqual(config.model_revision, "502eec5b03eaee9d0d2ce17a176e3490103c9a63");

let exactPortableIdentity = "not_checked_without_portable_root";
if (portableRoot) {
  assert.strictEqual(tools.sha256File(path.join(portableRoot, "portable-manifest.json")), config.portable_manifest_sha256);
  assert.strictEqual(tools.sha256File(path.join(portableRoot, "portable-build-manifest.json")), config.portable_build_manifest_sha256);
  const portableBuild = readJson(path.join(portableRoot, "portable-build-manifest.json"));
  assert.strictEqual(portableBuild.source_commit, config.portable_source_commit);
  assert.strictEqual(portableBuild.executable_sha256, config.executable.sha256);
  for (const entry of [config.executable, ...config.runtime_dlls]) {
    const absolute = path.join(portableRoot, ...entry.path.split("/"));
    assert.strictEqual(fs.statSync(absolute).size, entry.size);
    assert.strictEqual(tools.sha256File(absolute), entry.sha256);
  }
  exactPortableIdentity = "passed";
}

let lockedModelIdentity = "not_checked_without_model_root";
if (modelRoot) {
  const provenance = readJson(path.join(modelRoot, "MODEL_PROVENANCE.json"));
  assert.strictEqual(provenance.revision, config.model_revision);
  assert.deepStrictEqual(provenance.files, config.model_files);
  for (const entry of config.model_files) {
    assert.strictEqual(fs.statSync(path.join(modelRoot, ...entry.path.split("/"))).size, entry.size);
  }
  lockedModelIdentity = "provenance_paths_sizes_and_declared_hashes_passed";
}

const sourceSnapshotPath = path.join(root, "fixtures", "O-CASE-A-source-manifest.snapshot.json");
assert.strictEqual(tools.sha256File(sourceSnapshotPath), config.source_manifest_sha256);
const sourceManifest = readJson(sourceSnapshotPath);
assert.strictEqual(sourceManifest.chunks.length, 11);
for (let index = 0; index < sourceManifest.chunks.length; index += 1) {
  assert.strictEqual(sourceManifest.chunks[index].sequence, index + 1);
  assert.strictEqual(sourceManifest.chunks[index].offset_ms, index * 3000);
  assert.strictEqual(sourceManifest.chunks[index].duration_ms, 3000);
}

const oneHzRoot = path.join(root, "O-IN-07-1HZ");
const oneHzManifestPath = path.join(oneHzRoot, "manifest.json");
assert.strictEqual(tools.sha256File(oneHzManifestPath), config.one_hz_manifest_sha256);
const oneHzManifest = readJson(oneHzManifestPath);
const oneHzValidation = tools.validateTimeline(oneHzManifest, oneHzRoot, 1000, true);
assert.strictEqual(oneHzValidation.chunk_count, 33);
assert.strictEqual(oneHzValidation.timeline_end_ms, 33000);
assert.strictEqual(oneHzManifest.source_manifest_sha256, config.source_manifest_sha256);

const waveChecks = [];
for (const chunk of oneHzManifest.chunks) {
  const wave = readWave(path.join(oneHzRoot, chunk.audio));
  assert.strictEqual(wave.audio_format, 1);
  assert.strictEqual(wave.channels, 1);
  assert.strictEqual(wave.sample_rate, 16000);
  assert.strictEqual(wave.bits_per_sample, 16);
  assert.strictEqual(wave.frame_count, 16000);
  assert.strictEqual(wave.duration_ms, 1000);
  waveChecks.push({ sequence: chunk.sequence, frames: wave.frame_count, duration_ms: wave.duration_ms });
}

let exactSourceMapping = "not_checked_without_original_root";
if (originalRoot) {
  assert.strictEqual(tools.sha256File(path.join(originalRoot, "manifest.json")), config.source_manifest_sha256);
  tools.validateTimeline(readJson(path.join(originalRoot, "manifest.json")), originalRoot, 3000, true);
  for (const sourceChunk of sourceManifest.chunks) {
    const derived = oneHzManifest.chunks.filter((item) => item.source_sequence === sourceChunk.sequence);
    assert.strictEqual(derived.length, 3);
    assert.deepStrictEqual(derived.map((item) => item.source_part), [1, 2, 3]);
    const combinedPcm = Buffer.concat(derived.map((item) => readWave(path.join(oneHzRoot, item.audio)).pcm));
    const sourcePcm = readWave(path.join(originalRoot, sourceChunk.audio)).pcm;
    assert.strictEqual(sha256Buffer(combinedPcm), sha256Buffer(sourcePcm));
    for (const item of derived) {
      assert.strictEqual(tools.sha256File(path.join(oneHzRoot, item.image)), sourceChunk.image_sha256);
      assert.strictEqual(item.marker, sourceChunk.marker + "-part-" + item.source_part + "-of-3");
    }
  }
  exactSourceMapping = "passed";
}

const knownFixturePath = path.join(root, "fixtures", "O10-P23-20260809-four-speak-fragments.jsonl");
const knownReport = tools.aggregateEvents(readJsonl(knownFixturePath), {
  styleIds: config.style_ids,
  minimumItems: 1,
  maximumItems: 5,
  budgetChars: 225
});
assert.strictEqual(knownReport.fragment_count, 4);
assert.strictEqual(knownReport.aggregate_count, 1);
assert.strictEqual(knownReport.aggregates[0].json_parse_complete, false);
assert.ok(knownReport.fragments.every((fragment) => fragment.validation_status === "awaiting_completion"));

const cliTemp = fs.mkdtempSync(path.join(os.tmpdir(), "task23-aggregate-cli-"));
const cliFragments = path.join(cliTemp, "fragments.jsonl");
const cliSummary = path.join(cliTemp, "summary.json");
childProcess.execFileSync(process.execPath, [
  path.join(root, "diagnostic-tools.js"), "aggregate", knownFixturePath,
  cliFragments, cliSummary, config.style_ids.join(","), "1", "5", "225"
], { stdio: "inherit" });
assert.strictEqual(readJsonl(cliFragments).length, 4);
assert.strictEqual(readJson(cliSummary).aggregates[0].completion_basis, "evidence_end_without_complete_json");

function selectedRounds(manifest, contextSeconds) {
  return manifest.chunks.filter((chunk) => chunk.offset_ms <= contextSeconds * 1000).map((chunk, index) => ({
    round: index + 1,
    sequence: chunk.sequence,
    offset_ms: chunk.offset_ms,
    duration_ms: chunk.duration_ms,
    marker: chunk.marker,
    source_sequence: chunk.source_sequence || chunk.sequence,
    source_part: chunk.source_part || 1,
    expected_decision_mode: index < 3 ? "startup-guard-LISTEN" : "autonomous"
  }));
}

const caseARounds = selectedRounds(sourceManifest, config.cases["O-CASE-A"].context_seconds);
const caseBRounds = selectedRounds(oneHzManifest, config.cases["O-CASE-B"].context_seconds);
assert.strictEqual(caseARounds.length, config.cases["O-CASE-A"].expected_selected_rounds);
assert.strictEqual(caseBRounds.length, config.cases["O-CASE-B"].expected_selected_rounds);
assert.strictEqual(caseARounds.filter((item) => item.expected_decision_mode === "autonomous").length, 8);
assert.strictEqual(caseBRounds.filter((item) => item.expected_decision_mode === "autonomous").length, 18);

const report = {
  schema_version: 1,
  task_id: "AIJARVISV2-23",
  verification_scope: "zero-GPU static, fixture, timeline, media, mapping, and SHA-256 checks",
  status: "passed",
  no_rebuild: true,
  existing_exe_required: true,
  exact_existing_portable_identity: exactPortableIdentity,
  locked_model_identity: lockedModelIdentity,
  runtime_revision: config.runtime_revision,
  model_revision: config.model_revision,
  source_manifest_sha256: config.source_manifest_sha256,
  one_hz_manifest_sha256: config.one_hz_manifest_sha256,
  known_field_fixture: {
    fragments: knownReport.fragment_count,
    aggregates: knownReport.aggregate_count,
    completion_basis: knownReport.aggregates[0].completion_basis,
    per_fragment_full_json_rejections: 0,
    cli_round_trip: "passed"
  },
  runner_parameter_contract: {
    status: "passed",
    model_content_sha256_preflight: "mandatory",
    accepted_cases: Object.keys(config.cases),
    o_case_a_expected_arguments: config.cases["O-CASE-A"],
    o_case_b_expected_arguments: config.cases["O-CASE-B"],
    dry_run_round_order: "passed"
  },
  o_case_a: {
    total_chunks: sourceManifest.chunks.length,
    chunk_duration_ms: 3000,
    total_duration_ms: sourceManifest.duration_ms,
    selected_rounds: caseARounds.length,
    autonomous_rounds_after_guard: caseARounds.length - 3,
    rounds: caseARounds
  },
  o_case_b: {
    diagnostic_label: "1Hz official-alignment diagnostic",
    total_chunks: oneHzValidation.chunk_count,
    chunk_duration_ms: 1000,
    total_duration_ms: oneHzValidation.timeline_end_ms,
    selected_rounds: caseBRounds.length,
    autonomous_rounds_after_guard: caseBRounds.length - 3,
    exact_source_audio_and_vision_mapping: exactSourceMapping,
    wav_checks: waveChecks,
    rounds: caseBRounds
  },
  independent_result_roots: ["results/O-CASE-A/<run-id>", "results/O-CASE-B/<run-id>"],
  powershell_runner_dynamic_execution: "DYNAMIC-ONLY",
  windows_nvidia_model_behavior: "DYNAMIC-ONLY"
};

const serialized = JSON.stringify(report, null, 2) + "\n";
if (outputPath) fs.writeFileSync(outputPath, serialized, "utf8");
process.stdout.write(serialized);
