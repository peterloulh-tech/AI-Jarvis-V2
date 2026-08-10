#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

namespace aijarvis::official_o {

struct SseResult {
  std::string raw_sse;
  std::string content;
  bool saw_listen = false;
  bool saw_stop = false;
  bool saw_done = false;
  std::int64_t first_fragment_latency_ms = -1;
  std::int64_t completion_latency_ms = -1;
};

class SseCollector {
 public:
  void feed(std::string_view bytes, std::int64_t elapsed_ms);
  void finish(std::int64_t elapsed_ms);
  const SseResult &result() const;

 private:
  void consume_line(std::string line, std::int64_t elapsed_ms);

  std::string pending_;
  SseResult result_;
};

nlohmann::json validate_contract(const std::string &text,
                                 const std::vector<std::string> &style_ids,
                                 std::size_t max_chinese_chars);
nlohmann::json parse_and_validate_config(const std::string &text);
nlohmann::json build_init_request(const std::string &model_dir,
                                  const std::string &output_dir,
                                  const std::string &contract_prompt);
void validate_upstream_lock(const std::string &text);
nlohmann::json build_dry_run_plan(const std::string &manifest_text);

}  // namespace aijarvis::official_o
