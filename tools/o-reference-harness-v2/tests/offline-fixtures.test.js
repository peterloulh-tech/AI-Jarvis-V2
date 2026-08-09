"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

const fixtureTools = require("../scripts/fixture-tools.js");

const repositoryRoot = path.resolve(__dirname, "../../..");
const oneHzRoot = path.join(
  repositoryRoot,
  "tools/aijarvisv2-23/AIJARVISV2-23-NEXT-WIN-DELTA/O-IN-07-1HZ"
);
const sourceSnapshot = path.join(
  repositoryRoot,
  "tools/aijarvisv2-23/AIJARVISV2-23-NEXT-WIN-DELTA/fixtures/O-CASE-A-source-manifest.snapshot.json"
);
const manifestPath = path.join(
  repositoryRoot,
  "tools/o-reference-harness-v2/fixtures/manifests/legacy-3s-replay.json"
);

function testOfficialOneHzIntegrity() {
  const report = fixtureTools.validateOneHzFixture(oneHzRoot);
  assert.strictEqual(report.chunk_count, 33);
  assert.strictEqual(report.cadence_ms, 1000);
  assert.strictEqual(report.duration_ms, 33000);
  assert.strictEqual(report.pcm_format, "16000Hz-mono-16bit-PCM");
  assert.strictEqual(report.hashes_verified, 68);
  assert.strictEqual(report.markers_preserved, true);
  assert.strictEqual(report.vision_mapping_explicit, true);
}

function testLegacyFixtureRebuildMatchesRealMachineSnapshot() {
  const destination = fs.mkdtempSync(path.join(os.tmpdir(), "o-reference-legacy-"));
  const report = fixtureTools.materializeLegacyFixture({
    oneHzRoot,
    sourceSnapshot,
    manifestPath,
    destination
  });
  assert.strictEqual(report.chunk_count, 11);
  assert.strictEqual(report.cadence_ms, 3000);
  assert.strictEqual(report.duration_ms, 33000);
  assert.strictEqual(report.audio_recomposition_matches, true);
  assert.strictEqual(report.vision_mapping_matches, true);
  assert.strictEqual(report.marker_mapping_matches, true);
  assert.strictEqual(report.snapshot_hashes_match, true);
  assert.deepStrictEqual(report.input_order, Array.from({ length: 11 }, (_, index) => index + 1));
}

function testCheckedInLegacyAssetsMatchManifest() {
  const report = fixtureTools.validateLegacyFixture(manifestPath);
  assert.strictEqual(report.chunk_count, 11);
  assert.strictEqual(report.hashes_verified, 22);
  assert.strictEqual(report.pcm_format, "16000Hz-mono-16bit-PCM");
  assert.strictEqual(report.duration_ms, 33000);
}

const tests = [
  testOfficialOneHzIntegrity,
  testLegacyFixtureRebuildMatchesRealMachineSnapshot,
  testCheckedInLegacyAssetsMatchManifest
];
for (const test of tests) {
  test();
  process.stdout.write(`PASS ${test.name}\n`);
}
