"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const repositoryRoot = path.resolve(__dirname, "../../..");
const toolRoot = path.join(repositoryRoot, "tools/o-reference-harness-v2");
const buildRoot = fs.mkdtempSync(path.join(os.tmpdir(), "o-reference-offline-"));
const compiler = process.env.CXX || "c++";
const includeArgs = [
  `-I${path.join(toolRoot, "include")}`,
  `-I${path.join(repositoryRoot, "third_party/runtime/vendor/vendor")}`
];
const coreSources = ["aggregation.cpp", "manifest.cpp", "profile.cpp"].map((file) =>
  path.join(toolRoot, "src", file)
);

function run(command, args, options = {}) {
  const result = childProcess.spawnSync(command, args, {
    cwd: repositoryRoot,
    encoding: "utf8",
    ...options
  });
  if (result.status !== 0) {
    process.stderr.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    throw new Error(`${command} failed with status ${result.status}`);
  }
  return result;
}

const commonCompile = ["-std=c++20", "-Wall", "-Wextra", "-Werror", ...includeArgs];
const coreTests = path.join(buildRoot, "core-tests");
run(compiler, [
  ...commonCompile,
  path.join(toolRoot, "tests/core_tests.cpp"),
  ...coreSources,
  "-o", coreTests
]);
run(coreTests, [repositoryRoot], { stdio: "inherit" });

const cli = path.join(buildRoot, "o-reference-harness-v2");
run(compiler, [
  ...commonCompile,
  path.join(toolRoot, "src/main.cpp"),
  ...coreSources,
  "-o", cli
]);
run(process.execPath, [path.join(toolRoot, "tests/cli.test.js"), cli], { stdio: "inherit" });
run(process.execPath, [path.join(toolRoot, "tests/offline-fixtures.test.js")], { stdio: "inherit" });
run(process.execPath, [path.join(toolRoot, "tests/runner-config.test.js")], { stdio: "inherit" });

run(compiler, [
  "-std=c++20", "-Wall", "-Wextra", "-Werror",
  `-I${path.join(toolRoot, "include")}`,
  path.join(toolRoot, "tests/locked_runtime_contract.cpp"),
  "-fsyntax-only"
]);

const pendingInputsTest = path.join(buildRoot, "pending-inputs-test");
run(compiler, [
  "-std=c++20", "-Wall", "-Wextra", "-Werror", "-pthread",
  `-I${path.join(toolRoot, "src")}`,
  path.join(toolRoot, "tests/pending_inputs_test.cpp"),
  "-o", pendingInputsTest
]);
run(pendingInputsTest, [], { stdio: "inherit" });

const runtimeIncludes = [
  "common", "tools/omni", "vendor", "include", "ggml/include", "src"
].map((relative) => `-I${path.join(repositoryRoot, "third_party/runtime/vendor", relative)}`);
run(compiler, [
  "-std=c++20", "-Wall", "-Wextra", "-Werror",
  "-DO_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME",
  `-I${path.join(toolRoot, "include")}`,
  `-I${path.join(toolRoot, "src")}`,
  ...runtimeIncludes,
  "-fsyntax-only",
  path.join(toolRoot, "src/main.cpp"),
  path.join(toolRoot, "src/locked_runtime.cpp")
]);

const manifests = {
  "official-1hz": path.join(
    repositoryRoot,
    "tools/aijarvisv2-23/AIJARVISV2-23-NEXT-WIN-DELTA/O-IN-07-1HZ/manifest.json"
  ),
  "legacy-3s-replay": path.join(toolRoot, "fixtures/manifests/legacy-3s-replay.json")
};
const profiles = ["official-runtime-reference", "v2-contract"];
const matrix = [];
for (const profile of profiles) {
  for (const [cadence, manifest] of Object.entries(manifests)) {
    const output = path.join(buildRoot, "dry-run", profile, cadence);
    run(cli, [
      "dry-run",
      "--profile", path.join(toolRoot, "profiles", `${profile}.json`),
      "--manifest", manifest,
      "--output-dir", output,
      "--harness-commit", "OFFLINE-SELF-CHECK"
    ]);
    const summary = JSON.parse(fs.readFileSync(path.join(output, "summary.json"), "utf8"));
    matrix.push({ profile, cadence, planned_inputs: summary.planned_input_count });
  }
}

process.stdout.write(`${JSON.stringify({
  status: "passed",
  scope: "fixture/unit/manifest/hash/dry-run/static locked C API syntax",
  core_tests: 6,
  cli_tests: 4,
  fixture_tests: 3,
  runner_config_tests: 1,
  concurrent_correlation_tests: 1,
  dry_run_matrix: matrix,
  windows_nvidia_runtime: "DYNAMIC-ONLY",
  actions_started: false,
  cuda_long_build_started: false
}, null, 2)}\n`);
