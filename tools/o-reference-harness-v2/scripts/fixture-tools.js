"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function sha256Buffer(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function readWave(filePath) {
  const source = fs.readFileSync(filePath);
  if (source.toString("ascii", 0, 4) !== "RIFF" || source.toString("ascii", 8, 12) !== "WAVE") {
    throw new Error(`not a RIFF/WAVE file: ${filePath}`);
  }
  let cursor = 12;
  let format = null;
  let pcm = null;
  while (cursor + 8 <= source.length) {
    const id = source.toString("ascii", cursor, cursor + 4);
    const size = source.readUInt32LE(cursor + 4);
    const start = cursor + 8;
    if (start + size > source.length) throw new Error(`truncated WAV chunk: ${filePath}`);
    if (id === "fmt ") {
      format = {
        audioFormat: source.readUInt16LE(start),
        channels: source.readUInt16LE(start + 2),
        sampleRate: source.readUInt32LE(start + 4),
        byteRate: source.readUInt32LE(start + 8),
        blockAlign: source.readUInt16LE(start + 12),
        bitsPerSample: source.readUInt16LE(start + 14)
      };
    } else if (id === "data") {
      pcm = source.subarray(start, start + size);
    }
    cursor = start + size + (size % 2);
  }
  if (!format || !pcm) throw new Error(`WAV lacks fmt or data: ${filePath}`);
  const frames = pcm.length / format.blockAlign;
  return { ...format, pcm, frames, durationMs: frames / format.sampleRate * 1000 };
}

function writePcmWave(filePath, pcm, sampleRate = 16000, channels = 1, bitsPerSample = 16) {
  const blockAlign = channels * bitsPerSample / 8;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8, "ascii");
  header.write("fmt ", 12, "ascii");
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * blockAlign, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write("data", 36, "ascii");
  header.writeUInt32LE(pcm.length, 40);
  fs.writeFileSync(filePath, Buffer.concat([header, pcm]));
}

function validateOneHzFixture(oneHzRoot) {
  const manifest = readJson(path.join(oneHzRoot, "manifest.json"));
  if (manifest.input_id !== "O-IN-07" || manifest.chunks.length !== 33 ||
      manifest.duration_ms !== 33000 || manifest.slice_duration_ms !== 1000) {
    throw new Error("official-1hz manifest identity or cadence is invalid");
  }
  let hashesVerified = 0;
  for (let index = 0; index < manifest.chunks.length; index += 1) {
    const chunk = manifest.chunks[index];
    const sequence = index + 1;
    if (chunk.sequence !== sequence || chunk.offset_ms !== index * 1000 ||
        chunk.duration_ms !== 1000 || chunk.source_sequence !== Math.floor(index / 3) + 1 ||
        chunk.source_part !== index % 3 + 1 ||
        !chunk.marker.endsWith(`-part-${chunk.source_part}-of-3`)) {
      throw new Error(`official-1hz timeline or marker mismatch at ${sequence}`);
    }
    const audioPath = path.join(oneHzRoot, chunk.audio);
    const imagePath = path.join(oneHzRoot, chunk.image);
    if (sha256File(audioPath) !== chunk.audio_sha256 || sha256File(imagePath) !== chunk.image_sha256) {
      throw new Error(`official-1hz SHA-256 mismatch at ${sequence}`);
    }
    hashesVerified += 2;
    const wave = readWave(audioPath);
    if (wave.audioFormat !== 1 || wave.channels !== 1 || wave.sampleRate !== 16000 ||
        wave.bitsPerSample !== 16 || wave.frames !== 16000 || wave.durationMs !== 1000) {
      throw new Error(`official-1hz PCM format mismatch at ${sequence}`);
    }
  }
  for (const [record, expected] of [
    [manifest.authorization_record, manifest.authorization_sha256],
    [manifest.gold_record, manifest.gold_sha256]
  ]) {
    if (sha256File(path.join(oneHzRoot, record)) !== expected) {
      throw new Error(`official-1hz metadata SHA-256 mismatch: ${record}`);
    }
    hashesVerified += 1;
  }
  for (let group = 0; group < 11; group += 1) {
    const hashes = manifest.chunks.slice(group * 3, group * 3 + 3).map((chunk) => chunk.image_sha256);
    if (!hashes.every((hash) => hash === hashes[0])) {
      throw new Error(`official-1hz vision mapping mismatch at source ${group + 1}`);
    }
  }
  return {
    chunk_count: 33,
    cadence_ms: 1000,
    duration_ms: 33000,
    pcm_format: "16000Hz-mono-16bit-PCM",
    hashes_verified: hashesVerified,
    markers_preserved: true,
    vision_mapping_explicit: true
  };
}

