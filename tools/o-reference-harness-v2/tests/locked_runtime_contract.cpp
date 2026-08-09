#include "o_reference_harness/locked_runtime.hpp"

#include <type_traits>

using o_reference_harness::LockedRuntime;

static_assert(!std::is_copy_constructible_v<LockedRuntime>);
static_assert(!std::is_copy_assignable_v<LockedRuntime>);
static_assert(std::is_move_constructible_v<LockedRuntime>);
static_assert(std::is_move_assignable_v<LockedRuntime>);

int main() { return 0; }
