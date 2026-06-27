#pragma once

#include <filesystem>
#include <optional>
#include <string>

namespace pcverse::hw {

struct SensorCollectResult {
  bool ok{false};
  std::string json;
  std::string error;
};

/** Locate bundled PcVerseHwMon.exe (Windows) relative to install or repo root. */
std::optional<std::filesystem::path> find_hwmon_executable(const std::filesystem::path& start_dir);

/** True when this platform has a direct sensor collector (LHM on Windows, sysfs on Linux). */
bool platform_sensors_supported();

/** Collect sensor JSON (LHM subprocess on Windows, sysfs hwmon on Linux). */
SensorCollectResult collect_sensor_snapshot(const std::optional<std::filesystem::path>& hwmon_exe = std::nullopt);

}  // namespace pcverse::hw
