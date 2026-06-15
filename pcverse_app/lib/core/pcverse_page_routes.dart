import 'package:flutter/material.dart';

/// نام مسیرها باید با [PcverseNavigatorObserver] و [IntelligenceService.setCurrentRoute] یکسان باشند.
abstract final class PcverseRouteNames {
  static const compare = 'compare';
  static const categoriesHub = 'categories_hub';
  static const diagnostic = 'diagnostic';
  static const pcTest = 'pc_test';
  static const rgbLab = 'rgb_lab';
  static const labHub = 'lab_hub';
  static const qrScan = 'qr_scan';
  static const shopCart = 'shop_cart';
  static const shopCheckout = 'shop_checkout';
  static const shopPayWait = 'shop_pay_wait';
  static const shopOrders = 'shop_orders';
  /// قبض‌های دستی (VIP) — `GET/POST /api/profile/custom-payable*`
  static const customPayables = 'custom_payables';
  static String category(String slug) => 'category/$slug';
  static String part(int id) => 'part/$id';
  static String partSelect(String categorySlug) => 'part_select/$categorySlug';
}

/// مسیرهای مودال با پیشوند `modal/` تا [PcverseNavigatorObserver] آن‌ها را با صفحهٔ پایه اشتباه نگیرد.
abstract final class PcverseModalRouteNames {
  static const templatesSheet = 'modal/templates_sheet';
  static const templateReplaceConfirm = 'modal/template_replace_confirm';
  static const qrScannerInfo = 'modal/qr_scanner_info';
  static const checkoutSheet = 'modal/checkout_sheet';
  static const builderResetConfirm = 'modal/builder_reset_confirm';
  static const tribeComment = 'modal/tribe_comment';
}

/// [MaterialPageRoute] با [RouteSettings.name] برای ناوبری تلمتری.
MaterialPageRoute<T> pcverseMaterialRoute<T>({
  required String name,
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
}) {
  return MaterialPageRoute<T>(
    settings: RouteSettings(name: name),
    fullscreenDialog: fullscreenDialog,
    builder: builder,
  );
}
