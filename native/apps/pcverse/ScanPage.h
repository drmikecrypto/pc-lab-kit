#pragma once

#include <QWidget>

class ProbeClient;

class ScanPage : public QWidget {
  Q_OBJECT

 public:
  explicit ScanPage(ProbeClient* probe, QWidget* parent = nullptr);

 private slots:
  void runScan();
  void onScan(const QJsonObject& scan);
  void onScanFailed(const QString& message);

 private:
  ProbeClient* probe_;
  class QPushButton* run_btn_;
  class QProgressBar* progress_;
  class QTextEdit* output_;
};
