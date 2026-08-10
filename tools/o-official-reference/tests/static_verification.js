"use strict";

const fs = require("fs");
const path = require("path");

const toolRoot = path.resolve(__dirname, "..");
const repositoryRoot = path.resolve(toolRoot, "..", "..");

function read(relativePath) {
  return fs.readFileSync(path.join(repositoryRoot, relativePath), "utf8");
}

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

const runner = read("tools/o-official-reference/run-o-official-reference.ps1");
for (const required of [
  "llama-server.exe",
  "health",
  "init",
  "step",
  "break",
  "full_reinit",
  "nvidia-smi",
  "raw-sse",
  "final-text.txt",
  "final-parsed.json",
  "first_fragment_latency_ms",
  "completion_latency_ms",
  "contract_prompt_template",
  "--prompt-file",
  "--n-gpu-layers",
  "--repeat-penalty",
]) {
  requireCondition(runner.includes(required), `runner missing ${required}`);
}
requireCondition(!runner.includes("o-reference-harness-v2"), "runner calls retired Task93 harness");
requireCondition(!runner.includes("llama-omni-server"),
  "runner names a binary not produced by the locked upstream commit");
requireCondition(!runner.includes('"--vision"') && !runner.includes('"--audio"') &&
  !runner.includes('"--no-tts"'), "runner bypasses Comni model initialization");

const adapter = read("tools/o-official-reference/src/official_adapter.cpp");
const core = read("tools/o-official-reference/src/official_reference_core.cpp");
requireCondition(adapter.includes('required(options, "prompt-file")'),
  "adapter does not inject the V2 prompt into official init");
requireCondition(core.includes("voice_clone_prompt") && core.includes("assistant_prompt"),
  "Comni prompt wrappers are missing");

const packageManifest = JSON.parse(read("tools/o-official-reference/package-manifest.json"));
requireCondition(packageManifest.artifact_name ===
  "AIJARVISV2-93-o-official-reference-windows-x64-cuda", "artifact name changed");
for (const required of [
  "bin/llama-server.exe",
  "bin/aijarvisv2-o-official-adapter.exe",
  "run-o-official-reference.ps1",
  "official-config.json",
  "upstream-lock.json",
  "fixture/O-IN-07/manifest.json",
  "licenses/llama.cpp-omni/LICENSE",
]) {
  requireCondition(packageManifest.required_files.includes(required),
    `package manifest missing ${required}`);
}
requireCondition(packageManifest.models_included === false, "models must remain external");

const upstreamLock = JSON.parse(read("tools/o-official-reference/upstream-lock.json"));
const runtimeLock = upstreamLock.components.find((component) => component.name === "llama.cpp-omni");
requireCondition(runtimeLock?.cmake_target === "llama-server",
  "upstream lock does not record the real CMake target");
requireCondition(runtimeLock?.binary === "llama-server",
  "upstream lock does not record the real upstream binary");

const workflow = read(".github/workflows/aijarvisv2-23-portable.yml");
for (const required of [
  "codex/aijarvisv2-93-official-first",
  "5202b7b2f4d11f50b9f996161e7a2f8b8571b890",
  "--target llama-server",
  "AIJARVISV2-93-o-official-reference-windows-x64-cuda",
  "tools/o-official-reference/package-official.ps1",
]) {
  requireCondition(workflow.includes(required), `workflow missing ${required}`);
}
requireCondition(!workflow.includes("task93-powershell-5-no-gpu"),
  "registered workflow still calls retired Task93 job");
requireCondition(!workflow.includes("tools/o-reference-harness-v2"),
  "registered workflow still calls retired Task93 harness");
requireCondition(!workflow.includes("llama-omni-server"),
  "registered workflow names a target absent from the locked upstream commit");

const workflowRoot = path.join(repositoryRoot, ".github", "workflows");
for (const file of fs.readdirSync(workflowRoot).filter((name) => /\.ya?ml$/.test(name))) {
  const source = fs.readFileSync(path.join(workflowRoot, file), "utf8");
  requireCondition(!source.includes("tools/o-reference-harness-v2"),
    `${file} still calls retired Task93 harness`);
}

console.log("official static verification: PASS");
