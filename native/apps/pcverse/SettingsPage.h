#pragma once

#include <QWidget>

class SettingsStore;

class SettingsPage : public QWidget {
  Q_OBJECT

 public:
  explicit SettingsPage(SettingsStore* store, QWidget* parent = nullptr);

 private slots:
  void save();

 private:
  SettingsStore* store_;
  class QLineEdit* ai_url_;
  class QLineEdit* ai_model_;
  class QLineEdit* ai_key_;
  class QLabel* saved_hint_;
};
