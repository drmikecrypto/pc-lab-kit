cmake_minimum_required(VERSION 3.20)
project(pcverse_native VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(FetchContent)

FetchContent_Declare(
  httplib
  GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
  GIT_TAG v0.18.3
)
FetchContent_MakeAvailable(httplib)

add_subdirectory(core)
add_subdirectory(apps/pcverse_cli)

# Qt 6 desktop (Phase 1) — run ..\scripts\bootstrap-qt.ps1 if missing
set(PCVERSE_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
if(WIN32)
  set(_PCVERSE_QT_ARCHS msvc2022_64 win64_msvc2022_64)
else()
  set(_PCVERSE_QT_ARCHS linux_gcc_64 gcc_64)
endif()

if(DEFINED ENV{QT6_ROOT})
  list(PREPEND CMAKE_PREFIX_PATH "$ENV{QT6_ROOT}")
elseif(NOT CMAKE_PREFIX_PATH)
  foreach(_arch IN LISTS _PCVERSE_QT_ARCHS)
    set(_candidate "${PCVERSE_REPO_ROOT}/build-cache/qt/6.8.2/${_arch}")
    if(EXISTS "${_candidate}/lib/cmake/Qt6")
      list(PREPEND CMAKE_PREFIX_PATH "${_candidate}")
      break()
    endif()
  endforeach()
endif()

option(PCVERSE_BUILD_DESKTOP "Build Qt desktop shell" ON)
if(PCVERSE_BUILD_DESKTOP)
  find_package(Qt6 QUIET COMPONENTS Core Widgets Network Concurrent)
  if(Qt6_FOUND)
    add_subdirectory(apps/pcverse)
  else()
    message(STATUS "Qt6 not found — run: ..\\scripts\\bootstrap-qt.ps1")
  endif()
endif()
