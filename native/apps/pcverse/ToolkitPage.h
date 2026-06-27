#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QWidget>

class ToolkitPage : public QWidget {
  Q_OBJECT

 public:
  explicit ToolkitPage(QWidget* parent = nullptr);

 private slots:
  void applyFilters();

 private:
  void loadCatalog();
  void populateTable(const QJsonArray& tools);
  static QString coverageLabel(const QString& coverage);

  class QLabel* headline_;
  class QLineEdit* search_;
  class QComboBox* category_filter_;
  class QComboBox* coverage_filter_;
  class QTableWidget* table_;
  QJsonArray all_tools_;
  QJsonObject categories_;
  QJsonObject coverage_counts_;
};
