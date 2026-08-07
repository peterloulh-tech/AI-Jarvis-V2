cmake_minimum_required(VERSION 3.24)
project(AIJARVISV2Task23Poc LANGUAGES CXX)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "AIJARVISV2-23 PoC requires Windows x64")
endif()
if(NOT GGML_CUDA)
  message(FATAL_ERROR "AIJARVISV2-23 PoC requires -DGGML_CUDA=ON")
endif()

get_filename_component(AIJARVIS_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(JARVIS_RUNTIME_ENABLE_UPSTREAM ON CACHE BOOL "" FORCE)
if(NOT DEFINED JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR)
  set(JARVIS_RUNTIME_UPSTREAM_SOURCE_DIR
      "${AIJARVIS_REPOSITORY_ROOT}/third_party/runtime/vendor" CACHE PATH "")
endif()

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
