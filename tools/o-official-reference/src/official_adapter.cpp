#include "official_reference_core.hpp"

#include <cpp-httplib/httplib.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;
namespace fs = std::filesystem;

std::map<std::string, std::string> parse_options(int argc, char **argv, int start) {
  std::map<std::string, std::string> options;
  for (int index = start; index < argc; index += 2) {
    if (index + 1 >= argc || std::string(argv[index]).rfind("--", 0) != 0) {
      throw std::runtime_error("options must use --name value pairs");
    }
    options.emplace(std::string(argv[index]).substr(2), argv[index + 1]);
  }
  return options;
}

const std::string &required(const std::map<std::string, std::string> &options,
                            const std::string &name) {
  const auto found = options.find(name);
  if (found == options.end() || found->second.empty()) {
    throw std::runtime_error("missing --" + name);
  }
  return found->second;
}

std::string read_file(const std::string &path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("cannot read " + path);
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

httplib::Client make_http_client(const std::map<std::string, std::string> &options,
                                 int timeout_seconds) {
  httplib::Client client(required(options, "base-url"));
  client.set_connection_timeout(5, 0);
  client.set_read_timeout(timeout_seconds, 0);
  client.set_write_timeout(timeout_seconds, 0);
  return client;
}

void require_success(const httplib::Result &response, const std::string &operation) {
  if (!response) throw std::runtime_error(operation + " transport failed");
  if (response->status < 200 || response->status >= 300) {
    throw std::runtime_error(operation + " HTTP " + std::to_string(response->status) +
                             ": " + response->body);
  }
}

std::vector<std::string> split_styles(const std::string &value) {
  std::vector<std::string> styles;
  std::size_t begin = 0;
  for (;;) {
    const auto comma = value.find(',', begin);
    styles.push_back(value.substr(begin, comma == std::string::npos ? comma : comma - begin));
    if (comma == std::string::npos) return styles;
    begin = comma + 1;
  }
}

std::string websocket_url(const std::string &base_url) {
  std::string url = base_url;
  if (url.rfind("http://", 0) == 0) {
    url.replace(0, 7, "ws://");
  } else if (url.rfind("https://", 0) == 0) {
    url.replace(0, 8, "wss://");
  } else {
    throw std::runtime_error("--base-url must use http:// or https://");
  }
  while (!url.empty() && url.back() == '/') url.pop_back();
  return url + "/backend";
}

struct BackendSession {
  std::unique_ptr<httplib::ws::WebSocketClient> ws;
  std::string session_id;
  nlohmann::json created_event;
};

BackendSession open_session(const std::string &base_url, const std::string &prompt,
                            int timeout_seconds) {
  BackendSession session;
  session.ws = std::make_unique<httplib::ws::WebSocketClient>(websocket_url(base_url));
  session.ws->set_connection_timeout(5, 0);
  session.ws->set_read_timeout(timeout_seconds, 0);
  session.ws->set_write_timeout(timeout_seconds, 0);
  if (!session.ws->connect()) throw std::runtime_error("official /backend connect failed");
  if (!session.ws->send(aijarvis::official_o::build_session_init_request(prompt).dump())) {
    throw std::runtime_error("official session.init send failed");
  }

  std::string raw;
  if (session.ws->read(raw) != httplib::ws::ReadResult::Text) {
    throw std::runtime_error("official session.init did not return session.created");
  }
  session.created_event = nlohmann::json::parse(raw);
  if (session.created_event.value("type", "") != "session.created" ||
      !session.created_event.contains("session_id")) {
    throw std::runtime_error("official session.init returned unexpected event: " + raw);
  }
  session.session_id = session.created_event.at("session_id").get<std::string>();
  return session;
}

nlohmann::json close_session(const std::map<std::string, std::string> &options,
                             const std::string &session_id, int timeout_seconds) {
  auto client = make_http_client(options, timeout_seconds);
  const auto endpoint = "/sessions/" + session_id + "/close";
  const auto response = client.Post(endpoint, R"({"reason":"client_closed"})",
                                    "application/json");
  require_success(response, endpoint);
  return nlohmann::json::parse(response->body);
}

nlohmann::json run_backend(const std::map<std::string, std::string> &options) {
  const auto prompt = read_file(required(options, "prompt-file"));
  const auto manifest_text = read_file(required(options, "manifest"));
  const auto plan = aijarvis::official_o::build_dry_run_plan(manifest_text);
  const auto input_root = fs::path(required(options, "input-root"));
  const auto styles = split_styles(required(options, "styles"));
  const auto budget = static_cast<std::size_t>(std::stoul(required(options, "budget")));
  const auto init_timeout = std::stoi(required(options, "init-timeout-seconds"));
  const auto hard_timeout = std::stoi(required(options, "timeout-seconds"));
  if (init_timeout <= 0 || hard_timeout <= 0) throw std::runtime_error("timeouts must be positive");

  std::vector<nlohmann::json> requests;
  requests.reserve(plan.at("steps").size());
  for (const auto &step : plan.at("steps")) {
    requests.push_back(aijarvis::official_o::build_input_append_request(
        (input_root / step.at("audio").get<std::string>()).string(),
        (input_root / step.at("image").get<std::string>()).string()));
  }

  // The first official session performs the expensive model initialization.
  // Closing it through the Comni client primitive lets llama-omni-server run
  // omni_prepare_for_reuse; the real evidence session then starts on the same
  // loaded model with a clean official context and the generation timeout.
  auto warmup = open_session(required(options, "base-url"), prompt, init_timeout);
  const auto warmup_session_id = warmup.session_id;
  aijarvis::official_o::PendingTriggerSlot pending_trigger;
  aijarvis::official_o::RunGenerationFence generation_fence(warmup.session_id);
  const auto warmup_generation = generation_fence.generation();
  const auto active_generation = generation_fence.pause_and_invalidate(pending_trigger);
  const auto warmup_close = close_session(options, warmup.session_id, init_timeout);
  warmup.ws->close();

  auto session = open_session(required(options, "base-url"), prompt, hard_timeout);
  generation_fence.resume(session.session_id);
  const auto timeline_start = Clock::now();
  std::atomic<bool> stop{false};
  std::atomic<std::size_t> sent_count{0};
  std::mutex producer_mutex;
  std::condition_variable producer_cv;
  std::string producer_error;

  std::thread producer([&] {
    try {
      for (std::size_t index = 0; index < requests.size(); ++index) {
        const auto due = timeline_start + std::chrono::milliseconds(
            plan.at("steps").at(index).at("offset_ms").get<int>());
        {
          std::unique_lock<std::mutex> lock(producer_mutex);
          if (producer_cv.wait_until(lock, due, [&] { return stop.load(); })) return;
        }
        if (!generation_fence.accepts(active_generation, session.session_id)) {
          throw std::runtime_error("official input rejected by paused or stale run generation");
        }
        if (!session.ws->send(requests.at(index).dump())) {
          throw std::runtime_error("official input.append send failed at sequence " +
                                   std::to_string(index + 1));
        }
        sent_count.store(index + 1);
      }
    } catch (const std::exception &error) {
      std::lock_guard<std::mutex> lock(producer_mutex);
      producer_error = error.what();
      stop.store(true);
      producer_cv.notify_all();
    }
  });

  aijarvis::official_o::BackendEventCollector collector;
  nlohmann::json raw_events = nlohmann::json::array();
  std::size_t terminal_count = 0;
  try {
    while (!stop.load()) {
      std::string raw;
      if (session.ws->read(raw) != httplib::ws::ReadResult::Text) {
        throw std::runtime_error("official /backend read failed or exceeded hard timeout");
      }
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                               Clock::now() - timeline_start)
                               .count();
      const auto event = nlohmann::json::parse(raw);
      if (!generation_fence.accepts(active_generation,
                                    event.value("session_id", ""))) {
        throw std::runtime_error("official event rejected from stale generation or session");
      }
      collector.feed(raw, elapsed);
      raw_events.push_back({{"elapsed_ms", elapsed}, {"event", event}});

      const auto type = event.value("type", "");
      if (type == "response.done" ||
          (type == "response.output.delta" && event.value("kind", "") == "listen")) {
        ++terminal_count;
      }
      if (collector.result().saw_done && !collector.result().content.empty()) {
        break;
      }
      if (sent_count.load() == requests.size() && terminal_count >= requests.size()) {
        throw std::runtime_error("official O-IN-07 completed without a SPEAK text response");
      }
    }
  } catch (...) {
    stop.store(true);
    producer_cv.notify_all();
    if (producer.joinable()) producer.join();
    if (!generation_fence.paused()) {
      generation_fence.pause_and_invalidate(pending_trigger);
    }
    collector.clear();
    try {
      close_session(options, session.session_id, hard_timeout);
    } catch (...) {
    }
    session.ws->close();
    throw;
  }

  stop.store(true);
  producer_cv.notify_all();
  if (producer.joinable()) producer.join();
  {
    std::lock_guard<std::mutex> lock(producer_mutex);
    if (!producer_error.empty()) throw std::runtime_error(producer_error);
  }

  const auto collected = collector.result();
  const auto parsed =
      aijarvis::official_o::validate_contract(collected.content, styles, budget);
  const auto post_close_generation =
      generation_fence.pause_and_invalidate(pending_trigger);
  collector.clear();
  const auto active_close = close_session(options, session.session_id, hard_timeout);
  session.ws->close();

  return {
      {"transport", "/backend"},
      {"warmup_session_id", warmup_session_id},
      {"warmup_close", warmup_close},
      {"pause_resume_contract", {
          {"paused_session_id", warmup_session_id},
          {"paused_generation", warmup_generation},
          {"resumed_session_id", session.session_id},
          {"resumed_generation", active_generation},
          {"new_session", session.session_id != warmup_session_id},
      }},
      {"session_id", session.session_id},
      {"session_created", session.created_event},
      {"session_close", active_close},
      {"sent_inputs", sent_count.load()},
      {"terminal_responses", terminal_count},
      {"content", collected.content},
      {"saw_listen", collected.saw_listen},
      {"saw_done", collected.saw_done},
      {"first_fragment_latency_ms", collected.first_fragment_latency_ms},
      {"completion_latency_ms", collected.completion_latency_ms},
      {"post_close_generation", post_close_generation},
      {"pending_trigger_depth_after_pause", pending_trigger.depth()},
      {"parsed", parsed},
      {"events", raw_events},
  };
}

}  // namespace

int main(int argc, char **argv) {
  try {
    if (argc < 2) throw std::runtime_error("command required: health|run|validate|dry-run");
    const std::string command = argv[1];
    const auto options = parse_options(argc, argv, 2);

    if (command == "validate") {
      const auto parsed = aijarvis::official_o::validate_contract(
          read_file(required(options, "input")), split_styles(required(options, "styles")),
          static_cast<std::size_t>(std::stoul(required(options, "budget"))));
      std::cout << parsed.dump(2) << '\n';
      return 0;
    }
    if (command == "dry-run") {
      std::cout << aijarvis::official_o::build_dry_run_plan(
                       read_file(required(options, "manifest")))
                       .dump(2)
                << '\n';
      return 0;
    }
    if (command == "run") {
      std::cout << run_backend(options).dump() << '\n';
      return 0;
    }
    if (command != "health") throw std::runtime_error("unknown command: " + command);

    const auto timeout = options.count("timeout-seconds")
                             ? std::stoi(options.at("timeout-seconds"))
                             : 20;
    auto client = make_http_client(options, timeout);
    const auto response = client.Get("/health");
    require_success(response, "health");
    std::cout << response->body << '\n';
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "official adapter: FAIL: " << error.what() << '\n';
    return 1;
  }
}
