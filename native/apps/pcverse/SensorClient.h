#pragma once

#include <QJsonObject>
#include <QObject>
#include <QTimer>

class SensorClient : public QObject {
  Q_OBJECT

 public:
  explicit SensorClient(QObject* parent = nullptr);

  bool isAvailable() const { return hwmon_available_; }
  bool isBusy() const { return busy_; }

 public slots:
  void fetchTelemetry();

 signals:
  void telemetryReady(const QJsonObject& telemetry);
  void availabilityChanged(bool available);
  void errorOccurred(const QString& message);

 private slots:
  void onPollTimer();

 private:
  void runCollect();

  QTimer poll_timer_;
  bool hwmon_available_{false};
  bool busy_{false};
  QString hwmon_path_;
};
