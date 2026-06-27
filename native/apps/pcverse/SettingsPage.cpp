#include "SettingsPage.h"

#include "SettingsStore.h"

#include <QFormLayout>
#include <QLabel>
#include <QLineEdit>
#include <QPushButton>
#include <QVBoxLayout>

SettingsPage::SettingsPage(SettingsStore* store, QWidget* parent) : QWidget(parent), store_(store) {
  auto* layout = new QVBoxLayout(this);
  auto* intro = new QLabel(tr("Optional AI advisor — your API endpoint and model. Keys stay on this machine (QSettings)."));
  intro->setWordWrap(true);
  layout->addWidget(intro);

  auto* form = new QFormLayout();
  ai_url_ = new QLineEdit(store_->aiBaseUrl());
  ai_url_->setPlaceholderText(QStringLiteral("https://api.openai.com/v1"));
  ai_model_ = new QLineEdit(store_->aiModel());
  ai_model_->setPlaceholderText(QStringLiteral("gpt-4o"));
  ai_key_ = new QLineEdit(store_->aiApiKey());
  ai_key_->setEchoMode(QLineEdit::Password);
  ai_key_->setPlaceholderText(QStringLiteral("sk-… or local server token"));

  form->addRow(tr("API base URL"), ai_url_);
  form->addRow(tr("Model name"), ai_model_);
  form->addRow(tr("API key"), ai_key_);
  layout->addLayout(form);

  auto* save = new QPushButton(tr("Save settings"));
  connect(save, &QPushButton::clicked, this, &SettingsPage::save);
  layout->addWidget(save);

  saved_hint_ = new QLabel;
  layout->addWidget(saved_hint_);
  layout->addStretch();
}

void SettingsPage::save() {
  store_->setAiBaseUrl(ai_url_->text().trimmed());
  store_->setAiModel(ai_model_->text().trimmed());
  store_->setAiApiKey(ai_key_->text().trimmed());
  store_->sync();
  saved_hint_->setText(tr("Saved locally."));
}