function materializeLegacyFixture({ oneHzRoot, sourceSnapshot, manifestPath, destination }) {
  validateOneHzFixture(oneHzRoot);
  const oneHz = readJson(path.join(oneHzRoot, "manifest.json"));
  const snapshot = readJson(sourceSnapshot);
  const manifest = readJson(manifestPath);
  if (snapshot.chunks.length !== 11 || manifest.chunks.length !== 11 ||
      snapshot.duration_ms !== 33000 || manifest.duration_ms !== 33000) {
    throw new Error("legacy-3s manifest or snapshot is incomplete");
  }
  const outputChunks = path.join(destination, "chunks");
  fs.mkdirSync(outputChunks, { recursive: true });
  const inputOrder = [];
  for (let index = 0; index < 11; index += 1) {
    const sequence = index + 1;
    const declared = manifest.chunks[index];
    const expected = snapshot.chunks[index];
    const parts = oneHz.chunks.slice(index * 3, index * 3 + 3);
    if (declared.sequence !== sequence || declared.offset_ms !== index * 3000 ||
        declared.duration_ms !== 3000 || declared.marker !== expected.marker ||
        parts.some((part) => part.source_sequence !== sequence)) {
      throw new Error(`legacy-3s mapping mismatch at ${sequence}`);
    }
    const waves = parts.map((part) => readWave(path.join(oneHzRoot, part.audio)));
    const pcm = Buffer.concat(waves.map((wave) => wave.pcm));
    const stem = String(sequence).padStart(4, "0");
    const audioPath = path.join(outputChunks, `${stem}.wav`);
    const imagePath = path.join(outputChunks, `${stem}.jpg`);
    writePcmWave(audioPath, pcm);
    fs.copyFileSync(path.join(oneHzRoot, parts[0].image), imagePath);
    if (readWave(audioPath).durationMs !== 3000 ||
        sha256File(audioPath) !== expected.audio_sha256 ||
        sha256File(imagePath) !== expected.image_sha256 ||
        expected.audio_sha256 !== declared.audio_sha256 ||
        expected.image_sha256 !== declared.image_sha256) {
      throw new Error(`legacy-3s reconstructed asset mismatch at ${sequence}`);
    }
    inputOrder.push(sequence);
  }
  return {
    chunk_count: 11,
    cadence_ms: 3000,
    duration_ms: 33000,
    audio_recomposition_matches: true,
    vision_mapping_matches: true,
    marker_mapping_matches: true,
    snapshot_hashes_match: true,
    input_order: inputOrder
  };
}

function validateLegacyFixture(manifestPath) {
  const manifest = readJson(manifestPath);
  const root = path.dirname(manifestPath);
  if (manifest.input_id !== "O-IN-07" || manifest.cadence_id !== "legacy-3s-replay" ||
      manifest.chunks.length !== 11 || manifest.duration_ms !== 33000) {
    throw new Error("legacy-3s manifest identity is invalid");
  }
  let hashesVerified = 0;
  for (let index = 0; index < manifest.chunks.length; index += 1) {
    const chunk = manifest.chunks[index];
    if (chunk.sequence !== index + 1 || chunk.offset_ms !== index * 3000 ||
        chunk.duration_ms !== 3000 || !chunk.marker) {
      throw new Error(`legacy-3s timeline mismatch at ${index + 1}`);
    }
    const audioPath = path.resolve(root, chunk.audio);
    const imagePath = path.resolve(root, chunk.image);
    if (sha256File(audioPath) !== chunk.audio_sha256 || sha256File(imagePath) !== chunk.image_sha256) {
      throw new Error(`legacy-3s SHA-256 mismatch at ${index + 1}`);
    }
    hashesVerified += 2;
    const wave = readWave(audioPath);
    if (wave.audioFormat !== 1 || wave.channels !== 1 || wave.sampleRate !== 16000 ||
        wave.bitsPerSample !== 16 || wave.frames !== 48000 || wave.durationMs !== 3000) {
      throw new Error(`legacy-3s PCM format mismatch at ${index + 1}`);
    }
  }
  return {
    chunk_count: manifest.chunks.length,
    hashes_verified: hashesVerified,
    pcm_format: "16000Hz-mono-16bit-PCM",
    duration_ms: manifest.duration_ms
  };
}

function validateRunnerConfig(configPath, repositoryRoot) {
  const config = readJson(configPath);
  const profiles = Object.keys(config.profiles);
  const cadences = Object.keys(config.cadences);
  if (profiles.length !== 2 || cadences.length !== 2 ||
      config.model_files.length !== 3 ||
      config.windows_nvidia_execution !== "DYNAMIC-ONLY") {
    throw new Error("runner config identity is invalid");
  }
  for (const entry of [...Object.values(config.profiles), ...Object.values(config.cadences)]) {
    const sourcePath = path.join(repositoryRoot, entry.source_path);
    if (sha256File(sourcePath) !== entry.sha256) {
      throw new Error(`runner config source SHA-256 mismatch: ${entry.source_path}`);
    }
  }
  const official = readJson(path.join(repositoryRoot, config.profiles["official-runtime-reference"].source_path));
  const contract = readJson(path.join(repositoryRoot, config.profiles["v2-contract"].source_path));
  if (official.validate_v2_contract !== false || contract.validate_v2_contract !== true ||
      JSON.stringify(config.cadences).includes("chunk_count") ||
      JSON.stringify(config.cadences).includes("duration_ms")) {
    throw new Error("runner config mixes profile contracts or hardcodes cadence shape");
  }
  return {
    profiles,
    cadences,
    profile_contracts_separated: true,
    cadence_from_manifest: true,
    locked_model_hashes: config.model_files.length,
    locked_runtime_revision: config.runtime_revision,
    result_root_isolated_by_profile_and_cadence:
      config.result_root_pattern === "results/{profile}/{cadence}/{run_id}",
    windows_nvidia_execution: config.windows_nvidia_execution
  };
}

module.exports = {
  materializeLegacyFixture,
  readWave,
  sha256File,
  validateLegacyFixture,
  validateOneHzFixture,
  validateRunnerConfig
};

if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length !== 5 || args[0] !== "materialize-legacy") {
    process.stderr.write("usage: fixture-tools.js materialize-legacy ONE_HZ_ROOT SOURCE_SNAPSHOT MANIFEST DESTINATION\n");
    process.exitCode = 2;
  } else {
    const report = materializeLegacyFixture({
      oneHzRoot: path.resolve(args[1]),
      sourceSnapshot: path.resolve(args[2]),
      manifestPath: path.resolve(args[3]),
      destination: path.resolve(args[4])
    });
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  }
}
