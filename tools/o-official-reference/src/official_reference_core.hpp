#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

namespace aijarvis::official_o {

struct BackendResult {
  std::string session_id;
  std::string content;
  bool saw_listen = false;
  bool saw_done = false;
  std::int64_t first_fragment_latency_ms = -1;
  std::int64_t completion_latency_ms = -1;
};

class BackendEventCollector {
 public:
  void feed(std::string_view event_json, std::int64_t elapsed_ms);
  const BackendResult &result() const;

 private:
  BackendResult result_;
};

nlohmann::json validate_contract(const std::string &text,
                                 const std::vector<std::string> &style_ids,
                                 std::size_t max_chinese_chars);
nlohmann::json parse_and_validate_config(const std::string &text);
nlohmann::json build_session_init_request(const std::string &contract_prompt);
nlohmann::json build_input_append_request(const std::string &audio_path,
                                          const std::string &image_path);
void validate_upstream_lock(const std::string &text);
nlohmann::json build_dry_run_plan(const std::string &manifest_text);

}  // namespace aijarvis::official_o
