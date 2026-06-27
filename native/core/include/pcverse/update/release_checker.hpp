#pragma once

#include <optional>
#include <string>

namespace pcverse {

struct ReleaseInfo {
  std::string version;
  std::string name;
  std::string html_url;
  std::string published_at;
  std::string notes;
  std::string download_windows;
  std::string download_linux;
};

struct UpdateCheckResult {
  bool ok{false};
  std::string current_version;
  std::string message;
  bool update_available{false};
  std::optional<ReleaseInfo> release;
};

class ReleaseChecker {
 public:
  ReleaseChecker(std::string owner, std::string repo, std::string current_version);

  UpdateCheckResult check() const;

 private:
  std::string owner_;
  std::string repo_;
  std::string current_version_;
};

}  // namespace pcverse
