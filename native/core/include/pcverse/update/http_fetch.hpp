#pragma once

#include <string>
#include <utility>
#include <vector>

namespace pcverse {

struct HttpFetchResult {
  bool ok{false};
  int status{0};
  std::string body;
  std::string error;
};

HttpFetchResult http_get_https(const std::string& host, const std::string& path,
                               const std::vector<std::pair<std::string, std::string>>& headers);

}  // namespace pcverse
