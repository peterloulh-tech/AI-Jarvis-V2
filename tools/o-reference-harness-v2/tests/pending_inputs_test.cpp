#include "pending_inputs.hpp"

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <thread>

using o_reference_harness::detail::PendingInput;
using o_reference_harness::detail::PendingInputs;

int main() {
  PendingInputs pending;
  constexpr std::int64_t count = 20000;
  std::atomic<std::int64_t> consumed{0};
  std::thread producer([&] {
    for (std::int64_t sequence = 1; sequence <= count; ++sequence) {
      pending.put(sequence, PendingInput{.generation_id = 7,
                                         .offset_ms = sequence * 1000,
                                         .duration_ms = 1000});
    }
  });
  std::thread consumer([&] {
    for (std::int64_t sequence = 1; sequence <= count; ++sequence) {
      for (;;) {
        const auto value = pending.take(sequence);
        if (value) {
          if (value->generation_id != 7 || value->offset_ms != sequence * 1000) {
            std::abort();
          }
          ++consumed;
          break;
        }
        std::this_thread::yield();
      }
    }
  });
  producer.join();
  consumer.join();
  if (consumed != count || pending.size() != 0) return EXIT_FAILURE;
  std::cout << "PASS concurrent pending input correlation\n";
  return EXIT_SUCCESS;
}
