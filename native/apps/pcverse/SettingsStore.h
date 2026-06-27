#pragma once

#include <QSettings>
#include <QString>

class SettingsStore {
 public:
  SettingsStore();

  QString aiBaseUrl() const;
  QString aiModel() const;
  QString aiApiKey() const;

  void setAiBaseUrl(const QString& v);
  void setAiModel(const QString& v);
  void setAiApiKey(const QString& v);

  void sync();

 private:
  QSettings settings_;
};
