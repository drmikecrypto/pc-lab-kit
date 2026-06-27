#include "SettingsStore.h"

SettingsStore::SettingsStore() : settings_(QStringLiteral("PCVerse"), QStringLiteral("pcverse-native")) {}

QString SettingsStore::aiBaseUrl() const {
  return settings_.value(QStringLiteral("ai/base_url"), QStringLiteral("https://api.openai.com/v1")).toString();
}

QString SettingsStore::aiModel() const {
  return settings_.value(QStringLiteral("ai/model"), QStringLiteral("gpt-4o-mini")).toString();
}

QString SettingsStore::aiApiKey() const {
  return settings_.value(QStringLiteral("ai/api_key")).toString();
}

void SettingsStore::setAiBaseUrl(const QString& v) { settings_.setValue(QStringLiteral("ai/base_url"), v); }
void SettingsStore::setAiModel(const QString& v) { settings_.setValue(QStringLiteral("ai/model"), v); }
void SettingsStore::setAiApiKey(const QString& v) { settings_.setValue(QStringLiteral("ai/api_key"), v); }

void SettingsStore::sync() { settings_.sync(); }
