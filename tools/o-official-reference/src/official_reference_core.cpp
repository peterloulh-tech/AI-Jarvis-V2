#include "official_reference_core.hpp"

#include <algorithm>
#include <array>
#include <set>
#include <stdexcept>

namespace aijarvis::official_o {
namespace {

std::vector<std::uint32_t> decode_utf8(const std::string &text) {
  std::vector<std::uint32_t> codepoints;
  for (std::size_t index = 0; index < text.size();) {
    const auto lead = static_cast<unsigned char>(text[index]);
    std::size_t width = 0;
    std::uint32_t value = 0;
    if (lead < 0x80) {
      width = 1;
      value = lead;
    } else if ((lead & 0xE0) == 0xC0) {
      width = 2;
      value = lead & 0x1F;
    } else if ((lead & 0xF0) == 0xE0) {
      width = 3;
      value = lead & 0x0F;
    } else if ((lead & 0xF8) == 0xF0) {
      width = 4;
      value = lead & 0x07;
    } else {
      throw std::runtime_error("invalid UTF-8 lead byte");
    }
    if (index + width > text.size()) throw std::runtime_error("truncated UTF-8");
    for (std::size_t offset = 1; offset < width; ++offset) {
      const auto next = static_cast<unsigned char>(text[index + offset]);
      if ((next & 0xC0) != 0x80) throw std::runtime_error("invalid UTF-8 continuation");
      value = (value << 6) | (next & 0x3F);
    }
    codepoints.push_back(value);
    index += width;
  }
  return codepoints;
}

bool contains_chinese(const std::string &text) {
  const auto codepoints = decode_utf8(text);
  return std::any_of(codepoints.begin(), codepoints.end(), [](std::uint32_t value) {
    return (value >= 0x3400 && value <= 0x4DBF) ||
           (value >= 0x4E00 && value <= 0x9FFF) ||
           (value >= 0xF900 && value <= 0xFAFF) ||
           (value >= 0x20000 && value <= 0x3134F);
  });
}

void require(bool condition, const std::string &message) {
  if (!condition) throw std::runtime_error(message);
}

bool is_sha256(const std::string &value) {
  return value.size() == 64 && std::all_of(value.begin(), value.end(), [](char character) {
    return (character >= '0' && character <= '9') ||
           (character >= 'a' && character <= 'f');
  });
}

}  // namespace

void SseCollector::feed(std::string_view bytes, std::int64_t elapsed_ms) {
  result_.raw_sse.append(bytes.data(), bytes.size());
  pending_.append(bytes.data(), bytes.size());
  for (;;) {
    const auto newline = pending_.find('\n');
    if (newline == std::string::npos) break;
    auto line = pending_.substr(0, newline);
    pending_.erase(0, newline + 1);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    consume_line(std::move(line), elapsed_ms);
  }
}

void SseCollector::finish(std::int64_t elapsed_ms) {
  if (!pending_.empty()) {
    auto line = std::move(pending_);
    pending_.clear();
    if (!line.empty() && line.back() == '\r') line.pop_back();
    consume_line(std::move(line), elapsed_ms);
  }
  require(result_.saw_done, "official SSE ended without [DONE]");
  if (result_.completion_latency_ms < 0) result_.completion_latency_ms = elapsed_ms;
}

const SseResult &SseCollector::result() const { return result_; }

void SseCollector::consume_line(std::string line, std::int64_t elapsed_ms) {
  if (line.empty() || line.front() == ':') return;
  if (line.rfind("data:", 0) != 0) return;
  auto data = line.substr(5);
  if (!data.empty() && data.front() == ' ') data.erase(0, 1);
  if (data == "[DONE]") {
    result_.saw_done = true;
    result_.completion_latency_ms = elapsed_ms;
    return;
  }

  const auto event = nlohmann::json::parse(data);
  require(event.is_object(), "official SSE data must be a JSON object");
  if (event.contains("content")) {
    require(event.at("content").is_string(), "SSE content must be a string");
    const auto fragment = event.at("content").get<std::string>();
    if (!fragment.empty()) {
      if (result_.first_fragment_latency_ms < 0) {
        result_.first_fragment_latency_ms = elapsed_ms;
      }
      result_.content += fragment;
    }
  }
  if (event.value("is_listen", false)) result_.saw_listen = true;
  if (event.value("stop", false)) result_.saw_stop = true;
}

nlohmann::json validate_contract(const std::string &text,
                                 const std::vector<std::string> &style_ids,
                                 std::size_t max_chinese_chars) {
  require(style_ids.size() == 3, "validator requires exactly three configured styles");
  const auto payload = nlohmann::json::parse(text);
  require(payload.is_object() && payload.contains("batches") &&
              payload.at("batches").is_array(),
          "payload must contain a batches array");
  const auto &batches = payload.at("batches");
  require(batches.size() == 3, "payload must contain exactly three batches");

  std::set<std::string> seen_styles;
  std::size_t character_count = 0;
  for (std::size_t index = 0; index < batches.size(); ++index) {
    const auto &batch = batches.at(index);
    require(batch.is_object() && batch.contains("style_id") &&
                batch.at("style_id").is_string(),
            "each batch requires a string style_id");
    const auto style = batch.at("style_id").get<std::string>();
    require(style == style_ids.at(index), "batch style_id order does not match configuration");
    require(seen_styles.insert(style).second, "duplicate style_id");
    require(batch.contains("items") && batch.at("items").is_array() &&
                !batch.at("items").empty(),
            "each batch requires non-empty items");
    for (const auto &item : batch.at("items")) {
      require(item.is_string(), "batch item must be a string");
      const auto value = item.get<std::string>();
      require(!value.empty() && contains_chinese(value),
              "every batch item must contain Chinese text");
      character_count += decode_utf8(value).size();
    }
  }
  require(character_count <= max_chinese_chars, "payload exceeds selected character budget");
  return payload;
}

nlohmann::json parse_and_validate_config(const std::string &text) {
  const auto config = nlohmann::json::parse(text);
  require(config.value("schema_version", 0) == 1, "unsupported official config schema");
  require(config.value("cadence", "") == "official-1hz", "official cadence must be 1Hz");
  require(config.at("budgets") == nlohmann::json::array({225, 350, 500}),
          "budgets must remain 225/350/500");
  require(config.at("timeouts_seconds") == nlohmann::json::array({12, 16, 20}),
          "timeouts must remain 12/16/20 seconds");
  require(config.at("style_ids") ==
              nlohmann::json::array({"style-1", "style-2", "style-3"}),
          "style_ids must contain exactly the three frozen styles");
  require(config.at("runtime").value("use_tts", true) == false,
          "TTS must remain disabled");
  require(config.at("runtime").value("duplex_mode", false),
          "duplex mode must remain enabled");
  const auto prompt = config.value("contract_prompt_template", "");
  require(!prompt.empty() && prompt.find("{{MAX_CHINESE_CHARS}}") != std::string::npos,
          "contract prompt template must include the character-budget placeholder");
  return config;
}

nlohmann::json build_init_request(const std::string &model_dir,
                                  const std::string &output_dir,
                                  const std::string &contract_prompt) {
  require(!model_dir.empty(), "official init requires model_dir");
  require(!output_dir.empty(), "official init requires output_dir");
  require(!contract_prompt.empty(), "official init requires the V2 contract prompt");
  require(contract_prompt.find("{{MAX_CHINESE_CHARS}}") == std::string::npos,
          "official init contract prompt has an unresolved budget placeholder");
  return {
      {"media_type", 2},
      {"use_tts", false},
      {"duplex_mode", true},
      {"model_dir", model_dir},
      {"output_dir", output_dir},
      {"voice_clone_prompt", "<|im_start|>system\n" + contract_prompt +
                                 "\n<|audio_start|>"},
      {"assistant_prompt", "<|audio_end|><|im_end|>\n"},
  };
}

nlohmann::json build_init_prefill_request() {
  return {
      {"audio_path_prefix", ""},
      {"img_path_prefix", ""},
      {"cnt", 0},
  };
}

void validate_upstream_lock(const std::string &text) {
  const auto lock = nlohmann::json::parse(text);
  require(lock.value("schema_version", 0) == 1, "unsupported upstream lock schema");
  require(lock.at("components").is_array() && lock.at("components").size() == 2,
          "upstream lock must contain exactly two source components");
  const auto &runtime = lock.at("components").at(0);
  require(runtime.at("repo") == "https://github.com/tc-mb/llama.cpp-omni.git" &&
              runtime.at("ref") == "master" &&
              runtime.at("commit") == "09f5c3f1b484759f17b06fc63574f749c89c8761" &&
              runtime.at("license") == "MIT" &&
              runtime.at("cmake_target") == "llama-omni-server" &&
              runtime.at("binary") == "llama-omni-server",
          "llama.cpp-omni lock changed");
  const auto &demo = lock.at("components").at(1);
  require(demo.at("repo") == "https://github.com/OpenBMB/MiniCPM-o-Demo.git" &&
              demo.at("ref") == "main" &&
              demo.at("commit") == "d0a002093615b7f1d4d0f87a03fc01cb39bef3f6" &&
              demo.at("runtime_refspec_default") == "master" &&
              demo.at("runtime_checkout_default") == "origin/master" &&
              demo.at("redistributed") == false,
          "MiniCPM-o-Demo Comni lock changed");
  require(lock.at("model").value("external", false), "models must stay external");
  require(lock.at("model").value("active_profile", "") == "duplex-no-tts" &&
              lock.at("model").value("layout_compatibility", "") == "DIRECT" &&
              lock.at("model").at("missing_required_files").empty(),
          "active no-TTS model layout is not directly compatible");
  require(lock.at("model").at("files").size() == 3,
          "model lock must contain exactly the frozen three-file set");
  for (const auto &file : lock.at("model").at("files")) {
    require(is_sha256(file.at("sha256").get<std::string>()), "invalid model SHA-256");
  }
}

nlohmann::json build_dry_run_plan(const std::string &manifest_text) {
  const auto manifest = nlohmann::json::parse(manifest_text);
  require(manifest.value("input_id", "") == "O-IN-07", "manifest must be O-IN-07");
  require(manifest.value("slice_duration_ms", 0) == 1000,
          "O-IN-07 official route requires one-second slices");
  require(manifest.value("deidentified", false) && manifest.value("rights_confirmed", false),
          "O-IN-07 rights/deidentification gate failed");
  require(manifest.at("style_ids") ==
              nlohmann::json::array({"style-1", "style-2", "style-3"}),
          "O-IN-07 styles changed");
  require(manifest.at("chunks").is_array() && manifest.at("chunks").size() == 33,
          "O-IN-07 official route requires 33 chunks");

  nlohmann::json steps = nlohmann::json::array();
  for (std::size_t index = 0; index < manifest.at("chunks").size(); ++index) {
    const auto &chunk = manifest.at("chunks").at(index);
    const auto sequence = static_cast<int>(index + 1);
    require(chunk.value("sequence", 0) == sequence &&
                chunk.value("offset_ms", -1) == static_cast<int>(index * 1000) &&
                chunk.value("duration_ms", 0) == 1000,
            "O-IN-07 timeline is not deterministic official-1hz");
    require(!chunk.value("audio", "").empty() && !chunk.value("image", "").empty() &&
                is_sha256(chunk.value("audio_sha256", "")) &&
                is_sha256(chunk.value("image_sha256", "")),
            "O-IN-07 chunk path/hash is incomplete");
    steps.push_back({
        {"cnt", sequence},
        {"offset_ms", chunk.at("offset_ms")},
        {"audio", chunk.at("audio")},
        {"image", chunk.at("image")},
    });
  }
  return {
      {"input_id", "O-IN-07"},
      {"cadence", "official-1hz"},
      {"steps", std::move(steps)},
  };
}

}  // namespace aijarvis::official_o
