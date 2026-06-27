#include "pcverse/hw/sensor_collector.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#else
#include <dirent.h>
#include <fstream>
#include <sstream>
#endif

#include <array>
#include <cstdio>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace pcverse::hw {
namespace {

constexpr const char* kHwmonName = "PcVerseHwMon.exe";

bool path_exists(const std::filesystem::path& path) {
  std::error_code ec;
  return std::filesystem::is_regular_file(path, ec);
}

std::optional<std::filesystem::path> probe_candidate(const std::filesystem::path& base) {
  const std::array relative = {
      std::filesystem::path("agent") / "pcverse_probe" / kHwmonName,
      std::filesystem::path("probe") / kHwmonName,
  };
  for (const auto& rel : relative) {
    const auto candidate = base / rel;
    if (path_exists(candidate)) {
      return candidate;
    }
  }
  return std::nullopt;
}

#ifdef _WIN32
SensorCollectResult collect_windows(const std::filesystem::path& hwmon_exe) {
  SensorCollectResult result;

  SECURITY_ATTRIBUTES sa{};
  sa.nLength = sizeof(sa);
  sa.bInheritHandle = TRUE;

  HANDLE read_handle = nullptr;
  HANDLE write_handle = nullptr;
  if (!CreatePipe(&read_handle, &write_handle, &sa, 0)) {
    result.error = "CreatePipe failed";
    return result;
  }
  SetHandleInformation(read_handle, HANDLE_FLAG_INHERIT, 0);

  STARTUPINFOW si{};
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
  si.hStdOutput = write_handle;
  si.hStdError = write_handle;
  si.wShowWindow = SW_HIDE;

  PROCESS_INFORMATION pi{};
  const auto cmd = hwmon_exe.wstring();
  std::vector<wchar_t> cmdline(cmd.begin(), cmd.end());
  cmdline.push_back(L'\0');

  const BOOL started = CreateProcessW(
      hwmon_exe.c_str(), cmdline.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr,
      hwmon_exe.parent_path().wstring().c_str(), &si, &pi);
  CloseHandle(write_handle);

  if (!started) {
    CloseHandle(read_handle);
    result.error = "Failed to start PcVerseHwMon.exe";
    return result;
  }

  std::string output;
  std::array<char, 4096> buffer{};
  DWORD read = 0;
  while (ReadFile(read_handle, buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr) && read > 0) {
    output.append(buffer.data(), read);
  }

  CloseHandle(read_handle);
  WaitForSingleObject(pi.hProcess, 120000);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);

  if (output.empty()) {
    result.error = "PcVerseHwMon returned no data";
    return result;
  }

  result.ok = true;
  result.json = std::move(output);
  return result;
}
#else
std::string json_escape(std::string_view text) {
  std::string out;
  out.reserve(text.size() + 8);
  for (const char c : text) {
    switch (c) {
      case '\\':
        out += "\\\\";
        break;
      case '"':
        out += "\\\"";
        break;
      default:
        out.push_back(c);
        break;
    }
  }
  return out;
}

std::optional<std::string> read_file_trim(const std::filesystem::path& path) {
  std::ifstream in(path);
  if (!in) {
    return std::nullopt;
  }
  std::string line;
  std::getline(in, line);
  while (!line.empty() && (line.back() == '\r' || line.back() == '\n' || line.back() == ' ')) {
    line.pop_back();
  }
  return line;
}

std::optional<double> read_sysfs_double(const std::filesystem::path& path, double scale) {
  const auto raw = read_file_trim(path);
  if (!raw || raw->empty()) {
    return std::nullopt;
  }
  try {
    return std::stod(*raw) / scale;
  } catch (...) {
    return std::nullopt;
  }
}

void append_sensor(std::ostringstream& json, bool& first, const std::string& hardware, const std::string& name,
                   const std::string& type, double value, const std::string& unit) {
  if (!first) {
    json << ',';
  }
  first = false;
  json << "{\"hardware\":\"" << json_escape(hardware) << "\",\"name\":\"" << json_escape(name) << "\",\"type\":\""
       << json_escape(type) << "\",\"value\":" << value << ",\"unit\":\"" << json_escape(unit) << "\"}";
}

