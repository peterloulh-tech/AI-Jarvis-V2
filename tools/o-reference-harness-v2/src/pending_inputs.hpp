#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <mutex>
#include <optional>

namespace o_reference_harness::detail {

struct PendingInput {
  int generation_id{};
  std::int64_t offset_ms{};
  std::int64_t duration_ms{};
};

class PendingInputs {
 public:
  void put(std::int64_t user_seq, PendingInput input) {
    std::lock_guard lock(mutex_);
    inputs_[user_seq] = input;
  }

  std::optional<PendingInput> take(std::int64_t user_seq) {
    std::lock_guard lock(mutex_);
    const auto found = inputs_.find(user_seq);
    if (found == inputs_.end()) return std::nullopt;
    const auto result = found->second;
    inputs_.erase(found);
    return result;
  }

  std::size_t size() const {
    std::lock_guard lock(mutex_);
    return inputs_.size();
  }

 private:
  mutable std::mutex mutex_;
  std::map<std::int64_t, PendingInput> inputs_;
};

}  // namespace o_reference_harness::detail
