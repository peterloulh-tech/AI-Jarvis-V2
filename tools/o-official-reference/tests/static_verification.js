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
  "llama-omni-server.exe",
  "health",
  "init",
  "step",
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
requireCondition(!runner.includes("llama-server.exe"),
  "runner still names the conflicting legacy server binary");
requireCondition(!runner.includes("adapterPath break"),
  "runner still calls the removed legacy HTTP break endpoint");
requireCondition(!runner.includes('"--vision"') && !runner.includes('"--audio"') &&
  !runner.includes('"--no-tts"'), "runner bypasses Comni model initialization");

const adapter = read("tools/o-official-reference/src/official_adapter.cpp");
const core = read("tools/o-official-reference/src/official_reference_core.cpp");
requireCondition(adapter.includes('required(options, "prompt-file")'),
  "adapter does not inject the V2 prompt into official init");
requireCondition(adapter.includes("build_init_prefill_request"),
  "adapter does not perform the current server's explicit index=0 system prefill");
requireCondition(core.includes("voice_clone_prompt") && core.includes("assistant_prompt"),
  "Comni prompt wrappers are missing");

const packageManifest = JSON.parse(read("tools/o-official-reference/package-manifest.json"));
requireCondition(packageManifest.artifact_name ===
  "AIJARVISV2-93-o-official-reference-windows-x64-cuda", "artifact name changed");
for (const required of [
  "bin/llama-omni-server.exe",
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
requireCondition(runtimeLock?.ref === "master",
  "upstream lock does not record the current maintained runtime ref");
requireCondition(runtimeLock?.commit === "09f5c3f1b484759f17b06fc63574f749c89c8761",
  "upstream lock does not record the current maintained runtime commit");
requireCondition(runtimeLock?.cmake_target === "llama-omni-server",
  "upstream lock does not record the real CMake target");
requireCondition(runtimeLock?.binary === "llama-omni-server",
  "upstream lock does not record the real upstream binary");
const demoLock = upstreamLock.components.find((component) => component.name === "MiniCPM-o-Demo-Comni");
requireCondition(demoLock?.ref === "main" &&
  demoLock?.commit === "d0a002093615b7f1d4d0f87a03fc01cb39bef3f6",
  "upstream lock does not record the current maintained Comni demo baseline");

const workflow = read(".github/workflows/aijarvisv2-23-portable.yml");
for (const required of [
  "codex/aijarvisv2-93-official-first",
  "09f5c3f1b484759f17b06fc63574f749c89c8761",
  "--target llama-omni-server",
  "AIJARVISV2-93-o-official-reference-windows-x64-cuda",
  "tools/o-official-reference/package-official.ps1",
]) {
  requireCondition(workflow.includes(required), `workflow missing ${required}`);
}
requireCondition(!workflow.includes("task93-powershell-5-no-gpu"),
  "registered workflow still calls retired Task93 job");
requireCondition(!workflow.includes("tools/o-reference-harness-v2"),
  "registered workflow still calls retired Task93 harness");
requireCondition(!workflow.includes("5202b7b2f4d11f50b9f996161e7a2f8b8571b890") &&
  !workflow.includes("--target llama-server"),
  "registered workflow still contains the conflicting legacy runtime route");

const workflowRoot = path.join(repositoryRoot, ".github", "workflows");
for (const file of fs.readdirSync(workflowRoot).filter((name) => /\.ya?ml$/.test(name))) {
  const source = fs.readFileSync(path.join(workflowRoot, file), "utf8");
  requireCondition(!source.includes("tools/o-reference-harness-v2"),
    `${file} still calls retired Task93 harness`);
}

console.log("official static verification: PASS");
