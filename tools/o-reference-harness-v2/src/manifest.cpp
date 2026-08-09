#include "o_reference_harness/core.hpp"

#include <nlohmann/json.hpp>

#include <fstream>
#include <stdexcept>

namespace o_reference_harness {

InputManifest load_manifest(const std::filesystem::path& path, bool verify_assets) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) throw std::runtime_error("cannot open manifest: " + path.string());
  nlohmann::json source;
  stream >> source;
  InputManifest manifest;
  manifest.id = source.at("input_id").get<std::string>();
  manifest.cadence_id = source.value("cadence_id", source.value("diagnostic_label", ""));
  manifest.duration_ms = source.at("duration_ms").get<std::int64_t>();
  manifest.source_path = std::filesystem::absolute(path);
  const auto root = path.parent_path();
  const auto& chunks = source.at("chunks");
  if (!chunks.is_array() || chunks.empty()) throw std::runtime_error("manifest has no chunks");
  std::int64_t expected_offset = 0;
  std::int64_t cadence = -1;
  std::size_t expected_index = 1;
  for (const auto& item : chunks) {
    InputChunk chunk;
    chunk.index = item.at("sequence").get<std::size_t>();
    chunk.offset_ms = item.at("offset_ms").get<std::int64_t>();
    chunk.duration_ms = item.at("duration_ms").get<std::int64_t>();
    chunk.marker = item.at("marker").get<std::string>();
    chunk.audio = root / std::filesystem::path(item.at("audio").get<std::string>());
    chunk.image = root / std::filesystem::path(item.at("image").get<std::string>());
    chunk.audio_sha256 = item.value("audio_sha256", "");
    chunk.image_sha256 = item.value("image_sha256", "");
    if (chunk.index != expected_index || chunk.offset_ms != expected_offset ||
        chunk.duration_ms <= 0 || chunk.marker.empty()) {
      throw std::runtime_error("manifest timeline is not continuous at chunk " +
                               std::to_string(expected_index));
    }
    if (cadence < 0) cadence = chunk.duration_ms;
    if (chunk.duration_ms != cadence) throw std::runtime_error("mixed cadence manifest");
    if (verify_assets && (!std::filesystem::is_regular_file(chunk.audio) ||
                          !std::filesystem::is_regular_file(chunk.image))) {
      throw std::runtime_error("manifest input asset is missing at chunk " +
                               std::to_string(expected_index));
    }
    expected_offset += chunk.duration_ms;
    ++expected_index;
    manifest.chunks.push_back(std::move(chunk));
  }
  if (expected_offset != manifest.duration_ms) {
    throw std::runtime_error("manifest duration does not equal timeline end");
  }
  manifest.cadence_ms = cadence;
  return manifest;
}

std::vector<DryRunInput> build_dry_run(const InputManifest& manifest) {
  std::vector<DryRunInput> result;
  result.reserve(manifest.chunks.size());
  for (const auto& chunk : manifest.chunks) {
    result.push_back(DryRunInput{.index = chunk.index,
                                 .offset_ms = chunk.offset_ms,
                                 .duration_ms = chunk.duration_ms,
                                 .marker = chunk.marker,
                                 .audio = chunk.audio,
                                 .image = chunk.image});
  }
  return result;
}

}  // namespace o_reference_harness
