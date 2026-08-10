#include "official_reference_core.hpp"

#include <fstream>
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
    require(argc == 5, "expected fixture, config, lock, and O-IN-07 manifest paths");

    aijarvis::official_o::SseCollector collector;
    const std::string sse = read_file(argv[1]);
    const auto split = sse.size() / 2;
    collector.feed(sse.substr(0, split), 17);
    collector.feed(sse.substr(split), 29);
    collector.finish(31);
    const auto result = collector.result();
    require(result.content == "第一批第二批", "SSE content order changed");
    require(result.saw_listen && result.saw_stop && result.saw_done,
            "SSE lifecycle markers are incomplete");
    require(result.first_fragment_latency_ms == 17,
            "first-fragment latency must use the first content event");
    require(result.completion_latency_ms == 29,
            "completion latency must end at official DONE");

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

    const auto config = aijarvis::official_o::parse_and_validate_config(read_file(argv[2]));
    require(config.at("budgets") == nlohmann::json::array({225, 350, 500}),
            "budget entry changed");
    require(config.at("timeouts_seconds") == nlohmann::json::array({12, 16, 20}),
            "timeout entry changed");
    require(config.at("server").at("health_timeout_seconds") == 300,
            "official model initialization timeout changed");
    auto prompt_template = config.at("contract_prompt_template").get<std::string>();
    require(prompt_template.find("{{MAX_CHINESE_CHARS}}") != std::string::npos,
            "contract prompt must carry the selected character budget");
    const auto init_request = aijarvis::official_o::build_init_request(
        "C:/external/model", "C:/evidence/runtime-output",
        prompt_template.replace(prompt_template.find("{{MAX_CHINESE_CHARS}}"),
                                std::string("{{MAX_CHINESE_CHARS}}").size(), "350"));
    require(init_request.at("use_tts") == false && init_request.at("duplex_mode") == true,
            "official init must keep duplex enabled and TTS disabled");
    const auto wrapped_prompt = init_request.at("voice_clone_prompt").get<std::string>();
    const std::string prompt_prefix = "<|im_start|>system\n";
    const std::string prompt_suffix = "\n<|audio_start|>";
    require(wrapped_prompt.rfind(prompt_prefix, 0) == 0 &&
                wrapped_prompt.size() >= prompt_suffix.size() &&
                wrapped_prompt.compare(wrapped_prompt.size() - prompt_suffix.size(),
                                       prompt_suffix.size(), prompt_suffix) == 0,
            "Comni voice prompt wrapper changed");
    require(init_request.at("voice_clone_prompt").get<std::string>().find("350") !=
                std::string::npos &&
                init_request.at("voice_clone_prompt").get<std::string>().find(
                    "style-1") != std::string::npos,
            "V2 contract prompt was not injected into official init");
    require(init_request.at("assistant_prompt") == "<|audio_end|><|im_end|>\n",
            "Comni duplex assistant prompt changed");

    aijarvis::official_o::validate_upstream_lock(read_file(argv[3]));
    const auto plan = aijarvis::official_o::build_dry_run_plan(read_file(argv[4]));
    require(plan.at("input_id") == "O-IN-07", "dry-run input changed");
    require(plan.at("cadence") == "official-1hz", "official cadence changed");
    require(plan.at("steps").size() == 33, "O-IN-07 must have 33 one-second steps");
    require(plan.at("steps").front().at("cnt") == 1 &&
                plan.at("steps").back().at("cnt") == 33,
            "official prefill counters must run from 1 through 33");

    std::cout << "official reference tests: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "official reference tests: FAIL: " << error.what() << '\n';
    return 1;
  }
}
