#include "o_reference_harness/locked_runtime.hpp"

#include "common.h"
#include "omni.h"
#include "pending_inputs.hpp"

#include <chrono>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <utility>

#ifdef _WIN32
#include <windows.h>
#endif

namespace o_reference_harness {
namespace {

std::string path_utf8(const std::filesystem::path& path) {
#ifdef _WIN32
  const auto& native = path.native();
  if (native.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, native.data(),
                                       static_cast<int>(native.size()), nullptr, 0,
                                       nullptr, nullptr);
  if (size <= 0) throw std::runtime_error("cannot encode path as UTF-8");
  std::string result(static_cast<std::size_t>(size), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, native.data(),
                          static_cast<int>(native.size()), result.data(), size,
                          nullptr, nullptr) != size) {
    throw std::runtime_error("cannot encode path as UTF-8");
  }
  return result;
#else
  return path.string();
#endif
}

std::int64_t monotonic_us() {
  return std::chrono::duration_cast<std::chrono::microseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

}  // namespace

struct LockedRuntime::Impl {
  common_params params;
  omni_context* context{};
  bool session_active{};
  detail::PendingInputs pending;

  explicit Impl(const LockedModelConfig& config) {
    common_init();
    params.model.path = path_utf8(config.model_root / "MiniCPM-o-4_5-Q4_K_M.gguf");
    params.vpm_model =
        path_utf8(config.model_root / "vision/MiniCPM-o-4_5-vision-F16.gguf");
    params.apm_model =
        path_utf8(config.model_root / "audio/MiniCPM-o-4_5-audio-F16.gguf");
    params.n_ctx = 4096;
    params.n_batch = 512;
    params.n_ubatch = 256;
    params.n_predict = 1024;
    params.n_gpu_layers = 99;
    params.display_prompt = false;
    params.show_timings = false;
    params.sampling.seed = 42;
    context = omni_init(&params, 2, false, "", -1, "gpu:0", true, nullptr, nullptr,
                        path_utf8(config.output_root));
    if (context == nullptr) throw std::runtime_error("locked omni_init failed");
    context->async = true;
    context->duplex_mode = true;
    context->ref_audio_path.clear();
  }

  ~Impl() {
    if (context != nullptr) {
      if (session_active) omni_duplex_session_end(context);
      omni_free(context);
    }
  }
};

LockedRuntime::LockedRuntime(const LockedModelConfig& config)
    : impl_(std::make_unique<Impl>(config)) {}

LockedRuntime::~LockedRuntime() = default;
LockedRuntime::LockedRuntime(LockedRuntime&&) noexcept = default;
LockedRuntime& LockedRuntime::operator=(LockedRuntime&&) noexcept = default;

void LockedRuntime::begin(const Profile& profile,
                          const std::filesystem::path& debug_directory) {
  if (!impl_ || impl_->session_active) throw std::logic_error("runtime session already active");
  impl_->context->omni_voice_clone_prompt = profile.system_prompt;
  impl_->context->omni_assistant_prompt = profile.assistant_prompt;
  impl_->context->ref_audio_path.clear();
  if (!omni_duplex_session_begin(impl_->context, "", path_utf8(debug_directory))) {
    throw std::runtime_error("locked duplex session begin failed");
  }
  impl_->session_active = true;
}

std::int64_t LockedRuntime::push(const InputChunk& input, int generation_id) {
  if (!impl_ || !impl_->session_active) throw std::logic_error("runtime session is not active");
  if (generation_id < 0 || input.index > std::numeric_limits<std::uint32_t>::max()) {
    throw std::invalid_argument("generation or input index is outside user_seq range");
  }
  const auto encoded = (static_cast<std::uint64_t>(static_cast<std::uint32_t>(generation_id))
                        << 32U) |
                       static_cast<std::uint32_t>(input.index);
  if (encoded > static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max())) {
    throw std::invalid_argument("encoded user_seq exceeds signed C API range");
  }
  const auto user_seq = static_cast<std::int64_t>(encoded);
  OmniDuplexFrame frame;
  frame.aud_fname = path_utf8(input.audio);
  frame.img_fname = path_utf8(input.image);
  frame.max_slice_nums = -1;
  frame.user_seq = user_seq;
  const auto frame_id = omni_duplex_push_frame(impl_->context, frame);
  if (frame_id >= 0) {
    impl_->pending.put(user_seq, detail::PendingInput{.generation_id = generation_id,
                                                       .offset_ms = input.offset_ms,
                                                       .duration_ms = input.duration_ms});
  }
  return frame_id;
}

std::optional<RawRuntimeResult> LockedRuntime::wait(int timeout_ms) {
  if (!impl_ || !impl_->session_active) throw std::logic_error("runtime session is not active");
  OmniDuplexFrameResult result;
  if (!omni_duplex_wait_next_frame(impl_->context, &result, timeout_ms)) return std::nullopt;
  const auto input = impl_->pending.take(result.user_seq);
  if (!input) {
    throw std::runtime_error("locked runtime returned an unknown user_seq");
  }
  return RawRuntimeResult{.user_seq = static_cast<std::uint64_t>(result.user_seq),
                          .frame_id = result.frame_id,
                          .generation_id = input->generation_id,
                          .ok = result.ok,
                          .is_speak = result.is_speak,
                          .fragment = result.text,
                          .latency_ms = result.ms_total,
                          .input_offset_ms = input->offset_ms,
                          .input_duration_ms = input->duration_ms,
                          .seen_at_us = monotonic_us()};
}

void LockedRuntime::end() {
  if (!impl_ || !impl_->session_active) return;
  omni_duplex_session_end(impl_->context);
  impl_->session_active = false;
}

}  // namespace o_reference_harness
