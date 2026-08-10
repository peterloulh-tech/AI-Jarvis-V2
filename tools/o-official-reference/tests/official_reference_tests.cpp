#include "official_reference_core.hpp"

#include <fstream>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {

std::string read_file(const std::string &path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("cannot read " + path);
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

void require(bool condition, const std::string &message) {
  if (!condition) throw std::runtime_error(message);
}

template <typename F>
void require_rejected(F operation, const std::string &message) {
  try {
    operation();
  } catch (const std::exception &) {
    return;
  }
  throw std::runtime_error(message);
}

}  // namespace

int main(int argc, char **argv) {
  try {
    require(argc == 4, "expected config, lock, and O-IN-07 manifest paths");

    aijarvis::official_o::BackendEventCollector collector;
    collector.feed(R"({"type":"session.created","session_id":"official-session","mode":"full_duplex"})", 3);
    collector.feed(R"({"type":"response.output.delta","kind":"text","session_id":"official-session","response_id":"r1","text":"第一批"})", 17);
    collector.feed(R"({"type":"response.output.delta","kind":"text","session_id":"official-session","response_id":"r1","text":"第二批"})", 29);
    collector.feed(R"({"type":"response.done","session_id":"official-session","response_id":"r1","text":"第一批第二批","reason":"turn_end"})", 31);
    const auto result = collector.result();
    require(result.session_id == "official-session", "backend session id changed");
    require(result.content == "第一批第二批", "backend text delta order changed");
    require(result.saw_done, "backend response.done boundary is missing");
    require(result.first_fragment_latency_ms == 17,
            "first-fragment latency must use the first content event");
    require(result.completion_latency_ms == 31,
            "completion latency must end at official response.done");

    aijarvis::official_o::BackendEventCollector listen_collector;
    listen_collector.feed(R"({"type":"session.created","session_id":"listen-session","mode":"full_duplex"})", 1);
    listen_collector.feed(R"({"type":"response.output.delta","kind":"listen","session_id":"listen-session","response_id":"r1"})", 9);
    require(listen_collector.result().saw_listen,
            "backend LISTEN boundary is missing");

    const auto valid_contract = R"({"batches":[{"style_id":"style-1","items":["稳住，这波能翻。"]},{"style_id":"style-2","items":["漂亮！继续压节奏。"]},{"style_id":"style-3","items":["这波操作真的细。"]}]})";
    const auto parsed = aijarvis::official_o::validate_contract(
        valid_contract, {"style-1", "style-2", "style-3"}, 225);
    require(parsed.at("batches").size() == 3, "contract must contain exactly three batches");

    require_rejected([&] {
      aijarvis::official_o::validate_contract(
          R"({"batches":[{"style_id":"style-1","items":["中文"]},{"style_id":"style-1","items":["中文"]},{"style_id":"style-3","items":["中文"]}]})",
          {"style-1", "style-2", "style-3"}, 225);
    }, "duplicate style_id was accepted");
    require_rejected([&] {
      aijarvis::official_o::validate_contract(
          R"({"batches":[{"style_id":"style-1","items":["English only"]},{"style_id":"style-2","items":["中文"]},{"style_id":"style-3","items":["中文"]}]})",
          {"style-1", "style-2", "style-3"}, 225);
    }, "non-Chinese item was accepted");

    const auto config = aijarvis::official_o::parse_and_validate_config(read_file(argv[1]));
    require(config.at("budgets") == nlohmann::json::array({225, 350, 500}),
            "budget entry changed");
    require(config.at("timeouts_seconds") == nlohmann::json::array({12, 16, 20}),
            "timeout entry changed");
    require(config.at("server").at("health_timeout_seconds") == 300,
            "official model initialization timeout changed");
    auto prompt_template = config.at("contract_prompt_template").get<std::string>();
    require(prompt_template.find("{{MAX_CHINESE_CHARS}}") != std::string::npos,
            "contract prompt must carry the selected character budget");
    prompt_template.replace(prompt_template.find("{{MAX_CHINESE_CHARS}}"),
                            std::string("{{MAX_CHINESE_CHARS}}").size(), "350");
    const auto init_request = aijarvis::official_o::build_session_init_request(prompt_template);
    require(init_request.at("type") == "session.init" &&
                init_request.at("payload").at("mode") == "full_duplex" &&
                init_request.at("payload").at("use_tts") == false,
            "official backend init must keep full duplex enabled and TTS disabled");
    const auto backend_prompt = init_request.at("payload").at("system_prompt").get<std::string>();
    require(backend_prompt.rfind("<|audio_end|>", 0) == 0 &&
                backend_prompt.find(prompt_template) != std::string::npos &&
                backend_prompt.size() >= std::string("<|im_end|>\n").size() &&
                backend_prompt.compare(backend_prompt.size() - std::string("<|im_end|>\n").size(),
                                       std::string("<|im_end|>\n").size(), "<|im_end|>\n") == 0,
            "V2 contract prompt was not aligned to the official duplex suffix slot");

    aijarvis::official_o::validate_upstream_lock(read_file(argv[2]));
    const auto plan = aijarvis::official_o::build_dry_run_plan(read_file(argv[3]));
    require(plan.at("input_id") == "O-IN-07", "dry-run input changed");
    require(plan.at("cadence") == "official-1hz", "official cadence changed");
    require(plan.at("steps").size() == 33, "O-IN-07 must have 33 one-second steps");
    require(plan.at("steps").front().at("cnt") == 1 &&
                plan.at("steps").back().at("cnt") == 33,
            "official prefill counters must run from 1 through 33");

    const auto manifest_path = std::filesystem::path(argv[3]);
    const auto fixture_root = manifest_path.parent_path();
    const auto manifest = nlohmann::json::parse(read_file(argv[3]));
    const auto &first_chunk = manifest.at("chunks").front();
    const auto input_request = aijarvis::official_o::build_input_append_request(
        (fixture_root / first_chunk.at("audio").get<std::string>()).string(),
        (fixture_root / first_chunk.at("image").get<std::string>()).string());
    require(input_request.at("type") == "input.append",
            "official backend input type changed");
    require(input_request.at("input").at("audio_base64").get<std::string>().size() > 80000,
            "PCM16 WAV was not converted to base64 float32 PCM");
    require(input_request.at("input").at("video_frames").size() == 1 &&
                input_request.at("input").at("video_frames").front().get<std::string>().size() > 1000,
            "JPEG frame was not encoded for official input.append");

    std::cout << "official reference tests: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "official reference tests: FAIL: " << error.what() << '\n';
    return 1;
  }
}
