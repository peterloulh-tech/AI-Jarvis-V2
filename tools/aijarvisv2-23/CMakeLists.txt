cmake_minimum_required(VERSION 3.24)
project(AIJARVISV2Task23Poc LANGUAGES CXX)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "AIJARVISV2-23 PoC requires Windows x64")
endif()
if(NOT GGML_CUDA)
  message(FATAL_ERROR "AIJARVISV2-23 PoC requires -DGGML_CUDA=ON")
endif()

get_filename_component(AIJARVIS_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(JARVIS_RUNTIME_ENABLE_UPSTREAM ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS ON CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_APP OFF CACHE BOOL "" FORCE)
set(LLAMA_TOOLS_INSTALL OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
if(NOT DEFINED JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR)
  set(JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR
      "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/vendor" CACHE PATH "")
endif()

find_package(Threads REQUIRED)
add_subdirectory(
  "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime"
  "${CMAKE_CURRENT_BINARY_DIR}/runtime")

add_executable(aijarvisv2-task23-poc poc_main.cpp)
target_compile_features(aijarvisv2-task23-poc PRIVATE cxx_std_17)
target_compile_definitions(aijarvisv2-task23-poc PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(aijarvisv2-task23-poc PRIVATE /utf-8)
target_include_directories(aijarvisv2-task23-poc PRIVATE
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/common"
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/tools/omni"
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/vendor")
target_link_libraries(aijarvisv2-task23-poc PRIVATE
  jarvis::runtime_provider llama-common Threads::Threads)

install(TARGETS aijarvisv2-task23-poc
  RUNTIME_DEPENDENCY_SET aijarvisv2_task23_runtime_dependencies
  RUNTIME DESTINATION bin)
install(RUNTIME_DEPENDENCY_SET aijarvisv2_task23_runtime_dependencies
  DIRECTORIES
    "$ENV{CUDA_PATH}/bin"
    "${CMAKE_BINARY_DIR}/bin/Release"
  PRE_EXCLUDE_REGEXES
    "api-ms-win-.*"
    "ext-ms-win-.*"
    "nvcuda\\.dll"
  POST_EXCLUDE_REGEXES
    ".*[Ss]ystem32.*")

install(FILES
  run-aijarvisv2-23.ps1
  gpu-capacity.ps1
  README.md
  model-provenance.template.json
  o-in-07-manifest.template.json
  DESTINATION .)
install(FILES
  "${AIJARVIS_REPOSITORY_ROOT}/docs/v2/requirements/templates/performance-sample-record.csv"
  "${AIJARVIS_REPOSITORY_ROOT}/docs/v2/requirements/templates/resource-trend-record.csv"
  "${AIJARVIS_REPOSITORY_ROOT}/docs/v2/requirements/templates/reliability-event-record.csv"
  DESTINATION templates)
install(FILES
  "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/LICENSE.llama.cpp-omni"
  "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/NOTICE.md"
  DESTINATION licenses/llama.cpp-omni)
install(FILES
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/LICENSE"
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/AUTHORS"
  DESTINATION licenses/llama.cpp-omni/upstream)
install(DIRECTORY
  "${JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR}/licenses/"
  DESTINATION licenses/llama.cpp-omni/upstream/licenses)
