#include "pcverse/update/release_checker.hpp"

#include "pcverse/semver.hpp"
#include "pcverse/update/http_fetch.hpp"

#include <cctype>
#include <sstream>
#include <string>

namespace pcverse {
namespace {

std::string trim_v_prefix(std::string tag) {
  while (!tag.empty() && (tag.front() == 'v' || tag.front() == 'V')) {
    tag.erase(tag.begin());
  }
  return tag;
}

std::string extract_json_string(const std::string& json, const std::string& key) {
  const std::string needle = "\"" + key + "\":";
  const auto pos = json.find(needle);
  if (pos == std::string::npos) {
    return {};
  }
  auto i = pos + needle.size();
  while (i < json.size() && std::isspace(static_cast<unsigned char>(json[i]))) {
    ++i;
  }
  if (i >= json.size() || json[i] != '"') {
    return {};
  }
  ++i;
  std::string out;
  while (i < json.size() && json[i] != '"') {
    if (json[i] == '\\' && i + 1 < json.size()) {
      out.push_back(json[i + 1]);
      i += 2;
      continue;
    }
    out.push_back(json[i++]);
  }
  return out;
}

std::string find_asset_url(const std::string& json, const std::string& match_substr) {
  const std::string lower_match = [&] {
    std::string s = match_substr;
    for (char& c : s) {
      c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
  }();

  size_t pos = 0;
  while ((pos = json.find("\"name\"", pos)) != std::string::npos) {
    const auto name = extract_json_string(json.substr(pos), "name");
    std::string lower_name = name;
    for (char& c : lower_name) {
      c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    if (lower_name.find(lower_match) != std::string::npos) {
      const auto browser_pos = json.find("\"browser_download_url\"", pos);
      if (browser_pos != std::string::npos) {
        return extract_json_string(json.substr(browser_pos), "browser_download_url");
      }
    }
    pos += 6;
  }
  return {};
}

std::string trim_notes(std::string body) {
  while (!body.empty() && std::isspace(static_cast<unsigned char>(body.front()))) {
    body.erase(body.begin());
  }
  while (!body.empty() && std::isspace(static_cast<unsigned char>(body.back()))) {
    body.pop_back();
  }
  if (body.size() > 600) {
    body.resize(597);
    body += "...";
  }
  return body;
}

}  // namespace

ReleaseChecker::ReleaseChecker(std::string owner, std::string repo, std::string current_version)
    : owner_(std::move(owner)), repo_(std::move(repo)), current_version_(std::move(current_version)) {}

UpdateCheckResult ReleaseChecker::check() const {
  UpdateCheckResult result;
  result.current_version = current_version_;

  const auto path = "/repos/" + owner_ + "/" + repo_ + "/releases/latest";
  const auto res = http_get_https(
      "api.github.com", path,
      {{"User-Agent", "PCVerse-Native-UpdateChecker"}, {"Accept", "application/vnd.github+json"}});
  if (!res.ok || res.status != 200) {
    result.message = res.error.empty() ? "Could not reach GitHub releases. Try again later." : res.error;
    return result;
  }

  const auto& body = res.body;
  const auto version = trim_v_prefix(extract_json_string(body, "tag_name"));
  if (version.empty()) {
    result.message = "Invalid release metadata from GitHub.";
    return result;
  }

  ReleaseInfo info;
  info.version = version;
  info.name = extract_json_string(body, "name");
  info.html_url = extract_json_string(body, "html_url");
  if (info.html_url.empty()) {
    info.html_url = "https://github.com/" + owner_ + "/" + repo_ + "/releases/latest";
  }
  info.published_at = extract_json_string(body, "published_at");
  info.notes = trim_notes(extract_json_string(body, "body"));
  info.download_windows = find_asset_url(body, "pcverse-native-setup-windows-x64.exe");
  if (info.download_windows.empty()) {
    info.download_windows = find_asset_url(body, "pcverse-setup-windows-x64.exe");
  }
  if (info.download_windows.empty()) {
    info.download_windows = find_asset_url(body, "windows");
  }
  info.download_linux = find_asset_url(body, "pcverse-native-setup-linux-x64.run");
  if (info.download_linux.empty()) {
    info.download_linux = find_asset_url(body, "pcverse-setup-linux-x64.run");
  }

  result.ok = true;
  result.release = info;
  result.update_available = is_newer_version(info.version, current_version_);
  result.message = result.update_available ? "Update available." : "You are on the latest release.";
  return result;
}

}  // namespace pcverse
