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
  " run `",
  'transport = "/backend"',
  "backend-events.json",
  "official_session_reuse",
  "nvidia-smi",
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
for (const forbidden of [
  "o-reference-harness-v2",
  "llama-server.exe",
  "raw-sse",
  "full_reinit",
  "/v1/stream/omni_init",
  "/v1/stream/prefill",
  "/v1/stream/decode",
]) {
  requireCondition(!runner.includes(forbidden), `runner retains conflicting boundary: ${forbidden}`);
}

const adapter = read("tools/o-official-reference/src/official_adapter.cpp");
const core = read("tools/o-official-reference/src/official_reference_core.cpp");
for (const required of [
  "WebSocketClient",
  'url + "/backend"',
  "build_session_init_request",
  "build_input_append_request",
  '"/sessions/" + session_id + "/close"',
]) {
  requireCondition(adapter.includes(required), `adapter missing official backend primitive: ${required}`);
}
requireCondition(core.includes('"type", "session.init"') &&
  core.includes('"type", "input.append"') && core.includes('"audio_base64"') &&
  core.includes('"video_frames"'), "official backend payload builders are incomplete");
requireCondition(core.includes('type == "response.done"') &&
  core.includes('kind == "listen"') && core.includes("is_terminal_backend_event"),
  "official backend terminal classification is incomplete");
requireCondition(!adapter.includes("SseCollector") && !core.includes("SseCollector") &&
  !adapter.includes("/v1/stream/") && !core.includes("build_init_prefill_request"),
  "HTTP/SSE boundary remains active");

const packageManifest = JSON.parse(read("tools/o-official-reference/package-manifest.json"));
requireCondition(packageManifest.artifact_name ===
  "AIJARVISV2-93-o-official-reference-windows-x64-cuda", "artifact name changed");
requireCondition(packageManifest.transport === "/backend", "package transport changed");
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

const config = JSON.parse(read("tools/o-official-reference/official-config.json"));
requireCondition(config.transport === "/backend" && config.runtime.use_tts === false,
  "active config is not official /backend no-TTS");

const upstreamLock = JSON.parse(read("tools/o-official-reference/upstream-lock.json"));
const runtimeLock = upstreamLock.components.find((component) => component.name === "llama.cpp-omni");
requireCondition(runtimeLock?.ref === "master" &&
  runtimeLock?.commit === "09f5c3f1b484759f17b06fc63574f749c89c8761" &&
  runtimeLock?.cmake_target === "llama-omni-server" &&
  runtimeLock?.binary === "llama-omni-server", "runtime lock changed");
requireCondition(runtimeLock.usage.includes("llama-omni-server /backend") &&
  runtimeLock.usage.includes("SessionManager") &&
  runtimeLock.usage.includes("omni_prepare_for_reuse"), "runtime provenance omits official lifecycle");
const demoLock = upstreamLock.components.find((component) => component.name === "MiniCPM-o-Demo-Comni");
requireCondition(demoLock?.ref === "main" &&
  demoLock?.commit === "d0a002093615b7f1d4d0f87a03fc01cb39bef3f6",
  "Comni lock changed");

const workflow = read(".github/workflows/aijarvisv2-23-portable.yml");
for (const required of [
  "09f5c3f1b484759f17b06fc63574f749c89c8761",
  '-G "Ninja Multi-Config"',
  "-DGGML_CUDA=ON",
  "-DGGML_CUDA_CUB_3DOT2=ON",
  "-DGGML_NATIVE=OFF",
  "-DLLAMA_CURL=OFF",
  "--target llama-omni-server",
  "AIJARVISV2-93-o-official-reference-windows-x64-cuda",
  "tools/o-official-reference/package-official.ps1",
]) {
  requireCondition(workflow.includes(required), `workflow missing ${required}`);
}
requireCondition(!workflow.includes("task93-powershell-5-no-gpu") &&
  !workflow.includes("tools/o-reference-harness-v2") &&
  !workflow.includes("5202b7b2f4d11f50b9f996161e7a2f8b8571b890") &&
  !workflow.includes("--target llama-server"), "workflow retains a conflicting Task93 route");
for (const stalePowerShellStatusCheck of [
  'if ($LASTEXITCODE -ne 0) { throw "Official-First packaging failed" }',
  'if ($LASTEXITCODE -ne 0) { throw "Packaged thin adapter dry-run failed" }',
]) {
  requireCondition(!workflow.includes(stalePowerShellStatusCheck),
    "workflow must not treat stale native LASTEXITCODE as a PowerShell script result");
}

const workflowRoot = path.join(repositoryRoot, ".github", "workflows");
for (const file of fs.readdirSync(workflowRoot).filter((name) => /\.ya?ml$/.test(name))) {
  const source = fs.readFileSync(path.join(workflowRoot, file), "utf8");
  requireCondition(!source.includes("tools/o-reference-harness-v2"),
    `${file} still calls retired Task93 harness`);
}

console.log("official static verification: PASS");