SensorCollectResult collect_linux_sysfs() {
  SensorCollectResult result;
  std::ostringstream json;
  json << "{\"collector\":\"pcverse-sysfs\",\"sensors_flat\":[";
  bool first = true;

  const std::filesystem::path hwmon_root = "/sys/class/hwmon";
  std::error_code ec;
  if (std::filesystem::exists(hwmon_root, ec)) {
    for (const auto& entry : std::filesystem::directory_iterator(hwmon_root, ec)) {
      if (ec || !entry.is_directory()) {
        continue;
      }
      const auto dir = entry.path();
      const std::string hw_name = read_file_trim(dir / "name").value_or(dir.filename().string());

      for (const auto& sensor : std::filesystem::directory_iterator(dir, ec)) {
        if (ec || !sensor.is_regular_file()) {
          continue;
        }
        const auto filename = sensor.path().filename().string();
        if (filename.rfind("temp", 0) == 0 && filename.find("_input") != std::string::npos) {
          if (const auto value = read_sysfs_double(sensor.path(), 1000.0)) {
            const auto label_path = dir / (filename.substr(0, filename.find("_input")) + "_label");
            const std::string label = read_file_trim(label_path).value_or(filename);
            append_sensor(json, first, hw_name, label, "Temperature", *value, "C");
          }
        } else if (filename.rfind("fan", 0) == 0 && filename.find("_input") != std::string::npos) {
          if (const auto value = read_sysfs_double(sensor.path(), 1.0)) {
            append_sensor(json, first, hw_name, filename, "Fan", *value, "RPM");
          }
        } else if (filename.rfind("in", 0) == 0 && filename.find("_input") != std::string::npos) {
          if (const auto value = read_sysfs_double(sensor.path(), 1000.0)) {
            append_sensor(json, first, hw_name, filename, "Voltage", *value, "V");
          }
        }
      }
    }
  }

  const std::filesystem::path thermal_root = "/sys/class/thermal";
  if (std::filesystem::exists(thermal_root, ec)) {
    for (const auto& zone : std::filesystem::directory_iterator(thermal_root, ec)) {
      if (ec || !zone.is_directory()) {
        continue;
      }
      const auto dir = zone.path();
      if (dir.filename().string().rfind("thermal_zone", 0) != 0) {
        continue;
      }
      if (const auto value = read_sysfs_double(dir / "temp", 1000.0)) {
        const std::string zone_type = read_file_trim(dir / "type").value_or(dir.filename().string());
        append_sensor(json, first, zone_type, "temp", "Temperature", *value, "C");
      }
    }
  }

  json << "]}";
  if (!first) {
    result.ok = true;
    result.json = json.str();
  } else {
    result.error = "No sysfs sensors found";
  }
  return result;
}
#endif

}  // namespace

std::optional<std::filesystem::path> find_hwmon_executable(const std::filesystem::path& start_dir) {
#ifdef _WIN32
  std::error_code ec;
  auto dir = std::filesystem::absolute(start_dir, ec);
  if (ec) {
    dir = start_dir;
  }

  for (int i = 0; i < 8; ++i) {
    if (auto found = probe_candidate(dir)) {
      return found;
    }
    const auto parent = dir.parent_path();
    if (parent == dir) {
      break;
    }
    dir = parent;
  }
#else
  (void)start_dir;
#endif
  return std::nullopt;
}

bool platform_sensors_supported() {
#if defined(_WIN32) || defined(__linux__)
  return true;
#else
  return false;
#endif
}

SensorCollectResult collect_sensor_snapshot(const std::optional<std::filesystem::path>& hwmon_exe) {
#ifdef _WIN32
  if (!hwmon_exe || !path_exists(*hwmon_exe)) {
    return {.ok = false, .error = "PcVerseHwMon.exe not found"};
  }
  return collect_windows(*hwmon_exe);
#elif defined(__linux__)
  (void)hwmon_exe;
  return collect_linux_sysfs();
#else
  (void)hwmon_exe;
  return {.ok = false, .error = "Sensor collector not implemented on this platform"};
#endif
}

}  // namespace pcverse::hw
