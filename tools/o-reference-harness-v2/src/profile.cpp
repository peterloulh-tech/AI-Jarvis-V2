#include "o_reference_harness/core.hpp"

#include <nlohmann/json.hpp>

#include <fstream>
#include <stdexcept>

namespace o_reference_harness {

Profile load_profile(const std::filesystem::path& path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) throw std::runtime_error("cannot open profile: " + path.string());
  nlohmann::json source;
  stream >> source;
  Profile profile;
  profile.id = source.at("id").get<std::string>();
  profile.prompt_source = source.at("prompt_source").get<std::string>();
  profile.system_prompt = source.at("system_prompt").get<std::string>();
  profile.assistant_prompt = source.at("assistant_prompt").get<std::string>();
  profile.validate_v2_contract = source.at("validate_v2_contract").get<bool>();
  profile.style_ids = source.value("style_ids", std::vector<std::string>{});
  if (profile.id.empty() || profile.system_prompt.empty() ||
      (profile.validate_v2_contract && profile.style_ids.size() != 3)) {
    throw std::runtime_error("invalid profile contract: " + path.string());
  }
  return profile;
}

}  // namespace o_reference_harness
