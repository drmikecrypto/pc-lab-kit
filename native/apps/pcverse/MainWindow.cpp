#include "MainWindow.h"

#include "MonitorPage.h"
#include "ProbeClient.h"
#include "ScanPage.h"
#include "SensorClient.h"
#include "SettingsPage.h"
#include "SettingsStore.h"
#include "ToolkitPage.h"
#include "UpdateController.h"

#include <QApplication>
#include <QDesktopServices>
#include <QFile>
#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QPushButton>
#include <QStatusBar>
#include <QTabWidget>
#include <QUrl>
#include <QVBoxLayout>

MainWindow::MainWindow(QWidget* parent) : QMainWindow(parent) {
  setWindowTitle(QStringLiteral("PCVerse — Local PC Laboratory"));
  resize(1180, 760);

  settings_ = new SettingsStore();
  probe_ = new ProbeClient(this);
  sensors_ = new SensorClient(this);
  updates_ = new UpdateController(this);

  auto* central = new QWidget(this);
  auto* root = new QVBoxLayout(central);

  setupUpdateBanner();
  root->addWidget(update_banner_);

  tabs_ = new QTabWidget();
  monitor_ = new MonitorPage(probe_, sensors_, this);
  scan_ = new ScanPage(probe_, this);
  toolkit_ = new ToolkitPage(this);
  settings_page_ = new SettingsPage(settings_, this);
  tabs_->addTab(monitor_, tr("Monitor"));
  tabs_->addTab(scan_, tr("Full scan"));
  tabs_->addTab(toolkit_, tr("Toolkit"));
  tabs_->addTab(settings_page_, tr("Settings"));
  root->addWidget(tabs_, 1);

  setCentralWidget(central);

  statusBar()->showMessage(tr("PCVerse %1 — native desktop").arg(QStringLiteral(PCVERSE_VERSION)));

  connect(updates_, &UpdateController::updateChecked, this, &MainWindow::onUpdateChecked);
  connect(updates_, &UpdateController::checkFailed, this, &MainWindow::onUpdateFailed);
  connect(tabs_, &QTabWidget::currentChanged, this, [this](int idx) {
    if (tabs_->widget(idx) == monitor_) {
      if (sensors_->isAvailable()) {
        sensors_->fetchTelemetry();
      } else {
        probe_->fetchTelemetry();
      }
    }
  });

  applyStyle();
  updates_->checkForUpdates();
}

void MainWindow::setupUpdateBanner() {
  update_banner_ = new QFrame();
  update_banner_->setObjectName(QStringLiteral("updateBanner"));
  update_banner_->setVisible(false);
  auto* row = new QHBoxLayout(update_banner_);
  update_label_ = new QLabel;
  update_btn_ = new QPushButton(tr("Download update"));
  connect(update_btn_, &QPushButton::clicked, this, [this]() {
    const QString url = update_btn_->property("url").toString();
    if (!url.isEmpty()) {
      QDesktopServices::openUrl(QUrl(url));
    }
  });
  row->addWidget(update_label_, 1);
  row->addWidget(update_btn_);
}

void MainWindow::onUpdateChecked(const UpdateInfo& info) {
  if (!info.update_available) {
    update_banner_->setVisible(false);
    return;
  }
  update_label_->setText(tr("PCVerse %1 is available (you have %2).")
                             .arg(info.latest_version, QStringLiteral(PCVERSE_VERSION)));
  QString url = info.release_url;
#ifdef Q_OS_WIN
  if (!info.download_windows.isEmpty()) {
    url = info.download_windows;
  }
#elif defined(Q_OS_LINUX)
  if (!info.download_linux.isEmpty()) {
    url = info.download_linux;
  }
#endif
  update_btn_->setProperty("url", url);
  update_banner_->setVisible(true);
}

void MainWindow::onUpdateFailed(const QString& message) {
  statusBar()->showMessage(tr("Update check: %1").arg(message), 8000);
}

void MainWindow::applyStyle() {
  QFile f(QStringLiteral(":/dark.qss"));
  if (f.open(QIODevice::ReadOnly)) {
    qApp->setStyleSheet(QString::fromUtf8(f.readAll()));
  }
}
