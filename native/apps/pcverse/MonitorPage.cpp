#include "MonitorPage.h"

#include "ProbeClient.h"
#include "SensorClient.h"

#include <QHBoxLayout>
#include <QHeaderView>
#include <QJsonArray>
#include <QJsonObject>
#include <QLabel>
#include <QPushButton>
#include <QTableWidget>
#include <QTimer>
#include <QVBoxLayout>

MonitorPage::MonitorPage(ProbeClient* probe, SensorClient* sensors, QWidget* parent)
    : QWidget(parent), probe_(probe), sensors_(sensors) {
  auto* layout = new QVBoxLayout(this);

  status_ = new QLabel(sensors_ && sensors_->isAvailable() ? tr("Native sensor engine ready")
                                                            : tr("Connecting to probe…"));
  layout->addWidget(status_);

  auto* row = new QHBoxLayout();
  auto* refresh = new QPushButton(tr("Refresh sensors"));
  connect(refresh, &QPushButton::clicked, this, [this]() {
    if (sensors_ && sensors_->isAvailable()) {
      sensors_->fetchTelemetry();
    } else {
      probe_->fetchTelemetry();
    }
  });
  row->addWidget(refresh);
  row->addStretch();
  layout->addLayout(row);

  table_ = new QTableWidget(0, 4, this);
  table_->setHorizontalHeaderLabels({tr("Hardware"), tr("Sensor"), tr("Type"), tr("Value")});
  table_->horizontalHeader()->setStretchLastSection(true);
  table_->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeToContents);
  table_->setAlternatingRowColors(true);
  table_->setEditTriggers(QAbstractItemView::NoEditTriggers);
  layout->addWidget(table_);

  connect(probe_, &ProbeClient::telemetryReady, this, &MonitorPage::onTelemetry);
  connect(probe_, &ProbeClient::healthChanged, this, &MonitorPage::onHealth);
  if (sensors_) {
    connect(sensors_, &SensorClient::telemetryReady, this, &MonitorPage::onTelemetry);
    connect(sensors_, &SensorClient::errorOccurred, this, [this](const QString& message) {
      status_->setText(tr("Native sensors: %1 — trying probe…").arg(message));
      probe_->fetchTelemetry();
    });
  }

  if (sensors_ && sensors_->isAvailable()) {
    QTimer::singleShot(400, sensors_, &SensorClient::fetchTelemetry);
  } else {
    QTimer::singleShot(800, probe_, &ProbeClient::fetchTelemetry);
  }
}

void MonitorPage::onHealth(bool online, const QJsonObject& info) {
  if (sensors_ && sensors_->isAvailable()) {
    status_->setText(tr("Native sensors active (LibreHardwareMonitor)"));
    return;
  }
  if (online) {
    const bool hwmon = info.value(QStringLiteral("hwmon")).toBool();
    status_->setText(hwmon ? tr("Probe online · hardware monitor active")
                           : tr("Probe online · build PcVerseHwMon for deep sensors"));
  } else {
    status_->setText(tr("Probe offline — attempting to start local probe service…"));
  }
}

void MonitorPage::onTelemetry(const QJsonObject& telemetry) {
  QJsonArray flat = telemetry.value(QStringLiteral("sensors_flat")).toArray();
  if (flat.isEmpty() && telemetry.contains(QStringLiteral("hardware"))) {
    const QJsonArray hw = telemetry.value(QStringLiteral("hardware")).toArray();
    for (const auto& h : hw) {
      const QJsonObject ho = h.toObject();
      const QString hw_name = ho.value(QStringLiteral("name")).toString();
      const QJsonArray sensors = ho.value(QStringLiteral("sensors")).toArray();
      for (const auto& s : sensors) {
        QJsonObject copy = s.toObject();
        copy.insert(QStringLiteral("_hardware"), hw_name);
        flat.append(copy);
      }
    }
  }

  table_->setRowCount(flat.size());
  int row = 0;
  for (const auto& v : flat) {
    const QJsonObject s = v.toObject();
    const QString hw = s.value(QStringLiteral("_hardware")).toString(s.value(QStringLiteral("hardware")).toString());
    const QString name = s.value(QStringLiteral("name")).toString();
    const QString type = s.value(QStringLiteral("type")).toString();
    const double value = s.value(QStringLiteral("value")).toDouble();
    const QString unit = s.value(QStringLiteral("unit")).toString();
    QString val = unit.isEmpty() ? QString::number(value, 'f', 1) : QString("%1 %2").arg(value, 0, 'f', 1).arg(unit);

    table_->setItem(row, 0, new QTableWidgetItem(hw));
    table_->setItem(row, 1, new QTableWidgetItem(name));
    table_->setItem(row, 2, new QTableWidgetItem(type));
    table_->setItem(row, 3, new QTableWidgetItem(val));
    ++row;
  }
  if (telemetry.value(QStringLiteral("_source")).toString().startsWith(QStringLiteral("native"))) {
    status_->setText(tr("%1 sensors live (native)").arg(row));
  } else {
    status_->setText(tr("%1 sensors live").arg(row));
  }
}
