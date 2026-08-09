#pragma once

#include "o_reference_harness/core.hpp"

#include <filesystem>
#include <memory>
#include <optional>

namespace o_reference_harness {

struct LockedModelConfig {
  std::filesystem::path model_root;
  std::filesystem::path output_root;
};

class LockedRuntime {
 public:
  explicit LockedRuntime(const LockedModelConfig& config);
  ~LockedRuntime();

  LockedRuntime(const LockedRuntime&) = delete;
  LockedRuntime& operator=(const LockedRuntime&) = delete;
  LockedRuntime(LockedRuntime&&) noexcept;
  LockedRuntime& operator=(LockedRuntime&&) noexcept;

  void begin(const Profile& profile, const std::filesystem::path& debug_directory);
  std::int64_t push(const InputChunk& input, int generation_id);
  std::optional<RawRuntimeResult> wait(int timeout_ms);
  void end();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace o_reference_harness
