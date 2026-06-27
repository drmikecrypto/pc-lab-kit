#include "ScanPage.h"

#include "ProbeClient.h"

#include <QJsonDocument>
#include <QProgressBar>
#include <QPushButton>
#include <QTextEdit>
#include <QVBoxLayout>

ScanPage::ScanPage(ProbeClient* probe, QWidget* parent) : QWidget(parent), probe_(probe) {
  auto* layout = new QVBoxLayout(this);

  run_btn_ = new QPushButton(tr("Run full hardware scan"));
  layout->addWidget(run_btn_);

  progress_ = new QProgressBar();
  progress_->setRange(0, 0);
  progress_->setVisible(false);
  layout->addWidget(progress_);

  output_ = new QTextEdit();
  output_->setReadOnly(true);
  output_->setPlaceholderText(tr("Probe scan JSON appears here — CPU, GPU, memory, storage, thermals…"));
  layout->addWidget(output_);

  connect(run_btn_, &QPushButton::clicked, this, &ScanPage::runScan);
  connect(probe_, &ProbeClient::scanReady, this, &ScanPage::onScan);
  connect(probe_, &ProbeClient::scanFailed, this, &ScanPage::onScanFailed);
}

void ScanPage::runScan() {
  progress_->setVisible(true);
  run_btn_->setEnabled(false);
  output_->clear();
  probe_->fetchProbeScan();
}

void ScanPage::onScan(const QJsonObject& scan) {
  progress_->setVisible(false);
  run_btn_->setEnabled(true);
  output_->setPlainText(QString::fromUtf8(QJsonDocument(scan).toJson(QJsonDocument::Indented)));
}

void ScanPage::onScanFailed(const QString& message) {
  progress_->setVisible(false);
  run_btn_->setEnabled(true);
  output_->setPlainText(message);
}
