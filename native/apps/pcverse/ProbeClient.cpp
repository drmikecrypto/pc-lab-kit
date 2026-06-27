#include "ProbeClient.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcess>
#include <QUrl>
#include <functional>

namespace {

constexpr int kProbePort = 18765;

QString findRepoRoot() {
  QDir dir(QCoreApplication::applicationDirPath());
  for (int i = 0; i < 8; ++i) {
    if (QFileInfo::exists(dir.filePath(QStringLiteral("agent/pcverse_probe/PCVerseProbeServe.ps1")))) {
      return dir.absolutePath();
    }
    if (!dir.cdUp()) {
      break;
    }
  }
  return {};
}

}  // namespace

ProbeClient::ProbeClient(QObject* parent) : QObject(parent), nam_(new QNetworkAccessManager(this)) {
  repo_root_ = findRepoRoot();
  connect(&health_timer_, &QTimer::timeout, this, &ProbeClient::refreshHealth);
  health_timer_.start(3000);
  ensureProbeRunning();
  QTimer::singleShot(500, this, &ProbeClient::refreshHealth);
}

void ProbeClient::ensureProbeRunning() {
  if (repo_root_.isEmpty() || online_ || probe_spawned_) {
    return;
  }
  const auto script = QDir(repo_root_).filePath(QStringLiteral("agent/pcverse_probe/PCVerseProbeServe.ps1"));
  if (!QFileInfo::exists(script)) {
    return;
  }
  probe_spawned_ = true;
#ifdef Q_OS_WIN
  QProcess::startDetached(QStringLiteral("powershell"),
                          {QStringLiteral("-NoProfile"), QStringLiteral("-ExecutionPolicy"), QStringLiteral("Bypass"),
                           QStringLiteral("-File"), script},
                          repo_root_);
#elif defined(Q_OS_LINUX)
  if (QFileInfo::exists(QStringLiteral("/usr/bin/pwsh"))) {
    QProcess::startDetached(QStringLiteral("pwsh"),
                            {QStringLiteral("-NoProfile"), QStringLiteral("-File"), script}, repo_root_);
  }
#endif
}

void ProbeClient::getJson(const QString& path, const std::function<void(const QJsonObject&)>& on_ok) {
  const QUrl url(QStringLiteral("http://127.0.0.1:%1%2").arg(kProbePort).arg(path));
  auto* reply = nam_->get(QNetworkRequest(url));
  connect(reply, &QNetworkReply::finished, this, [this, reply, on_ok]() {
    if (reply->error() != QNetworkReply::NoError) {
      online_ = false;
      emit errorOccurred(reply->errorString());
      reply->deleteLater();
      return;
    }
    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) {
      emit errorOccurred(QStringLiteral("Invalid JSON from probe"));
      return;
    }
    on_ok(doc.object());
  });
}

void ProbeClient::refreshHealth() {
  getJson(QStringLiteral("/health"), [this](const QJsonObject& obj) {
    const bool was_offline = !online_;
    online_ = obj.value(QStringLiteral("ok")).toBool(false);
    if (online_ && was_offline) {
      probe_spawned_ = false;
    }
    emit healthChanged(online_, obj);
  });
}

void ProbeClient::fetchTelemetry() {
  if (!online_) {
    emit errorOccurred(QStringLiteral("Probe offline - starting probe service..."));
    ensureProbeRunning();
    return;
  }
  getJson(QStringLiteral("/telemetry"), [this](const QJsonObject& obj) { emit telemetryReady(obj); });
}

void ProbeClient::fetchProbeScan() {
  if (!online_) {
    emit scanFailed(QStringLiteral("Probe offline"));
    ensureProbeRunning();
    return;
  }
  const QUrl url(QStringLiteral("http://127.0.0.1:%1/probe").arg(kProbePort));
  auto* reply = nam_->get(QNetworkRequest(url));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    if (reply->error() != QNetworkReply::NoError) {
      emit scanFailed(reply->errorString());
      reply->deleteLater();
      return;
    }
    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) {
      emit scanFailed(QStringLiteral("Invalid probe response"));
      return;
    }
    emit scanReady(doc.object());
  });
}
