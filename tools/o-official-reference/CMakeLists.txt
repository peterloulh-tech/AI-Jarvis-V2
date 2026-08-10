cmake_minimum_required(VERSION 3.24)
project(AIJARVISV2OfficialOReference LANGUAGES CXX)

include(CTest)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  add_compile_options(/utf-8)
endif()

set(AIJARVIS_OFFICIAL_RUNTIME_SOURCE_DIR "" CACHE PATH
    "Pinned llama.cpp-omni source checkout used only for official headers and the server build")
if(NOT AIJARVIS_OFFICIAL_RUNTIME_SOURCE_DIR)
  message(FATAL_ERROR "AIJARVIS_OFFICIAL_RUNTIME_SOURCE_DIR must point to the pinned official checkout")
endif()

add_library(aijarvisv2_official_reference_core STATIC
  src/official_reference_core.cpp)
target_compile_features(aijarvisv2_official_reference_core PUBLIC cxx_std_17)
target_include_directories(aijarvisv2_official_reference_core
  PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src"
  PRIVATE "${AIJARVIS_OFFICIAL_RUNTIME_SOURCE_DIR}/vendor")

add_executable(aijarvisv2-o-official-adapter src/official_adapter.cpp)
target_compile_features(aijarvisv2-o-official-adapter PRIVATE cxx_std_17)
target_include_directories(aijarvisv2-o-official-adapter PRIVATE
  "${AIJARVIS_OFFICIAL_RUNTIME_SOURCE_DIR}/vendor")
target_link_libraries(aijarvisv2-o-official-adapter PRIVATE
  aijarvisv2_official_reference_core)
if(MSVC)
  target_compile_definitions(aijarvisv2-o-official-adapter PRIVATE
    NOMINMAX WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x0A00)
  target_link_libraries(aijarvisv2-o-official-adapter PRIVATE ws2_32)
endif()

if(BUILD_TESTING)
  add_executable(aijarvisv2-o-official-tests tests/official_reference_tests.cpp)
  target_compile_features(aijarvisv2-o-official-tests PRIVATE cxx_std_17)
  target_include_directories(aijarvisv2-o-official-tests PRIVATE
    "${AIJARVIS_OFFICIAL_RUNTIME_SOURCE_DIR}/vendor")
  target_link_libraries(aijarvisv2-o-official-tests PRIVATE
    aijarvisv2_official_reference_core)
  add_test(NAME aijarvisv2-o-official-tests COMMAND
    aijarvisv2-o-official-tests
    "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/official-sse.txt"
    "${CMAKE_CURRENT_SOURCE_DIR}/official-config.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/upstream-lock.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/../aijarvisv2-23/AIJARVISV2-23-NEXT-WIN-DELTA/O-IN-07-1HZ/manifest.json")
endif()

install(TARGETS aijarvisv2-o-official-adapter RUNTIME DESTINATION bin)
install(FILES
  official-config.json
  upstream-lock.json
  run-o-official-reference.ps1
  README.md
  DESTINATION .)
install(FILES fixtures/official-sse.txt DESTINATION fixtures)
