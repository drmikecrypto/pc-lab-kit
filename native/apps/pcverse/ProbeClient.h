#pragma once

#include <QJsonObject>
#include <QObject>
#include <QTimer>

#include <functional>

class QNetworkAccessManager;

class ProbeClient : public QObject {
  Q_OBJECT

 public:
  explicit ProbeClient(QObject* parent = nullptr);

  bool isOnline() const { return online_; }
  QString repoRoot() const { return repo_root_; }

  void ensureProbeRunning();
  void refreshHealth();
  void fetchTelemetry();
  void fetchProbeScan();

 signals:
  void healthChanged(bool online, const QJsonObject& info);
  void telemetryReady(const QJsonObject& telemetry);
  void scanReady(const QJsonObject& scan);
  void scanFailed(const QString& message);
  void errorOccurred(const QString& message);

 private:
  void getJson(const QString& path, const std::function<void(const QJsonObject&)>& on_ok);

  QNetworkAccessManager* nam_;
  QTimer health_timer_;
  QString repo_root_;
  bool online_{false};
  bool probe_spawned_{false};
};
