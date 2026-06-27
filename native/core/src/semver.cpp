#include "pcverse/semver.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>
#include <vector>

namespace pcverse {
namespace {

std::vector<int> parse_parts(std::string s) {
  for (char& c : s) {
    if (!std::isdigit(static_cast<unsigned char>(c))) {
      c = ' ';
    }
  }
  std::istringstream in(s);
  std::vector<int> parts;
  int n = 0;
  while (in >> n) {
    parts.push_back(n);
  }
  if (parts.empty()) {
    parts.push_back(0);
  }
  return parts;
}

}  // namespace

bool is_newer_version(const std::string& latest, const std::string& current) {
  if (latest == current) {
    return false;
  }
  auto a = parse_parts(latest);
  auto b = parse_parts(current);
  const auto n = std::max(a.size(), b.size());
  a.resize(n, 0);
  b.resize(n, 0);
  for (size_t i = 0; i < n; ++i) {
    if (a[i] > b[i]) {
      return true;
    }
    if (a[i] < b[i]) {
      return false;
    }
  }
  return false;
}

}  // namespace pcverse
