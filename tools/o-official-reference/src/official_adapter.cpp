#include "official_reference_core.hpp"

#include <cpp-httplib/httplib.h>

#include <chrono>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

using Clock = std::chrono::steady_clock;

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

httplib::Client make_client(const std::map<std::string, std::string> &options) {
  httplib::Client client(required(options, "base-url"));
  const auto timeout = options.count("timeout-seconds")
                           ? std::stoi(options.at("timeout-seconds"))
                           : 20;
  client.set_connection_timeout(5, 0);
  client.set_read_timeout(timeout, 0);
  client.set_write_timeout(timeout, 0);
  return client;
}

void require_success(const httplib::Result &response, const std::string &operation) {
  if (!response) throw std::runtime_error(operation + " transport failed");
  if (response->status < 200 || response->status >= 300) {
    throw std::runtime_error(operation + " HTTP " + std::to_string(response->status) +
                             ": " + response->body);
  }
}

nlohmann::json post_json(httplib::Client &client, const std::string &endpoint,
                         const nlohmann::json &body) {
  const auto response = client.Post(endpoint, body.dump(), "application/json");
  require_success(response, endpoint);
  if (response->body.empty()) return nlohmann::json::object();
  return nlohmann::json::parse(response->body);
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

}  // namespace

int main(int argc, char **argv) {
  try {
    if (argc < 2) throw std::runtime_error("command required: health|init|step|validate|dry-run");
    const std::string command = argv[1];
    const auto options = parse_options(argc, argv, 2);

    if (command == "validate") {
      const auto parsed = aijarvis::official_o::validate_contract(
          read_file(required(options, "input")),
          split_styles(required(options, "styles")),
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

    auto client = make_client(options);
    if (command == "health") {
      const auto response = client.Get("/health");
      require_success(response, "health");
      std::cout << response->body << '\n';
      return 0;
    }
    if (command == "init") {
      const auto response = post_json(
          client, "/v1/stream/omni_init",
          aijarvis::official_o::build_init_request(
              required(options, "model-dir"), required(options, "output-dir"),
              read_file(required(options, "prompt-file"))));
      const auto prefill = post_json(
          client, "/v1/stream/prefill",
          aijarvis::official_o::build_init_prefill_request());
      std::cout << nlohmann::json({
          {"omni_init", response},
          {"system_prefill", prefill},
      }).dump() << '\n';
      return 0;
    }
    if (command != "step") throw std::runtime_error("unknown command: " + command);

    post_json(client, "/v1/stream/prefill", {
        {"audio_path_prefix", required(options, "audio")},
        {"img_path_prefix", required(options, "image")},
        {"cnt", std::stoi(required(options, "cnt"))},
    });

    aijarvis::official_o::SseCollector collector;
    const auto started = Clock::now();
    const nlohmann::json decode_body = {{"stream", true}};
    const auto decode = client.Post(
        "/v1/stream/decode", httplib::Headers{}, decode_body.dump(), "application/json",
        [&](const char *data, std::size_t length) {
          const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                   Clock::now() - started)
                                   .count();
          collector.feed(std::string_view(data, length), elapsed);
          return true;
        });
    require_success(decode, "decode");
    const auto completion = std::chrono::duration_cast<std::chrono::milliseconds>(
                                Clock::now() - started)
                                .count();
    collector.finish(completion);
    const auto &result = collector.result();
    std::cout << nlohmann::json({
        {"raw_sse", result.raw_sse},
        {"content", result.content},
        {"is_listen", result.saw_listen},
        {"stop", result.saw_stop},
        {"done", result.saw_done},
        {"first_fragment_latency_ms", result.first_fragment_latency_ms},
        {"completion_latency_ms", result.completion_latency_ms},
    }).dump() << '\n';
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "official adapter: FAIL: " << error.what() << '\n';
    return 1;
  }
}
