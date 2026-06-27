set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Widgets Network Concurrent)

qt_add_executable(pcverse WIN32
  main.cpp
  MainWindow.cpp
  ProbeClient.cpp
  SensorClient.cpp
  UpdateController.cpp
  SettingsStore.cpp
  MonitorPage.cpp
  ScanPage.cpp
  ToolkitPage.cpp
  SettingsPage.cpp
  resources/app.qrc
)

target_link_libraries(pcverse PRIVATE
  Qt6::Core
  Qt6::Widgets
  Qt6::Network
  Qt6::Concurrent
  pcverse_core
)

target_compile_definitions(pcverse PRIVATE
  PCVERSE_VERSION="${PROJECT_VERSION}"
  PCVERSE_GITHUB_OWNER="drmikecrypto"
  PCVERSE_GITHUB_REPO="pc-lab-kit"
)

if(WIN32)
  set_property(TARGET pcverse PROPERTY WIN32_EXECUTABLE TRUE)
endif()
