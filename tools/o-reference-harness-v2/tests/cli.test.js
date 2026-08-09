"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

if (process.argv.length !== 3) throw new Error("usage: cli.test.js HARNESS_BINARY");
const binary = path.resolve(process.argv[2]);
const repositoryRoot = path.resolve(__dirname, "../../..");
const toolRoot = path.join(repositoryRoot, "tools/o-reference-harness-v2");
const oneHzManifest = path.join(
  repositoryRoot,
  "tools/aijarvisv2-23/AIJARVISV2-23-NEXT-WIN-DELTA/O-IN-07-1HZ/manifest.json"
);

function run(args, expectedStatus = 0) {
  const result = childProcess.spawnSync(binary, args, { encoding: "utf8" });
  assert.strictEqual(result.status, expectedStatus, `${result.stdout}\n${result.stderr}`);
  return result;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function readJsonl(filePath) {
  return fs.readFileSync(filePath, "utf8").trim().split(/\r?\n/).filter(Boolean).map(JSON.parse);
}

function tempResult(name) {
  return path.join(fs.mkdtempSync(path.join(os.tmpdir(), "o-reference-cli-")), name);
}

function testDryRunEmitsManifestOrderWithoutModel() {
  const output = tempResult("official-dry-run");
  run([
    "dry-run",
    "--profile", path.join(toolRoot, "profiles/official-runtime-reference.json"),
    "--manifest", oneHzManifest,
    "--output-dir", output,
    "--harness-commit", "TEST-COMMIT"
  ]);
  const metadata = readJson(path.join(output, "run-metadata.json"));
  const inputs = readJsonl(path.join(output, "inputs.jsonl"));
  const summary = readJson(path.join(output, "summary.json"));
  assert.strictEqual(metadata.profile, "official-runtime-reference");
  assert.strictEqual(metadata.model_revision, "502eec5b03eaee9d0d2ce17a176e3490103c9a63");
  assert.deepStrictEqual(metadata.model_files.map((item) => item.sha256), [
    "1237a97ee081b8abebc47aa7dad565701e8f5f904cdc92f6723ac4281bbc0932",
    "1453678cc4e4fe18de241952962e234f265cb8dda780773526103ab8ba82f421",
    "d5b188ac7feaf98e17175c3f9bd14bf269301bfd187439fdaa3e3a494fc32ef7"
  ]);
  assert.strictEqual(metadata.runtime_revision, "b9d15b83ee353b2eaeee4d9318c98a35a1347486");
  assert.strictEqual(metadata.harness_commit, "TEST-COMMIT");
  assert.strictEqual(metadata.execution_mode, "dry-run");
  assert.strictEqual(inputs.length, 33);
  assert.deepStrictEqual(inputs[0], {
    index: 1,
    offset_ms: 0,
    duration_ms: 1000,
    marker: "before-generation-01-part-1-of-3",
    source_asset: {
      audio: path.resolve(path.dirname(oneHzManifest), "chunks/0001.wav"),
      image: path.resolve(path.dirname(oneHzManifest), "chunks/0001.jpg")
    },
    audio: path.resolve(path.dirname(oneHzManifest), "chunks/0001.wav"),
    image: path.resolve(path.dirname(oneHzManifest), "chunks/0001.jpg")
  });
  assert.strictEqual(inputs[32].offset_ms, 32000);
  assert.strictEqual(summary.model_loaded, false);
  assert.strictEqual(summary.input_processed, 0);
  assert.strictEqual(summary.planned_input_count, 33);
  assert.strictEqual(summary.dynamic_runtime_status, "DYNAMIC-ONLY");
}

function testLegacyReplayPreservesIncompletePayload() {
  const output = tempResult("legacy-replay");
  run([
    "replay-results",
    "--profile", path.join(toolRoot, "profiles/v2-contract.json"),
    "--input", path.join(toolRoot, "fixtures/results/legacy-four-fragments.jsonl"),
    "--boundary", "input_exhausted",
    "--output-dir", output,
    "--harness-commit", "TEST-COMMIT"
  ]);
  const raw = readJsonl(path.join(output, "raw-results.jsonl"));
  const aggregates = readJson(path.join(output, "aggregations.json"));
  const boundaries = readJsonl(path.join(output, "runtime-boundaries.jsonl"));
  const summary = readJson(path.join(output, "summary.json"));
  assert.strictEqual(raw.length, 4);
  assert.deepStrictEqual(raw.map((item) => item.fragment), [
    '{"batches": [{"style_id":"style-',
    '1", "items": ["01 开',
    '始。"]}, {"style_id":"style-',
    '2", "items": ["0'
  ]);
  assert.strictEqual(aggregates[0].payload_parse_state, "payload_incomplete");
  assert.strictEqual(aggregates[0].payload_schema_state, "not_evaluated");
  assert.strictEqual(aggregates[0].runtime_boundary_reason, "input_exhausted");
  assert.ok(!JSON.stringify(aggregates).includes("invalid_final_payload"));
  assert.strictEqual(summary.fragment_count, 4);
  assert.strictEqual(summary.incomplete_payload_count, 1);
  assert.deepStrictEqual(boundaries.map((item) => item.reason), ["input_exhausted"]);
  assert.ok(boundaries.every((item) => item.official_eos === false));
}

function testCompleteReplayPassesThreeBatchValidatorWithoutEos() {
  const output = tempResult("complete-replay");
  run([
    "replay-results",
    "--profile", path.join(toolRoot, "profiles/v2-contract.json"),
    "--input", path.join(toolRoot, "fixtures/results/complete-three-batch-fragments.jsonl"),
    "--boundary", "input_exhausted",
    "--output-dir", output,
    "--harness-commit", "TEST-COMMIT"
  ]);
  const aggregates = readJson(path.join(output, "aggregations.json"));
  const summary = readJson(path.join(output, "summary.json"));
  assert.strictEqual(aggregates[0].payload_parse_state, "payload_complete");
  assert.strictEqual(aggregates[0].payload_schema_state, "schema_valid");
  assert.strictEqual(aggregates[0].runtime_boundary_reason, null);
  assert.strictEqual(summary.complete_payload_count, 1);
  assert.strictEqual(summary.valid_three_batch_count, 1);
}

function testResultDirectoryIsolationRejectsOverwrite() {
  const output = tempResult("isolated");
  fs.mkdirSync(output);
  fs.writeFileSync(path.join(output, "existing.txt"), "keep\n");
  run([
    "dry-run",
    "--profile", path.join(toolRoot, "profiles/official-runtime-reference.json"),
    "--manifest", oneHzManifest,
    "--output-dir", output,
    "--harness-commit", "TEST-COMMIT"
  ], 2);
  assert.strictEqual(fs.readFileSync(path.join(output, "existing.txt"), "utf8"), "keep\n");
}

const tests = [
  testDryRunEmitsManifestOrderWithoutModel,
  testLegacyReplayPreservesIncompletePayload,
  testCompleteReplayPassesThreeBatchValidatorWithoutEos,
  testResultDirectoryIsolationRejectsOverwrite
];
for (const test of tests) {
  test();
  process.stdout.write(`PASS ${test.name}\n`);
}
