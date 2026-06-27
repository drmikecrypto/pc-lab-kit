#include "pcverse/update/http_fetch.hpp"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <winhttp.h>
#else
#include <httplib.h>
#endif

#include <string>
#include <utility>
#include <vector>

namespace pcverse {
namespace {

#ifdef _WIN32
std::wstring to_wide(const std::string& utf8) {
  if (utf8.empty()) {
    return {};
  }
  const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), nullptr, 0);
  if (len <= 0) {
    return {};
  }
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), out.data(), len);
  return out;
}

HttpFetchResult winhttp_get(const std::string& host, const std::string& path,
                            const std::vector<std::pair<std::string, std::string>>& headers) {
  HttpFetchResult result;

  HINTERNET session =
      WinHttpOpen(L"PCVerse-Native-UpdateChecker", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME,
                  WINHTTP_NO_PROXY_BYPASS, 0);
  if (!session) {
    result.error = "WinHTTP session failed";
    return result;
  }

  WinHttpSetTimeouts(session, 8000, 8000, 8000, 8000);

  const auto whost = to_wide(host);
  HINTERNET connect = WinHttpConnect(session, whost.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0);
  if (!connect) {
    WinHttpCloseHandle(session);
    result.error = "WinHTTP connect failed";
    return result;
  }

  const auto wpath = to_wide(path);
  HINTERNET request =
      WinHttpOpenRequest(connect, L"GET", wpath.c_str(), nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                         WINHTTP_FLAG_SECURE);
  if (!request) {
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    result.error = "WinHTTP request failed";
    return result;
  }

  for (const auto& [key, value] : headers) {
    const auto header = to_wide(key + ": " + value);
    WinHttpAddRequestHeaders(request, header.c_str(), static_cast<DWORD>(header.size()),
                           WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
  }

  if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
      !WinHttpReceiveResponse(request, nullptr)) {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    result.error = "WinHTTP send/receive failed";
    return result;
  }

  DWORD status = 0;
  DWORD status_size = sizeof(status);
  WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX,
                      &status, &status_size, WINHTTP_NO_HEADER_INDEX);
  result.status = static_cast<int>(status);

  std::string body;
  DWORD available = 0;
  do {
    if (!WinHttpQueryDataAvailable(request, &available)) {
      break;
    }
    if (available == 0) {
      break;
    }
    const size_t offset = body.size();
    body.resize(offset + available);
    DWORD read = 0;
    if (!WinHttpReadData(request, body.data() + offset, available, &read)) {
      body.resize(offset);
      break;
    }
    body.resize(offset + read);
  } while (available > 0);

  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);

  result.body = std::move(body);
  result.ok = true;
  return result;
}
#else
HttpFetchResult httplib_get(const std::string& host, const std::string& path,
                            const std::vector<std::pair<std::string, std::string>>& headers) {
  HttpFetchResult result;

  httplib::Client cli("https://" + host);
  cli.set_connection_timeout(8, 0);
  cli.set_read_timeout(8, 0);
  httplib::Headers h;
  for (const auto& [key, value] : headers) {
    h.emplace(key, value);
  }
  cli.set_default_headers(h);

  const auto res = cli.Get(path.c_str());
  if (!res) {
    result.error = "HTTP request failed";
    return result;
  }

  result.ok = true;
  result.status = res->status;
  result.body = res->body;
  return result;
}
#endif

}  // namespace

HttpFetchResult http_get_https(const std::string& host, const std::string& path,
                               const std::vector<std::pair<std::string, std::string>>& headers) {
#ifdef _WIN32
  return winhttp_get(host, path, headers);
#else
  return httplib_get(host, path, headers);
#endif
}

}  // namespace pcverse
