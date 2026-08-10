#include "official_reference_core.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <fstream>
#include <iterator>
#include <set>
#include <sstream>
#include <stdexcept>

#include "common/base64.hpp"

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

std::string read_binary_file(const std::string &path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("cannot read " + path);
  return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}

std::uint16_t read_le16(const std::string &bytes, std::size_t offset) {
  require(offset + 2 <= bytes.size(), "truncated WAV uint16");
  return static_cast<std::uint16_t>(static_cast<unsigned char>(bytes[offset])) |
         static_cast<std::uint16_t>(static_cast<unsigned char>(bytes[offset + 1])) << 8;
}

std::uint32_t read_le32(const std::string &bytes, std::size_t offset) {
  require(offset + 4 <= bytes.size(), "truncated WAV uint32");
  return static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[offset])) |
         static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[offset + 1])) << 8 |
         static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[offset + 2])) << 16 |
         static_cast<std::uint32_t>(static_cast<unsigned char>(bytes[offset + 3])) << 24;
}

std::string wav_pcm16_to_float32_bytes(const std::string &wav) {
  require(wav.size() >= 12 && wav.compare(0, 4, "RIFF") == 0 &&
              wav.compare(8, 4, "WAVE") == 0,
          "audio input must be a RIFF/WAVE file");

  bool saw_format = false;
  std::size_t data_offset = 0;
  std::size_t data_size = 0;
  for (std::size_t offset = 12; offset + 8 <= wav.size();) {
    const auto chunk_id = wav.substr(offset, 4);
    const auto chunk_size = static_cast<std::size_t>(read_le32(wav, offset + 4));
    const auto chunk_data = offset + 8;
    require(chunk_data + chunk_size <= wav.size(), "truncated WAV chunk");
    if (chunk_id == "fmt ") {
      require(chunk_size >= 16 && read_le16(wav, chunk_data) == 1,
              "audio input must use integer PCM");
      require(read_le16(wav, chunk_data + 2) == 1,
              "audio input must be mono");
      require(read_le32(wav, chunk_data + 4) == 16000,
              "audio input must be 16 kHz");
      require(read_le16(wav, chunk_data + 14) == 16,
              "audio input must be 16-bit PCM");
      saw_format = true;
    } else if (chunk_id == "data") {
      data_offset = chunk_data;
      data_size = chunk_size;
    }
    offset = chunk_data + chunk_size + (chunk_size & 1U);
  }
  require(saw_format && data_offset != 0 && data_size != 0 && data_size % 2 == 0,
          "WAV format or data chunk is missing");

  std::string pcm;
  pcm.resize((data_size / 2) * sizeof(float));
  for (std::size_t index = 0; index < data_size / 2; ++index) {
    const auto raw = read_le16(wav, data_offset + index * 2);
    const auto sample = static_cast<std::int16_t>(raw);
    const float normalized = static_cast<float>(sample) / 32768.0F;
    std::memcpy(pcm.data() + index * sizeof(float), &normalized, sizeof(float));
  }
  return pcm;
}

}  // namespace

void BackendEventCollector::feed(std::string_view event_json, std::int64_t elapsed_ms) {
  const auto event = nlohmann::json::parse(event_json);
  require(event.is_object() && event.contains("type") && event.at("type").is_string(),
          "official backend event must contain a string type");
  const auto type = event.at("type").get<std::string>();
  if (type == "session.created") {
    require(event.contains("session_id") && event.at("session_id").is_string(),
            "session.created must contain session_id");
    result_.session_id = event.at("session_id").get<std::string>();
    return;
  }
  if (type == "response.output.delta") {
    const auto kind = event.value("kind", "");
    if (kind == "listen") {
      result_.saw_listen = true;
      result_.completion_latency_ms = elapsed_ms;
      return;
    }
    if (kind == "text") {
      require(event.contains("text") && event.at("text").is_string(),
              "text delta must contain text");
      const auto fragment = event.at("text").get<std::string>();
      if (!fragment.empty()) {
        if (result_.first_fragment_latency_ms < 0) {
          result_.first_fragment_latency_ms = elapsed_ms;
        }
        result_.content += fragment;
      }
    }
    return;
  }
  if (type == "response.done") {
    if (event.contains("text") && event.at("text").is_string()) {
      const auto complete = event.at("text").get<std::string>();
      if (!complete.empty()) result_.content = complete;
    }
    result_.saw_done = true;
    result_.completion_latency_ms = elapsed_ms;
  }
}

const BackendResult &BackendEventCollector::result() const { return result_; }

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
  require(config.value("transport", "") == "/backend",
          "official transport must use /backend");
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
  const auto prompt = config.value("contract_prompt_template", "");
  require(!prompt.empty() && prompt.find("{{MAX_CHINESE_CHARS}}") != std::string::npos,
          "contract prompt template must include the character-budget placeholder");
  return config;
}

nlohmann::json build_session_init_request(const std::string &contract_prompt) {
  require(!contract_prompt.empty(), "official session.init requires the V2 contract prompt");
  require(contract_prompt.find("{{MAX_CHINESE_CHARS}}") == std::string::npos,
          "official session.init contract prompt has an unresolved budget placeholder");
  return {
      {"type", "session.init"},
      {"payload", {
          {"mode", "full_duplex"},
          {"use_tts", false},
          {"system_prompt", "<|audio_end|>" + contract_prompt + "<|im_end|>\n"},
      }},
  };
}

nlohmann::json build_input_append_request(const std::string &audio_path,
                                          const std::string &image_path) {
  require(!audio_path.empty() && !image_path.empty(),
          "official input.append requires audio and image paths");
  const auto float_pcm = wav_pcm16_to_float32_bytes(read_binary_file(audio_path));
  const auto jpeg = read_binary_file(image_path);
  require(jpeg.size() >= 2 && static_cast<unsigned char>(jpeg[0]) == 0xFF &&
              static_cast<unsigned char>(jpeg[1]) == 0xD8,
          "image input must be JPEG");
  return {
      {"type", "input.append"},
      {"input", {
          {"audio_base64", base64::encode(float_pcm)},
          {"video_frames", nlohmann::json::array({base64::encode(jpeg)})},
          {"max_slice_nums", -1},
      }},
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
