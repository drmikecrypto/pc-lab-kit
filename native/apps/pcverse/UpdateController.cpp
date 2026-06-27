#include "UpdateController.h"

#include "pcverse/semver.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>

UpdateController::UpdateController(QObject* parent) : QObject(parent), nam_(new QNetworkAccessManager(this)) {}

void UpdateController::checkForUpdates() {
  const QUrl url(QStringLiteral("https://api.github.com/repos/%1/%2/releases/latest")
                     .arg(QStringLiteral(PCVERSE_GITHUB_OWNER), QStringLiteral(PCVERSE_GITHUB_REPO)));
  QNetworkRequest req(url);
  req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("PCVerse-Native-Desktop"));
  req.setRawHeader("Accept", "application/vnd.github+json");

  auto* reply = nam_->get(req);
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    if (reply->error() != QNetworkReply::NoError) {
      emit checkFailed(reply->errorString());
      reply->deleteLater();
      return;
    }
    const auto doc = QJsonDocument::fromJson(reply->readAll());
    reply->deleteLater();
    if (!doc.isObject()) {
      emit checkFailed(QStringLiteral("Invalid GitHub response"));
      return;
    }

    const QJsonObject root = doc.object();
    QString tag = root.value(QStringLiteral("tag_name")).toString();
    while (tag.startsWith('v') || tag.startsWith('V')) {
      tag.remove(0, 1);
    }

    UpdateInfo info;
    info.latest_version = tag;
    info.release_url = root.value(QStringLiteral("html_url")).toString();
    if (info.release_url.isEmpty()) {
      info.release_url = QStringLiteral("https://github.com/%1/%2/releases/latest")
                             .arg(QStringLiteral(PCVERSE_GITHUB_OWNER), QStringLiteral(PCVERSE_GITHUB_REPO));
    }

    const QJsonArray assets = root.value(QStringLiteral("assets")).toArray();
    for (const auto& v : assets) {
      const QJsonObject a = v.toObject();
      const QString name = a.value(QStringLiteral("name")).toString().toLower();
      const QString url = a.value(QStringLiteral("browser_download_url")).toString();
      if (name.contains(QStringLiteral("native-setup-windows")) || name.contains(QStringLiteral("native-setup-windows-x64"))) {
        info.download_windows = url;
      } else if (info.download_windows.isEmpty() && name.contains(QStringLiteral("windows"))) {
        info.download_windows = url;
      }
      if (name.contains(QStringLiteral("native-setup-linux")) || name.contains(QStringLiteral("native-setup-linux-x64"))) {
        info.download_linux = url;
      } else if (info.download_linux.isEmpty() && name.contains(QStringLiteral("linux"))) {
        info.download_linux = url;
      }
    }

    const std::string current = PCVERSE_VERSION;
    info.update_available = pcverse::is_newer_version(tag.toStdString(), current);
    emit updateChecked(info);
  });
}
