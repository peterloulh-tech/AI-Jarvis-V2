#include "o_reference_harness/core.hpp"

#ifdef O_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME
#include "o_reference_harness/locked_runtime.hpp"
#endif

#include <nlohmann/json.hpp>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;
using json = nlohmann::json;
using namespace o_reference_harness;

namespace {

constexpr const char* kModelRepository = "openbmb/MiniCPM-o-4_5-gguf";
constexpr const char* kModelRevision = "502eec5b03eaee9d0d2ce17a176e3490103c9a63";
constexpr const char* kRuntimeRevision = "b9d15b83ee353b2eaeee4d9318c98a35a1347486";
constexpr const char* kRuntimePatchSha256 =
    "cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e";

std::map<std::string, std::string> parse_options(int argc, char** argv, int start) {
  std::map<std::string, std::string> options;
  for (int index = start; index < argc; index += 2) {
    if (index + 1 >= argc || std::string(argv[index]).rfind("--", 0) != 0) {
      throw std::invalid_argument("options must use --name value pairs");
    }
    options[std::string(argv[index]).substr(2)] = argv[index + 1];
  }
  return options;
}

std::string required(const std::map<std::string, std::string>& options,
                     const std::string& key) {
  const auto found = options.find(key);
  if (found == options.end() || found->second.empty()) {
    throw std::invalid_argument("missing --" + key);
  }
  return found->second;
}

void prepare_output_directory(const fs::path& output) {
  if (fs::exists(output)) {
    if (!fs::is_directory(output) || fs::directory_iterator(output) != fs::directory_iterator{}) {
      throw std::invalid_argument("output directory already contains results: " + output.string());
    }
  } else {
    fs::create_directories(output);
  }
}

void write_json(const fs::path& path, const json& value) {
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  if (!stream) throw std::runtime_error("cannot write " + path.string());
  stream << value.dump(2) << '\n';
}

void write_jsonl(const fs::path& path, const std::vector<json>& values) {
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  if (!stream) throw std::runtime_error("cannot write " + path.string());
  for (const auto& value : values) stream << value.dump() << '\n';
}

json metadata(const Profile& profile, const std::string& harness_commit,
              const std::string& execution_mode) {
  return json{{"schema_version", 1},
              {"model_repo", kModelRepository},
              {"model_revision", kModelRevision},
              {"model_files",
               {{{"path", "MiniCPM-o-4_5-Q4_K_M.gguf"},
                 {"sha256", "1237a97ee081b8abebc47aa7dad565701e8f5f904cdc92f6723ac4281bbc0932"}},
                {{"path", "vision/MiniCPM-o-4_5-vision-F16.gguf"},
                 {"sha256", "1453678cc4e4fe18de241952962e234f265cb8dda780773526103ab8ba82f421"}},
                {{"path", "audio/MiniCPM-o-4_5-audio-F16.gguf"},
                 {"sha256", "d5b188ac7feaf98e17175c3f9bd14bf269301bfd187439fdaa3e3a494fc32ef7"}}}},
              {"runtime_revision", kRuntimeRevision},
              {"runtime_patch_sha256", kRuntimePatchSha256},
              {"harness_commit", harness_commit},
              {"profile", profile.id},
              {"prompt_config",
               {{"source", profile.prompt_source},
                {"system_prompt", profile.system_prompt},
                {"assistant_prompt", profile.assistant_prompt}}},
              {"execution_mode", execution_mode},
              {"platform", execution_mode == "runtime" ? "dynamic" : "offline"},
              {"tts_enabled", false},
              {"reference_audio", nullptr}};
}

json raw_result_json(const RawRuntimeResult& value) {
  return json{{"user_seq", value.user_seq},
              {"frame_id", value.frame_id},
              {"generation_id", value.generation_id},
              {"ok", value.ok},
              {"is_speak", value.is_speak},
              {"fragment", value.fragment},
              {"latency_ms", value.latency_ms},
              {"input_offset_ms", value.input_offset_ms},
              {"input_duration_ms", value.input_duration_ms},
              {"seen_at_us", value.seen_at_us}};
}

json summary_json(const Summary& value) {
  return json{{"model_loaded", value.model_loaded},
              {"input_processed", value.input_processed},
              {"listen_count", value.listen_count},
              {"speak_count", value.speak_count},
              {"fragment_count", value.fragment_count},
              {"aggregated_payload_count", value.aggregated_payload_count},
              {"complete_payload_count", value.complete_payload_count},
              {"incomplete_payload_count", value.incomplete_payload_count},
              {"invalid_payload_count", value.invalid_payload_count},
              {"valid_three_batch_count", value.valid_three_batch_count},
              {"runtime_failure_count", value.runtime_failure_count}};
}

json aggregation_json(const AggregatedResult& value) {
  json fragments = json::array();
  for (const auto& fragment : value.fragments) {
    auto record = raw_result_json(fragment.runtime_result);
    record["fragment_index"] = fragment.fragment_index;
    fragments.push_back(std::move(record));
  }
  return json{{"logical_key", value.logical_key},
              {"generation_id", value.generation_id},
              {"logical_sequence", value.logical_sequence},
              {"fragments", std::move(fragments)},
              {"aggregated_text", value.aggregated_text},
              {"first_seen_us", value.first_seen_us},
              {"last_seen_us", value.last_seen_us},
              {"runtime_boundary_reason",
               value.runtime_boundary_reason
                   ? json(to_string(*value.runtime_boundary_reason))
                   : json(nullptr)},
              {"payload_parse_state", to_string(value.payload_parse_state)},
              {"payload_schema_state", to_string(value.payload_schema_state)}};
}

std::vector<json> boundary_ledger(const std::vector<RawRuntimeResult>& raw,
                                  RuntimeBoundaryReason final_reason,
                                  bool include_session_end) {
  std::vector<json> boundaries;
  std::optional<int> generation;
  for (const auto& result : raw) {
    if (generation && *generation != result.generation_id) {
      boundaries.push_back(json{{"reason", "generation_change"},
                                {"user_seq", result.user_seq},
                                {"from_generation", *generation},
                                {"to_generation", result.generation_id},
                                {"official_eos", false}});
    }
    generation = result.generation_id;
    if (!result.ok) {
      boundaries.push_back(json{{"reason", "failure"},
                                {"user_seq", result.user_seq},
                                {"official_eos", false}});
    } else if (!result.is_speak) {
      boundaries.push_back(json{{"reason", "listen_transition"},
                                {"user_seq", result.user_seq},
                                {"official_eos", false}});
    }
  }
  boundaries.push_back(json{{"reason", to_string(final_reason)}, {"official_eos", false}});
  if (include_session_end) {
    boundaries.push_back(json{{"reason", "session_end_drain"}, {"official_eos", false}});
  }
  return boundaries;
}

RuntimeBoundaryReason parse_boundary(const std::string& value) {
  if (value == "listen_transition") return RuntimeBoundaryReason::listen_transition;
  if (value == "generation_change") return RuntimeBoundaryReason::generation_change;
  if (value == "session_end_drain") return RuntimeBoundaryReason::session_end_drain;
  if (value == "input_exhausted") return RuntimeBoundaryReason::input_exhausted;
  if (value == "failure") return RuntimeBoundaryReason::failure;
  if (value == "timeout") return RuntimeBoundaryReason::timeout;
  throw std::invalid_argument("unknown boundary: " + value);
}

RawRuntimeResult parse_raw_result(const json& value, std::size_t line_number) {
  return RawRuntimeResult{
      .user_seq = value.at("user_seq").get<std::uint64_t>(),
      .frame_id = value.at("frame_id").get<std::int64_t>(),
      .generation_id = value.at("generation_id").get<int>(),
      .ok = value.at("ok").get<bool>(),
      .is_speak = value.at("is_speak").get<bool>(),
      .fragment = value.value("fragment", ""),
      .latency_ms = value.value("latency_ms", 0.0),
      .input_offset_ms = value.value("input_offset_ms", 0),
      .input_duration_ms = value.value("input_duration_ms", 0),
      .seen_at_us = value.value("seen_at_us", static_cast<std::int64_t>(line_number) * 1000000)};
}

int dry_run(const std::map<std::string, std::string>& options) {
  const auto profile = load_profile(required(options, "profile"));
  const auto manifest = load_manifest(required(options, "manifest"), true);
  const fs::path output = required(options, "output-dir");
  prepare_output_directory(output);
  write_json(output / "run-metadata.json",
             metadata(profile, required(options, "harness-commit"), "dry-run"));
  std::vector<json> inputs;
  for (const auto& input : build_dry_run(manifest)) {
    const auto audio = fs::absolute(input.audio).string();
    const auto image = fs::absolute(input.image).string();
    inputs.push_back(json{{"index", input.index},
                          {"offset_ms", input.offset_ms},
                          {"duration_ms", input.duration_ms},
                          {"marker", input.marker},
                          {"source_asset", {{"audio", audio}, {"image", image}}},
                          {"audio", audio},
                          {"image", image}});
  }
  write_jsonl(output / "inputs.jsonl", inputs);
  auto summary = summary_json(Summary{});
  summary["planned_input_count"] = inputs.size();
  summary["dynamic_runtime_status"] = "DYNAMIC-ONLY";
  write_json(output / "summary.json", summary);
  return 0;
}

int replay_results(const std::map<std::string, std::string>& options) {
  const auto profile = load_profile(required(options, "profile"));
  const auto final_boundary = parse_boundary(required(options, "boundary"));
  const fs::path input = fs::absolute(required(options, "input"));
  const fs::path output = required(options, "output-dir");
  prepare_output_directory(output);
  write_json(output / "run-metadata.json",
             metadata(profile, required(options, "harness-commit"), "replay-results"));
  Aggregator aggregator(AggregationOptions{.validate_v2_contract = profile.validate_v2_contract,
                                           .style_ids = profile.style_ids});
  std::ifstream stream(input, std::ios::binary);
  if (!stream) throw std::runtime_error("cannot open replay input");
  std::string line;
  std::size_t line_number = 0;
  std::optional<std::string> primary_error;
  while (std::getline(stream, line)) {
    ++line_number;
    if (line.empty()) continue;
    const auto value = json::parse(line, nullptr, false);
    if (value.is_discarded()) {
      primary_error = "line " + std::to_string(line_number) + ": malformed JSON";
      break;
    }
    try {
      aggregator.consume(parse_raw_result(value, line_number));
    } catch (const std::invalid_argument& error) {
      const std::string detail = error.what();
      primary_error = "line " + std::to_string(line_number) + ": " +
                      (detail.find("duplicate or out-of-order") != std::string::npos
                           ? std::string("duplicate or out-of-order result")
                           : std::string("invalid raw result: ") + detail);
      break;
    } catch (const std::exception& error) {
      primary_error = "line " + std::to_string(line_number) +
                      ": invalid raw result: " + error.what();
      break;
    }
  }
  const auto evidence_boundary = primary_error ? RuntimeBoundaryReason::failure : final_boundary;
  aggregator.boundary(evidence_boundary);
  const auto& report = aggregator.report();
  std::vector<json> raw;
  for (const auto& result : report.raw_results) raw.push_back(raw_result_json(result));
  write_jsonl(output / "raw-results.jsonl", raw);
  json aggregations = json::array();
  for (const auto& aggregate : report.aggregations) {
    aggregations.push_back(aggregation_json(aggregate));
  }
  write_json(output / "aggregations.json", aggregations);
  auto boundaries = boundary_ledger(report.raw_results, evidence_boundary, false);
  if (primary_error && !boundaries.empty()) {
    boundaries.back()["source"] = "mock_result_source";
  }
  write_jsonl(output / "runtime-boundaries.jsonl", boundaries);
  auto summary = summary_json(report.summary);
  summary["dynamic_runtime_status"] = "MOCK-RESULT-SOURCE";
  summary["outcome"] = primary_error ? "failed" : "passed";
  summary["error_count"] = primary_error ? 1 : 0;
  summary["primary_error"] = primary_error ? json(*primary_error) : json(nullptr);
  write_json(output / "summary.json", summary);
  write_json(output / "evidence.json",
             json{{"schema_version", 1},
                  {"outcome", primary_error ? "failed" : "passed"},
                  {"execution_mode", "mock_result_source"},
                  {"result_source", input.string()},
                  {"requested_boundary", to_string(final_boundary)},
                  {"final_boundary", to_string(evidence_boundary)},
                  {"primary_error", primary_error ? json(*primary_error) : json(nullptr)},
                  {"cleanup_error", nullptr}});
  if (primary_error) {
    std::cerr << "Mock result source failed: " << *primary_error << '\n';
    return 4;
  }
  return 0;
}

#ifdef O_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME
int run_runtime(const std::map<std::string, std::string>& options) {
  const auto profile = load_profile(required(options, "profile"));
  const auto manifest = load_manifest(required(options, "manifest"), true);
  const fs::path output = required(options, "output-dir");
  prepare_output_directory(output);
  write_json(output / "run-metadata.json",
             metadata(profile, required(options, "harness-commit"), "runtime"));

  Aggregator aggregator(AggregationOptions{.validate_v2_contract = profile.validate_v2_contract,
                                           .style_ids = profile.style_ids});
  const int generation = std::stoi(required(options, "generation"));
  const int result_timeout_ms = std::stoi(required(options, "result-timeout-ms"));
  LockedRuntime runtime(LockedModelConfig{.model_root = required(options, "model-root"),
                                          .output_root = output / "runtime-output"});
  fs::create_directories(output / "runtime-debug");
  runtime.begin(profile, output / "runtime-debug");

  std::vector<json> pushed_inputs;
  std::mutex pushed_mutex;
  std::exception_ptr producer_error;
  const auto started = std::chrono::steady_clock::now();
  std::thread producer([&] {
    try {
      for (const auto& input : manifest.chunks) {
        std::this_thread::sleep_until(started + std::chrono::milliseconds(input.offset_ms));
        const auto frame_id = runtime.push(input, generation);
        if (frame_id < 0) throw std::runtime_error("locked runtime rejected input frame");
        std::lock_guard lock(pushed_mutex);
        const auto audio = fs::absolute(input.audio).string();
        const auto image = fs::absolute(input.image).string();
        pushed_inputs.push_back(json{{"index", input.index},
                                     {"offset_ms", input.offset_ms},
                                     {"duration_ms", input.duration_ms},
                                     {"marker", input.marker},
                                     {"source_asset", {{"audio", audio}, {"image", image}}},
                                     {"audio", audio},
                                     {"image", image},
                                     {"frame_id", frame_id}});
      }
    } catch (...) {
      producer_error = std::current_exception();
    }
  });

  bool timed_out = false;
  for (std::size_t index = 0; index < manifest.chunks.size(); ++index) {
    const auto result = runtime.wait(result_timeout_ms);
    if (!result) {
      aggregator.boundary(RuntimeBoundaryReason::timeout);
      timed_out = true;
      break;
    }
    aggregator.consume(*result);
  }
  if (producer.joinable()) producer.join();
  if (producer_error) std::rethrow_exception(producer_error);
  if (!timed_out) aggregator.boundary(RuntimeBoundaryReason::input_exhausted);
  runtime.end();

  const auto& report = aggregator.report();
  std::vector<json> raw;
  for (const auto& result : report.raw_results) raw.push_back(raw_result_json(result));
  write_jsonl(output / "raw-results.jsonl", raw);
  write_jsonl(output / "inputs.jsonl", pushed_inputs);
  json aggregations = json::array();
  for (const auto& aggregate : report.aggregations) {
    aggregations.push_back(aggregation_json(aggregate));
  }
  write_json(output / "aggregations.json", aggregations);
  write_jsonl(output / "runtime-boundaries.jsonl",
              boundary_ledger(report.raw_results,
                              timed_out ? RuntimeBoundaryReason::timeout
                                        : RuntimeBoundaryReason::input_exhausted,
                              true));
  auto summary_value = report.summary;
  summary_value.model_loaded = true;
  auto summary = summary_json(summary_value);
  summary["planned_input_count"] = manifest.chunks.size();
  summary["dynamic_runtime_status"] = timed_out ? "timeout" : "completed_without_official_eos";
  write_json(output / "summary.json", summary);
  return timed_out ? 3 : 0;
}
#endif

}  // namespace

int main(int argc, char** argv) {
  try {
    if (argc < 2) throw std::invalid_argument("missing command");
    const std::string command = argv[1];
    const auto options = parse_options(argc, argv, 2);
    if (command == "dry-run") return dry_run(options);
    if (command == "replay-results") return replay_results(options);
#ifdef O_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME
    if (command == "run") return run_runtime(options);
#else
    if (command == "run") {
      throw std::invalid_argument("run is DYNAMIC-ONLY and this binary has no locked runtime");
    }
#endif
    throw std::invalid_argument("unsupported command: " + command);
  } catch (const std::exception& error) {
    std::cerr << "O Reference Harness v2 failed: " << error.what() << '\n';
    return 2;
  }
}
