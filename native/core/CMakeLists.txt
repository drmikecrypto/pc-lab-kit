add_library(pcverse_core STATIC
  src/semver.cpp
  src/hw/sensor_collector.cpp
  src/update/http_fetch.cpp
  src/update/release_checker.cpp
)

target_include_directories(pcverse_core PUBLIC include)

if(WIN32)
  target_link_libraries(pcverse_core PUBLIC winhttp ws2_32)
else()
  target_link_libraries(pcverse_core PUBLIC httplib::httplib)
endif()

target_compile_definitions(pcverse_core PUBLIC
  PCVERSE_VERSION="${PROJECT_VERSION}"
  PCVERSE_GITHUB_OWNER="drmikecrypto"
  PCVERSE_GITHUB_REPO="pc-lab-kit"
)
