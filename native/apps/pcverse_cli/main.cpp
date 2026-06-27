#include "pcverse/config.hpp"
#include "pcverse/update/release_checker.hpp"

#include <iostream>

int main(int argc, char* argv[]) {
  const bool check_update = (argc > 1 && std::string(argv[1]) == "--check-update");

  if (!check_update) {
    std::cout << "PCVerse native CLI v" << pcverse::kVersion << "\n"
              << "Usage: pcverse_cli --check-update\n";
    return 0;
  }

  pcverse::ReleaseChecker checker(pcverse::kGithubOwner, pcverse::kGithubRepo, pcverse::kVersion);
  const auto result = checker.check();

  std::cout << "current=" << result.current_version << "\n";
  if (!result.ok) {
    std::cerr << result.message << "\n";
    return 1;
  }

  const auto& r = *result.release;
  std::cout << "latest=" << r.version << "\n"
            << "update_available=" << (result.update_available ? "yes" : "no") << "\n"
            << "url=" << r.html_url << "\n";
  if (!r.download_windows.empty()) {
    std::cout << "windows=" << r.download_windows << "\n";
  }
  if (!r.download_linux.empty()) {
    std::cout << "linux=" << r.download_linux << "\n";
  }
  return 0;
}
