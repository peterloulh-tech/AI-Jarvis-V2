cmake_minimum_required(VERSION 3.24)
project(OReferenceHarnessV2 LANGUAGES CXX)

include(CTest)
find_package(Threads REQUIRED)

get_filename_component(AIJARVIS_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
if(NOT DEFINED JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR)
  set(JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR
    "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/vendor" CACHE PATH "")
endif()
option(O_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME
  "Link the pinned llama.cpp-omni C API for Windows/NVIDIA execution" ${WIN32})
option(O_REFERENCE_HARNESS_MSVC_PREFLIGHT
  "Compile the Windows target without CUDA" OFF)
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

add_library(o-reference-harness-core
  src/aggregation.cpp
  src/manifest.cpp
  src/profile.cpp)
target_compile_features(o-reference-harness-core PUBLIC cxx_std_20)
target_include_directories(o-reference-harness-core PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
  "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/vendor/vendor")

add_executable(o-reference-harness-v2 src/main.cpp)
target_link_libraries(o-reference-harness-v2 PRIVATE o-reference-harness-core)

if(O_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME)
  if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "The locked runtime target requires Windows x64")
  endif()
  if(NOT GGML_CUDA AND NOT O_REFERENCE_HARNESS_MSVC_PREFLIGHT)
    message(FATAL_ERROR "The dynamic Reference Harness requires -DGGML_CUDA=ON")
  endif()
  if(MSVC)
    target_compile_options(o-reference-harness-v2 PRIVATE /utf-8)
  endif()
  set(JARVIS_RUNTIME_ENABLE_UPSTREAM ON CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_TOOLS ON CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
  set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
  set(LLAMA_TOOLS_INSTALL OFF CACHE BOOL "" FORCE)
  set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
  add_subdirectory("${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime"
                   "${CMAKE_CURRENT_BINARY_DIR}/runtime")
  target_sources(o-reference-harness-v2 PRIVATE src/locked_runtime.cpp)
  target_compile_definitions(o-reference-harness-v2 PRIVATE
    O_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME NOMINMAX WIN32_LEAN_AND_MEAN)
  target_include_directories(o-reference-harness-v2 PRIVATE
    "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/common"
    "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/tools/omni"
    "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/vendor")
  target_link_libraries(o-reference-harness-v2 PRIVATE
    jarvis::runtime_provider llama-common Threads::Threads)
endif()

install(FILES
  run-o-reference-harness-v2.ps1
  package-portable.ps1
  runner-config.json
  README.md
  "${AIJARVIS_REPOSITORY_ROOT}/tools/aijarvisv2-23/gpu-capacity.ps1"
  "${AIJARVIS_REPOSITORY_ROOT}/tools/aijarvisv2-23/model-provenance.template.json"
  DESTINATION .)
install(DIRECTORY profiles/ DESTINATION profiles)
install(DIRECTORY
  "${AIJARVIS_REPOSITORY_ROOT}/tools/aijarvisv2-23/AIJARVISV2-23-NEXT-WIN-DELTA/O-IN-07-1HZ/"
  DESTINATION fixtures/official-1hz)
install(FILES fixtures/manifests/legacy-3s-replay.json
  DESTINATION fixtures/legacy-3s-replay RENAME manifest.json)
install(DIRECTORY fixtures/legacy-3s-replay/chunks/
  DESTINATION fixtures/legacy-3s-replay/chunks)
install(FILES
  "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/LICENSE.llama.cpp-omni"
  "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/NOTICE.md"
  DESTINATION licenses/llama.cpp-omni)
install(FILES
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/LICENSE"
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/AUTHORS"
  DESTINATION licenses/llama.cpp-omni/upstream)
install(DIRECTORY "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/licenses/"
  DESTINATION licenses/llama.cpp-omni/upstream/licenses)

install(TARGETS o-reference-harness-v2
  RUNTIME_DEPENDENCY_SET o_reference_harness_runtime_dependencies
  RUNTIME DESTINATION bin)
if(O_REFERENCE_HARNESS_WITH_LOCKED_RUNTIME)
  install(RUNTIME_DEPENDENCY_SET o_reference_harness_runtime_dependencies
    DIRECTORIES "$ENV{CUDA_PATH}/bin" "${CMAKE_BINARY_DIR}/bin/Release"
    PRE_EXCLUDE_REGEXES "api-ms-win-.*" "ext-ms-win-.*" "nvcuda\\.dll"
    POST_EXCLUDE_REGEXES ".*[Ss]ystem32.*")
endif()

if(BUILD_TESTING)
  add_executable(o-reference-harness-core-tests tests/core_tests.cpp)
  target_link_libraries(o-reference-harness-core-tests PRIVATE o-reference-harness-core)
  add_test(NAME o-reference-harness-core-tests
    COMMAND o-reference-harness-core-tests "${AIJARVIS_REPOSITORY_ROOT}")
  add_executable(o-reference-harness-pending-inputs-tests tests/pending_inputs_test.cpp)
  target_compile_features(o-reference-harness-pending-inputs-tests PRIVATE cxx_std_20)
  target_include_directories(o-reference-harness-pending-inputs-tests PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_link_libraries(o-reference-harness-pending-inputs-tests PRIVATE Threads::Threads)
  add_test(NAME o-reference-harness-pending-inputs-tests
    COMMAND o-reference-harness-pending-inputs-tests)
endif()
