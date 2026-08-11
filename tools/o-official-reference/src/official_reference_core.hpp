#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <nlohmann/json.hpp>

namespace aijarvis::official_o {

enum class TriggerSource {
  System,
  Autonomous,
};

struct PendingTrigger {
  TriggerSource source;
  std::uint64_t sequence;
  std::string input_ref;
};

enum class TriggerOfferDecision {
  Stored,
  Replaced,
  Ignored,
};

enum class TimelineProgress {
  Continue,
  Complete,
  MissingSpeak,
};

TimelineProgress evaluate_timeline_progress(std::size_t sent,
                                            std::size_t terminal,
                                            std::size_t expected,
                                            bool saw_speak);
bool is_terminal_backend_event(std::string_view type, std::string_view kind);

class PendingTriggerSlot {
 public:
  TriggerOfferDecision offer(PendingTrigger trigger);
  std::optional<PendingTrigger> take();
  void clear();
  std::size_t depth() const;

 private:
  std::optional<PendingTrigger> pending_;
};

class RunGenerationFence {
 public:
  explicit RunGenerationFence(std::string initial_session_id);

  std::uint64_t generation() const;
  bool paused() const;
  std::uint64_t pause_and_invalidate(PendingTriggerSlot &pending_slot);
  void resume(std::string new_session_id);
  bool accepts(std::uint64_t generation, std::string_view session_id) const;

 private:
  std::uint64_t generation_ = 1;
  bool paused_ = false;
  std::string active_session_id_;
  std::string paused_session_id_;
};

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
  void clear();
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
