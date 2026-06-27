#pragma once

#include <QWidget>

class ProbeClient;
class SensorClient;

class MonitorPage : public QWidget {
  Q_OBJECT

 public:
  explicit MonitorPage(ProbeClient* probe, SensorClient* sensors, QWidget* parent = nullptr);

 public slots:
  void onTelemetry(const QJsonObject& telemetry);
  void onHealth(bool online, const QJsonObject& info);

 private:
  ProbeClient* probe_;
  SensorClient* sensors_;
  class QTableWidget* table_;
  class QLabel* status_;
};
