#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace o_reference_harness {

enum class RuntimeBoundaryReason {
  listen_transition,
  generation_change,
  session_end_drain,
  input_exhausted,
  failure,
  timeout,
};

enum class PayloadParseState {
  not_requested,
  payload_incomplete,
  payload_complete,
  payload_invalid,
};

enum class PayloadSchemaState {
  not_requested,
  not_evaluated,
  schema_valid,
  schema_invalid,
};

std::string to_string(RuntimeBoundaryReason value);
std::string to_string(PayloadParseState value);
std::string to_string(PayloadSchemaState value);

struct RawRuntimeResult {
  std::uint64_t user_seq{};
  std::int64_t frame_id{};
  int generation_id{};
  bool ok{};
  bool is_speak{};
  std::string fragment;
  double latency_ms{};
  std::int64_t input_offset_ms{};
  std::int64_t input_duration_ms{};
  std::int64_t seen_at_us{};
};

struct FragmentRecord {
  std::size_t fragment_index{};
  RawRuntimeResult runtime_result;
};

struct AggregatedResult {
  std::string logical_key;
  int generation_id{};
  std::size_t logical_sequence{};
  std::vector<FragmentRecord> fragments;
  std::string aggregated_text;
  std::int64_t first_seen_us{};
  std::int64_t last_seen_us{};
  std::optional<RuntimeBoundaryReason> runtime_boundary_reason;
  PayloadParseState payload_parse_state{PayloadParseState::not_requested};
  PayloadSchemaState payload_schema_state{PayloadSchemaState::not_requested};
};

struct Summary {
  bool model_loaded{};
  std::size_t input_processed{};
  std::size_t listen_count{};
  std::size_t speak_count{};
  std::size_t fragment_count{};
  std::size_t aggregated_payload_count{};
  std::size_t complete_payload_count{};
  std::size_t incomplete_payload_count{};
  std::size_t valid_three_batch_count{};
  std::size_t runtime_failure_count{};
};

struct AggregationReport {
  std::vector<RawRuntimeResult> raw_results;
  std::vector<AggregatedResult> aggregations;
  Summary summary;
};

struct AggregationOptions {
  bool validate_v2_contract{};
  std::vector<std::string> style_ids;
};

class Aggregator {
 public:
  explicit Aggregator(AggregationOptions options);
  void consume(const RawRuntimeResult& result);
  void boundary(RuntimeBoundaryReason reason);
  [[nodiscard]] const AggregationReport& report() const;

 private:
  void start(const RawRuntimeResult& result);
  void append(const RawRuntimeResult& result);
  void finalize(std::optional<RuntimeBoundaryReason> reason);
  void update_payload_state();

  AggregationOptions options_;
  AggregationReport report_;
  std::optional<AggregatedResult> current_;
  std::optional<int> last_generation_;
  std::optional<std::uint64_t> last_user_seq_;
  std::size_t next_logical_sequence_{1};
};

struct Profile {
  std::string id;
  std::string prompt_source;
  std::string system_prompt;
  std::string assistant_prompt;
  bool validate_v2_contract{};
  std::vector<std::string> style_ids;
};

Profile load_profile(const std::filesystem::path& path);

struct InputChunk {
  std::size_t index{};
  std::int64_t offset_ms{};
  std::int64_t duration_ms{};
  std::string marker;
  std::filesystem::path audio;
  std::filesystem::path image;
  std::string audio_sha256;
  std::string image_sha256;
};

struct InputManifest {
  std::string id;
  std::string cadence_id;
  std::int64_t cadence_ms{};
  std::int64_t duration_ms{};
  std::filesystem::path source_path;
  std::vector<InputChunk> chunks;
};

struct DryRunInput {
  std::size_t index{};
  std::int64_t offset_ms{};
  std::int64_t duration_ms{};
  std::string marker;
  std::filesystem::path audio;
  std::filesystem::path image;
};

InputManifest load_manifest(const std::filesystem::path& path, bool verify_assets);
std::vector<DryRunInput> build_dry_run(const InputManifest& manifest);

}  // namespace o_reference_harness
