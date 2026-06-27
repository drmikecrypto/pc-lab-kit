#pragma once

#include <QObject>

class QNetworkAccessManager;

struct UpdateInfo {
  QString latest_version;
  QString release_url;
  QString download_windows;
  QString download_linux;
  bool update_available{false};
};

class UpdateController : public QObject {
  Q_OBJECT

 public:
  explicit UpdateController(QObject* parent = nullptr);

  void checkForUpdates();

 signals:
  void updateChecked(const UpdateInfo& info);
  void checkFailed(const QString& message);

 private:
  QNetworkAccessManager* nam_;
};
