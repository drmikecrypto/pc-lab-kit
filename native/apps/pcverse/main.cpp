#include "MainWindow.h"

#include <QApplication>
#include <QFile>
#include <QIcon>

int main(int argc, char* argv[]) {
  QApplication app(argc, argv);
  QApplication::setApplicationName(QStringLiteral("PCVerse"));
  QApplication::setOrganizationName(QStringLiteral("PCVerse"));
  QApplication::setApplicationVersion(QStringLiteral(PCVERSE_VERSION));

  MainWindow window;
  window.show();
  return app.exec();
}
