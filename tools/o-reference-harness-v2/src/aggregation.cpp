#include "o_reference_harness/core.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <stdexcept>

namespace o_reference_harness {
namespace {

enum class JsonShape { incomplete, complete, invalid };

JsonShape json_shape(const std::string& text) {
  std::vector<char> stack;
  bool in_string = false;
  bool escaped = false;
  bool saw_value = false;
  bool complete_root = false;
  for (const unsigned char byte : text) {
    const char value = static_cast<char>(byte);
    if (complete_root && !std::isspace(byte)) return JsonShape::invalid;
    if (in_string) {
      if (escaped) {
        escaped = false;
      } else if (value == '\\') {
        escaped = true;
      } else if (value == '"') {
        in_string = false;
      }
      continue;
    }
    if (value == '"') {
      in_string = true;
      saw_value = true;
    } else if (value == '{' || value == '[') {
      if (stack.empty()) {
        if (saw_value) return JsonShape::invalid;
        saw_value = true;
      }
      stack.push_back(value);
    } else if (value == '}' || value == ']') {
      if (stack.empty()) return JsonShape::invalid;
      const char expected = value == '}' ? '{' : '[';
      if (stack.back() != expected) return JsonShape::invalid;
      stack.pop_back();
      if (stack.empty()) complete_root = true;
    } else if (!std::isspace(byte) && stack.empty()) {
      return JsonShape::invalid;
    }
  }
  if (in_string || escaped || !stack.empty()) return JsonShape::incomplete;
  return complete_root ? JsonShape::complete : JsonShape::incomplete;
}

bool valid_three_batches(const nlohmann::json& payload,
                         const std::vector<std::string>& style_ids) {
  if (style_ids.size() != 3 || !payload.is_object() ||
      !payload.contains("batches") || !payload["batches"].is_array() ||
      payload["batches"].size() != 3) {
    return false;
  }
  for (std::size_t index = 0; index < 3; ++index) {
    const auto& batch = payload["batches"][index];
    if (!batch.is_object() || batch.value("style_id", "") != style_ids[index] ||
        !batch.contains("items") || !batch["items"].is_array() ||
        batch["items"].empty() ||
        std::any_of(batch["items"].begin(), batch["items"].end(),
                    [](const nlohmann::json& item) {
                      return !item.is_string() || item.get<std::string>().empty();
                    })) {
      return false;
    }
  }
  return true;
}

}  // namespace

std::string to_string(RuntimeBoundaryReason value) {
  switch (value) {
    case RuntimeBoundaryReason::listen_transition: return "listen_transition";
    case RuntimeBoundaryReason::generation_change: return "generation_change";
    case RuntimeBoundaryReason::session_end_drain: return "session_end_drain";
    case RuntimeBoundaryReason::input_exhausted: return "input_exhausted";
    case RuntimeBoundaryReason::failure: return "failure";
    case RuntimeBoundaryReason::timeout: return "timeout";
  }
  throw std::invalid_argument("unknown runtime boundary reason");
}

std::string to_string(PayloadParseState value) {
  switch (value) {
    case PayloadParseState::not_requested: return "not_requested";
    case PayloadParseState::payload_incomplete: return "payload_incomplete";
    case PayloadParseState::payload_complete: return "payload_complete";
    case PayloadParseState::payload_invalid: return "payload_invalid";
  }
  throw std::invalid_argument("unknown payload parse state");
}

std::string to_string(PayloadSchemaState value) {
  switch (value) {
    case PayloadSchemaState::not_requested: return "not_requested";
    case PayloadSchemaState::not_evaluated: return "not_evaluated";
    case PayloadSchemaState::schema_valid: return "schema_valid";
    case PayloadSchemaState::schema_invalid: return "schema_invalid";
  }
  throw std::invalid_argument("unknown payload schema state");
}

Aggregator::Aggregator(AggregationOptions options) : options_(std::move(options)) {
  if (options_.validate_v2_contract && options_.style_ids.size() != 3) {
    throw std::invalid_argument("v2-contract requires exactly three style ids");
  }
}

void Aggregator::consume(const RawRuntimeResult& result) {
  if (last_generation_ && *last_generation_ == result.generation_id &&
      last_user_seq_ && result.user_seq <= *last_user_seq_) {
    throw std::invalid_argument("duplicate or out-of-order raw runtime result");
  }
  report_.raw_results.push_back(result);
  ++report_.summary.input_processed;
  if (last_generation_ && *last_generation_ != result.generation_id) {
    finalize(RuntimeBoundaryReason::generation_change);
    last_user_seq_.reset();
  }
  last_generation_ = result.generation_id;
  last_user_seq_ = result.user_seq;

  if (!result.ok) {
    ++report_.summary.runtime_failure_count;
    finalize(RuntimeBoundaryReason::failure);
    return;
  }
  if (!result.is_speak) {
    ++report_.summary.listen_count;
    finalize(RuntimeBoundaryReason::listen_transition);
    return;
  }

  ++report_.summary.speak_count;
  ++report_.summary.fragment_count;
  if (!current_) start(result);
  append(result);
  update_payload_state();
  if (current_ && current_->payload_parse_state == PayloadParseState::payload_complete) {
    finalize(std::nullopt);
  }
}

void Aggregator::boundary(RuntimeBoundaryReason reason) { finalize(reason); }

const AggregationReport& Aggregator::report() const { return report_; }

void Aggregator::start(const RawRuntimeResult& result) {
  AggregatedResult aggregate;
  aggregate.generation_id = result.generation_id;
  aggregate.logical_sequence = next_logical_sequence_++;
  aggregate.logical_key = "g" + std::to_string(result.generation_id) + "-s" +
                          std::to_string(aggregate.logical_sequence);
  aggregate.first_seen_us = result.seen_at_us;
  aggregate.last_seen_us = result.seen_at_us;
  if (!options_.validate_v2_contract) {
    aggregate.payload_parse_state = PayloadParseState::not_requested;
    aggregate.payload_schema_state = PayloadSchemaState::not_requested;
  } else {
    aggregate.payload_parse_state = PayloadParseState::payload_incomplete;
    aggregate.payload_schema_state = PayloadSchemaState::not_evaluated;
  }
  current_ = std::move(aggregate);
}

void Aggregator::append(const RawRuntimeResult& result) {
  current_->fragments.push_back(
      FragmentRecord{.fragment_index = current_->fragments.size() + 1,
                     .runtime_result = result});
  current_->aggregated_text += result.fragment;
  current_->last_seen_us = result.seen_at_us;
}

void Aggregator::update_payload_state() {
  if (!options_.validate_v2_contract) return;
  const auto shape = json_shape(current_->aggregated_text);
  if (shape == JsonShape::incomplete) {
    current_->payload_parse_state = PayloadParseState::payload_incomplete;
    current_->payload_schema_state = PayloadSchemaState::not_evaluated;
    return;
  }
  if (shape == JsonShape::invalid) {
    current_->payload_parse_state = PayloadParseState::payload_invalid;
    current_->payload_schema_state = PayloadSchemaState::not_evaluated;
    return;
  }
  const auto parsed = nlohmann::json::parse(current_->aggregated_text, nullptr, false);
  if (parsed.is_discarded()) {
    current_->payload_parse_state = PayloadParseState::payload_invalid;
    current_->payload_schema_state = PayloadSchemaState::not_evaluated;
    return;
  }
  current_->payload_parse_state = PayloadParseState::payload_complete;
  current_->payload_schema_state = valid_three_batches(parsed, options_.style_ids)
                                       ? PayloadSchemaState::schema_valid
                                       : PayloadSchemaState::schema_invalid;
}

void Aggregator::finalize(std::optional<RuntimeBoundaryReason> reason) {
  if (!current_) return;
  current_->runtime_boundary_reason = reason;
  ++report_.summary.aggregated_payload_count;
  if (current_->payload_parse_state == PayloadParseState::payload_complete) {
    ++report_.summary.complete_payload_count;
    if (current_->payload_schema_state == PayloadSchemaState::schema_valid) {
      ++report_.summary.valid_three_batch_count;
    }
  } else if (current_->payload_parse_state == PayloadParseState::payload_incomplete &&
             options_.validate_v2_contract) {
    ++report_.summary.incomplete_payload_count;
  } else if (current_->payload_parse_state == PayloadParseState::payload_invalid) {
    ++report_.summary.invalid_payload_count;
  }
  report_.aggregations.push_back(std::move(*current_));
  current_.reset();
}

}  // namespace o_reference_harness
