# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "cs2_capture")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "cs2_capture_plugin")

list(APPEND PLUGIN_SOURCES
  "cs2_capture_plugin.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

# C++/WinRT requires C++20 on current MSVC (<experimental/coroutine> was
# removed; the C++20 <coroutine> path is the supported one).
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 20
  CXX_STANDARD_REQUIRED ON
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
target_link_libraries(${PLUGIN_NAME} PRIVATE d3d11 dxgi windowsapp)

set(cs2_capture_bundled_libraries
  ""
  PARENT_SCOPE
)
