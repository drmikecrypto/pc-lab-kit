#pragma once

#include <string>

namespace pcverse {

/** Returns true if `latest` is strictly newer than `current` (semver-ish). */
bool is_newer_version(const std::string& latest, const std::string& current);

}  // namespace pcverse
