#include "SensorClient.h"

#include "pcverse/hw/sensor_collector.hpp"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <QtConcurrent>

#include <filesystem>
#include <optional>

namespace {

QString pathToQString(const std::filesystem::path& path) {
  return QString::fromStdWString(path.wstring());
}

}  // namespace

SensorClient::SensorClient(QObject* parent) : QObject(parent) {
  const auto start = QCoreApplication::applicationDirPath().toStdWString();
  if (pcverse::hw::platform_sensors_supported()) {
#ifdef Q_OS_WIN
    if (const auto exe = pcverse::hw::find_hwmon_executable(start)) {
      hwmon_path_ = pathToQString(*exe);
      hwmon_available_ = true;
    }
#else
    hwmon_available_ = true;
#endif
  }

  connect(&poll_timer_, &QTimer::timeout, this, &SensorClient::onPollTimer);
  poll_timer_.start(5000);
  QTimer::singleShot(300, this, &SensorClient::fetchTelemetry);
}

void SensorClient::fetchTelemetry() {
  if (!hwmon_available_ || busy_) {
    return;
  }
  runCollect();
}

void SensorClient::onPollTimer() {
  fetchTelemetry();
}

void SensorClient::runCollect() {
  busy_ = true;
  const QString hwmon = hwmon_path_;

  (void)QtConcurrent::run([this, hwmon]() {
    std::optional<std::filesystem::path> exe;
#ifdef Q_OS_WIN
    if (!hwmon.isEmpty()) {
      exe = hwmon.toStdWString();
    }
#endif
    const auto result = pcverse::hw::collect_sensor_snapshot(exe);
    QMetaObject::invokeMethod(
        this,
        [this, result]() {
          busy_ = false;
          if (!result.ok) {
            emit errorOccurred(QString::fromUtf8(result.error.c_str()));
            return;
          }
          const auto doc = QJsonDocument::fromJson(QByteArray::fromStdString(result.json));
          if (!doc.isObject()) {
            emit errorOccurred(QStringLiteral("Invalid sensor JSON"));
            return;
          }
          QJsonObject telemetry = doc.object();
          const QString collector = telemetry.value(QStringLiteral("collector")).toString();
          if (collector == QStringLiteral("pcverse-sysfs")) {
            telemetry.insert(QStringLiteral("_source"), QStringLiteral("native-sysfs"));
          } else {
            telemetry.insert(QStringLiteral("_source"), QStringLiteral("native-lhm"));
          }
          emit telemetryReady(telemetry);
        },
        Qt::QueuedConnection);
  });
}
