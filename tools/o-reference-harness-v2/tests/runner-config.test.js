"use strict";

const assert = require("assert");
const path = require("path");

const fixtureTools = require("../scripts/fixture-tools.js");

const repositoryRoot = path.resolve(__dirname, "../../..");
const configPath = path.join(repositoryRoot, "tools/o-reference-harness-v2/runner-config.json");
const report = fixtureTools.validateRunnerConfig(configPath, repositoryRoot);

assert.deepStrictEqual(report.profiles, ["official-runtime-reference", "v2-contract"]);
assert.deepStrictEqual(report.cadences, ["official-1hz", "legacy-3s-replay"]);
assert.strictEqual(report.profile_contracts_separated, true);
assert.strictEqual(report.cadence_from_manifest, true);
assert.strictEqual(report.locked_model_hashes, 3);
assert.strictEqual(report.locked_runtime_revision, "b9d15b83ee353b2eaeee4d9318c98a35a1347486");
assert.strictEqual(report.result_root_isolated_by_profile_and_cadence, true);
assert.strictEqual(report.windows_nvidia_execution, "DYNAMIC-ONLY");

process.stdout.write("PASS runner config contract\n");
