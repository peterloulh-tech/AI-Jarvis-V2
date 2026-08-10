#include "o_reference_harness/core.hpp"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using namespace o_reference_harness;

namespace {

void require(bool condition, const std::string& message) {
  if (!condition) throw std::runtime_error(message);
}

RawRuntimeResult speak(std::uint64_t sequence, std::string fragment,
                       int generation = 4) {
  return RawRuntimeResult{.user_seq = sequence,
                          .frame_id = static_cast<std::int64_t>(sequence),
                          .generation_id = generation,
                          .ok = true,
                          .is_speak = true,
                          .fragment = std::move(fragment),
                          .latency_ms = 12.5,
                          .input_offset_ms = static_cast<std::int64_t>(sequence) * 1000,
                          .input_duration_ms = 1000,
                          .seen_at_us = static_cast<std::int64_t>(sequence) * 1000000};
}

RawRuntimeResult listen(std::uint64_t sequence, int generation = 4) {
  auto value = speak(sequence, "", generation);
  value.is_speak = false;
  return value;
}

AggregationOptions v2_options() {
  return AggregationOptions{.validate_v2_contract = true,
                            .style_ids = {"style-1", "style-2", "style-3"}};
}

void test_legacy_fragments_remain_ordered_incomplete_prefix() {
  Aggregator aggregator(v2_options());
  aggregator.consume(speak(4, R"({"batches": [{"style_id":"style-)"));
  aggregator.consume(speak(5, R"(1", "items": ["01 开)"));
  aggregator.consume(speak(6, R"(始。"]}, {"style_id":"style-)"));
  aggregator.consume(speak(7, R"(2", "items": ["0)"));
  aggregator.boundary(RuntimeBoundaryReason::input_exhausted);

  const auto& report = aggregator.report();
  require(report.raw_results.size() == 4, "all raw fragments must be retained");
  require(report.aggregations.size() == 1, "one contiguous SPEAK aggregation expected");
  const auto& aggregate = report.aggregations.front();
  require(aggregate.logical_key == "g4-s1", "logical key must identify generation and segment");
  require(aggregate.fragments.size() == 4, "four ordered fragments expected");
  require(aggregate.fragments[0].fragment_index == 1 &&
              aggregate.fragments[3].fragment_index == 4,
          "fragment indexes must preserve order");
  require(aggregate.aggregated_text ==
              R"({"batches": [{"style_id":"style-1", "items": ["01 开始。"]}, {"style_id":"style-2", "items": ["0)",
          "legacy prefix must aggregate byte-for-byte");
  require(aggregate.payload_parse_state == PayloadParseState::payload_incomplete,
          "incomplete prefix must not become invalid final payload");
  require(aggregate.payload_schema_state == PayloadSchemaState::not_evaluated,
          "schema cannot be evaluated before JSON completes");
  require(aggregate.runtime_boundary_reason == RuntimeBoundaryReason::input_exhausted,
          "observable input exhaustion must be recorded");
}

void test_complete_three_batch_payload_passes_contract_without_runtime_eos() {
  const std::string payload =
      R"({"batches":[{"style_id":"style-1","items":["a"]},{"style_id":"style-2","items":["b"]},{"style_id":"style-3","items":["c"]}]})";
  Aggregator aggregator(v2_options());
  aggregator.consume(speak(8, payload.substr(0, 52)));
  aggregator.consume(speak(9, payload.substr(52)));

  const auto& report = aggregator.report();
  require(report.aggregations.size() == 1, "complete payload must form one aggregation");
  const auto& aggregate = report.aggregations.front();
  require(aggregate.payload_parse_state == PayloadParseState::payload_complete,
          "complete JSON must be recognized");
  require(aggregate.payload_schema_state == PayloadSchemaState::schema_valid,
          "three-batch contract must pass");
  require(!aggregate.runtime_boundary_reason.has_value(),
          "payload completion must not manufacture runtime EOS");
  require(report.summary.complete_payload_count == 1 &&
              report.summary.valid_three_batch_count == 1,
          "summary must count complete valid payload");
}

void test_official_profile_does_not_require_v2_json() {
  Aggregator aggregator(AggregationOptions{.validate_v2_contract = false});
  aggregator.consume(speak(4, "plain official runtime text"));
  aggregator.consume(listen(5));

  const auto& aggregate = aggregator.report().aggregations.front();
  require(aggregate.runtime_boundary_reason == RuntimeBoundaryReason::listen_transition,
          "LISTEN must close the observable SPEAK segment");
  require(aggregate.payload_parse_state == PayloadParseState::not_requested,
          "official runtime profile must not require JSON");
  require(aggregate.payload_schema_state == PayloadSchemaState::not_requested,
          "official runtime profile must not run V2 schema validation");
}

void test_generation_change_timeout_failure_and_order_detection() {
  Aggregator generation(v2_options());
  generation.consume(speak(4, R"({"batches":)"));
  generation.consume(speak(1, R"([]})", 5));
  require(generation.report().aggregations.front().runtime_boundary_reason ==
              RuntimeBoundaryReason::generation_change,
          "generation change must be an explicit runtime boundary");

  Aggregator timeout(v2_options());
  timeout.consume(speak(1, R"({"batches":)"));
  timeout.boundary(RuntimeBoundaryReason::timeout);
  require(timeout.report().aggregations.front().payload_parse_state ==
              PayloadParseState::payload_incomplete,
          "timeout must preserve incomplete payload");

  Aggregator failure(v2_options());
  auto failed = listen(2);
  failed.ok = false;
  failure.consume(failed);
  require(failure.report().summary.runtime_failure_count == 1,
          "failed result must not count as LISTEN");
  require(failure.report().summary.listen_count == 0,
          "failed result must stay separate from model decisions");

  Aggregator order(v2_options());
  order.consume(speak(10, "a"));
  bool detected = false;
  try {
    order.consume(speak(9, "b"));
  } catch (const std::invalid_argument&) {
    detected = true;
  }
  require(detected, "out-of-order fragment sequence must be rejected");
  require(order.report().raw_results.size() == 1 &&
              order.report().summary.input_processed == 1,
          "rejected results must not contaminate raw evidence or summary counters");

  Aggregator duplicate(v2_options());
  duplicate.consume(speak(10, "a"));
  detected = false;
  try {
    duplicate.consume(speak(10, "b"));
  } catch (const std::invalid_argument&) {
    detected = true;
  }
  require(detected && duplicate.report().raw_results.size() == 1,
          "duplicate results must be rejected without contaminating evidence");
}

void test_payload_completion_runtime_continuation_and_invalid_summary() {
  const std::string payload =
      R"({"batches":[{"style_id":"style-1","items":["中文一"]},{"style_id":"style-2","items":["中文二"]},{"style_id":"style-3","items":["中文三"]}]})";
  Aggregator continuation(v2_options());
  continuation.consume(speak(1, payload.substr(0, 40)));
  continuation.consume(speak(2, payload.substr(40)));
  continuation.consume(speak(3, ""));
  continuation.consume(listen(4));
  require(continuation.report().aggregations.size() == 2,
          "runtime results after payload completion must remain observable");
  require(continuation.report().aggregations[0].payload_parse_state ==
              PayloadParseState::payload_complete &&
              continuation.report().aggregations[1].payload_parse_state ==
                  PayloadParseState::payload_incomplete,
          "a later empty SPEAK must not be merged into the completed payload");
  require(continuation.report().summary.speak_count == 3 &&
              continuation.report().summary.listen_count == 1,
          "continuation decisions must be counted without hiding the empty fragment");

  Aggregator invalid(v2_options());
  invalid.consume(speak(1, R"({"batches":]})"));
  invalid.boundary(RuntimeBoundaryReason::session_end_drain);
  require(invalid.report().summary.invalid_payload_count == 1 &&
              invalid.report().summary.incomplete_payload_count == 0,
          "invalid JSON must not be misreported as incomplete JSON");
  invalid.boundary(RuntimeBoundaryReason::session_end_drain);
  require(invalid.report().aggregations.size() == 1,
          "repeated drain/cleanup boundaries must be idempotent");
}

void test_profiles_are_explicitly_separated(const fs::path& repository_root) {
  const auto official = load_profile(repository_root /
                                     "tools/o-reference-harness-v2/profiles/official-runtime-reference.json");
  const auto contract = load_profile(repository_root /
                                     "tools/o-reference-harness-v2/profiles/v2-contract.json");
  require(official.id == "official-runtime-reference" && !official.validate_v2_contract,
          "official profile must not include V2 contract success criteria");
  require(contract.id == "v2-contract" && contract.validate_v2_contract,
          "V2 profile must enable the three-batch contract");
  require(contract.style_ids == std::vector<std::string>({"style-1", "style-2", "style-3"}),
          "V2 style order must be explicit");
}

void test_manifest_is_driven_by_declared_cadence(const fs::path& repository_root) {
  const auto one_hz = load_manifest(
      repository_root /
      "tools/aijarvisv2-23/AIJARVISV2-23-NEXT-WIN-DELTA/O-IN-07-1HZ/manifest.json",
      true);
  const auto legacy = load_manifest(
      repository_root /
      "tools/o-reference-harness-v2/fixtures/manifests/legacy-3s-replay.json",
      true);
  require(one_hz.chunks.size() == 33 && one_hz.cadence_ms == 1000,
          "official fixture must expose 33 one-second chunks");
  require(legacy.chunks.size() == 11 && legacy.cadence_ms == 3000,
          "legacy fixture must expose 11 three-second chunks");
  require(one_hz.duration_ms == legacy.duration_ms && one_hz.duration_ms == 33000,
          "both manifests must preserve the same total timeline");
  const auto dry_run = build_dry_run(one_hz);
  require(dry_run.front().index == 1 && dry_run.front().offset_ms == 0 &&
              dry_run.back().index == 33 && dry_run.back().offset_ms == 32000,
          "dry-run order must come from the manifest");
}

}  // namespace

int main(int argc, char** argv) {
  try {
    if (argc != 2) throw std::runtime_error("usage: core-tests REPOSITORY_ROOT");
    const fs::path repository_root = fs::absolute(argv[1]);
    const std::vector<std::pair<const char*, void (*)()>> tests{
        {"legacy fragments", test_legacy_fragments_remain_ordered_incomplete_prefix},
        {"complete payload", test_complete_three_batch_payload_passes_contract_without_runtime_eos},
        {"official profile", test_official_profile_does_not_require_v2_json},
        {"boundaries", test_generation_change_timeout_failure_and_order_detection},
        {"continuation and invalid summary",
         test_payload_completion_runtime_continuation_and_invalid_summary}};
    for (const auto& [name, test] : tests) {
      test();
      std::cout << "PASS " << name << '\n';
    }
    test_profiles_are_explicitly_separated(repository_root);
    std::cout << "PASS profile separation\n";
    test_manifest_is_driven_by_declared_cadence(repository_root);
    std::cout << "PASS manifest cadence\n";
    return EXIT_SUCCESS;
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
