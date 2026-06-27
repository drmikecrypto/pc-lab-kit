#include "ToolkitPage.h"

#include <QComboBox>
#include <QFile>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QLineEdit>
#include <QTableWidget>
#include <QTableWidgetItem>
#include <QVBoxLayout>

namespace {

QColor coverageColor(const QString& coverage) {
  if (coverage == QStringLiteral("live")) {
    return QColor(QStringLiteral("#3fb950"));
  }
  if (coverage == QStringLiteral("beta")) {
    return QColor(QStringLiteral("#58a6ff"));
  }
  if (coverage == QStringLiteral("import")) {
    return QColor(QStringLiteral("#d29922"));
  }
  if (coverage == QStringLiteral("orchestrate")) {
    return QColor(QStringLiteral("#a371f7"));
  }
  return QColor(QStringLiteral("#8b949e"));
}

}  // namespace

ToolkitPage::ToolkitPage(QWidget* parent) : QWidget(parent) {
  auto* layout = new QVBoxLayout(this);

  headline_ = new QLabel(tr("Loading toolkit catalog…"));
  headline_->setWordWrap(true);
  layout->addWidget(headline_);

  auto* filters = new QHBoxLayout();
  search_ = new QLineEdit();
  search_->setPlaceholderText(tr("Search tools…"));
  category_filter_ = new QComboBox();
  coverage_filter_ = new QComboBox();
  filters->addWidget(search_, 2);
  filters->addWidget(category_filter_, 1);
  filters->addWidget(coverage_filter_, 1);
  layout->addLayout(filters);

  table_ = new QTableWidget(0, 5, this);
  table_->setHorizontalHeaderLabels(
      {tr("Tool"), tr("Category"), tr("Module"), tr("Coverage"), tr("PCVerse")});
  table_->horizontalHeader()->setStretchLastSection(true);
  table_->horizontalHeader()->setSectionResizeMode(0, QHeaderView::ResizeToContents);
  table_->horizontalHeader()->setSectionResizeMode(1, QHeaderView::ResizeToContents);
  table_->horizontalHeader()->setSectionResizeMode(2, QHeaderView::ResizeToContents);
  table_->horizontalHeader()->setSectionResizeMode(3, QHeaderView::ResizeToContents);
  table_->setAlternatingRowColors(true);
  table_->setEditTriggers(QAbstractItemView::NoEditTriggers);
  table_->setSelectionBehavior(QAbstractItemView::SelectRows);
  layout->addWidget(table_, 1);

  connect(search_, &QLineEdit::textChanged, this, &ToolkitPage::applyFilters);
  connect(category_filter_, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &ToolkitPage::applyFilters);
  connect(coverage_filter_, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &ToolkitPage::applyFilters);

  loadCatalog();
}

void ToolkitPage::loadCatalog() {
  QFile file(QStringLiteral(":/tool_catalog.json"));
  if (!file.open(QIODevice::ReadOnly)) {
    headline_->setText(tr("Toolkit catalog missing — run scripts/export-tool-catalog.php"));
    return;
  }

  const auto doc = QJsonDocument::fromJson(file.readAll());
  if (!doc.isObject()) {
    headline_->setText(tr("Invalid toolkit catalog JSON"));
    return;
  }

  const QJsonObject root = doc.object();
  all_tools_ = root.value(QStringLiteral("tools")).toArray();
  categories_ = root.value(QStringLiteral("categories")).toObject();
  coverage_counts_ = root.value(QStringLiteral("summary")).toObject().value(QStringLiteral("coverage")).toObject();

  const QString headline = root.value(QStringLiteral("summary")).toObject().value(QStringLiteral("headline")).toString();
  headline_->setText(headline.isEmpty() ? tr("%1 tools in unified catalog").arg(all_tools_.size()) : headline);

  category_filter_->clear();
  category_filter_->addItem(tr("All categories"), QString());
  for (auto it = categories_.begin(); it != categories_.end(); ++it) {
    category_filter_->addItem(it.value().toString(), it.key());
  }

  coverage_filter_->clear();
  coverage_filter_->addItem(tr("All coverage"), QString());
  const QStringList order = {QStringLiteral("live"), QStringLiteral("beta"), QStringLiteral("import"),
                             QStringLiteral("orchestrate"), QStringLiteral("planned")};
  for (const auto& key : order) {
    const int count = coverage_counts_.value(key).toInt(0);
    if (count > 0) {
      coverage_filter_->addItem(QStringLiteral("%1 (%2)").arg(coverageLabel(key), QString::number(count)), key);
    }
  }

  populateTable(all_tools_);
}

QString ToolkitPage::coverageLabel(const QString& coverage) {
  if (coverage == QStringLiteral("live")) {
    return QObject::tr("Live");
  }
  if (coverage == QStringLiteral("beta")) {
    return QObject::tr("Beta");
  }
  if (coverage == QStringLiteral("import")) {
    return QObject::tr("Import");
  }
  if (coverage == QStringLiteral("orchestrate")) {
    return QObject::tr("Orchestrate");
  }
  return QObject::tr("Planned");
}

void ToolkitPage::populateTable(const QJsonArray& tools) {
  table_->setRowCount(tools.size());
  int row = 0;
  for (const auto& value : tools) {
    const QJsonObject tool = value.toObject();
    const QString category_key = tool.value(QStringLiteral("category")).toString();
    const QString category = categories_.value(category_key).toString(category_key);
    const QString coverage = tool.value(QStringLiteral("coverage")).toString();

    table_->setItem(row, 0, new QTableWidgetItem(tool.value(QStringLiteral("name")).toString()));
    table_->setItem(row, 1, new QTableWidgetItem(category));
    table_->setItem(row, 2, new QTableWidgetItem(tool.value(QStringLiteral("module")).toString()));
    auto* cov_item = new QTableWidgetItem(coverageLabel(coverage));
    cov_item->setForeground(coverageColor(coverage));
    table_->setItem(row, 3, cov_item);
    table_->setItem(row, 4, new QTableWidgetItem(tool.value(QStringLiteral("pcverse")).toString()));
    ++row;
  }
  table_->setRowCount(row);
}

void ToolkitPage::applyFilters() {
  const QString needle = search_->text().trimmed().toLower();
  const QString category = category_filter_->currentData().toString();
  const QString coverage = coverage_filter_->currentData().toString();

  QJsonArray filtered;
  for (const auto& value : all_tools_) {
    const QJsonObject tool = value.toObject();
    if (!category.isEmpty() && tool.value(QStringLiteral("category")).toString() != category) {
      continue;
    }
    if (!coverage.isEmpty() && tool.value(QStringLiteral("coverage")).toString() != coverage) {
      continue;
    }
    if (!needle.isEmpty()) {
      const QString hay = (tool.value(QStringLiteral("name")).toString() + QLatin1Char(' ') +
                           tool.value(QStringLiteral("pcverse")).toString() + QLatin1Char(' ') +
                           tool.value(QStringLiteral("id")).toString())
                              .toLower();
      if (!hay.contains(needle)) {
        continue;
      }
    }
    filtered.append(tool);
  }
  populateTable(filtered);
}
