#pragma once

#include <QMainWindow>

class MonitorPage;
class ProbeClient;
class ScanPage;
class SensorClient;
class SettingsPage;
class SettingsStore;
class ToolkitPage;
class UpdateController;

class MainWindow : public QMainWindow {
  Q_OBJECT

 public:
  explicit MainWindow(QWidget* parent = nullptr);

 private slots:
  void onUpdateChecked(const struct UpdateInfo& info);
  void onUpdateFailed(const QString& message);

 private:
  void applyStyle();
  void setupUpdateBanner();

  ProbeClient* probe_;
  SensorClient* sensors_;
  SettingsStore* settings_;
  UpdateController* updates_;
  class QTabWidget* tabs_;
  MonitorPage* monitor_;
  ScanPage* scan_;
  ToolkitPage* toolkit_;
  SettingsPage* settings_page_;
  class QFrame* update_banner_;
  class QLabel* update_label_;
  class QPushButton* update_btn_;
};
