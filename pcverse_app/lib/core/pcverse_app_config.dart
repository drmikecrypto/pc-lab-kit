/// **PCVerse** local app configuration.
///
/// **Custom build:**
/// ```bash
/// flutter build apk --release --dart-define=PCVERSE_API_BASE=http://127.0.0.1:8080/api
/// flutter build apk --release --dart-define=PCVERSE_AGENT_BASE=http://127.0.0.1:18765
/// ```
///
/// API base must end with `/api` to match the PHP backend.
abstract final class PcverseAppConfig {
  static const String apiBase = String.fromEnvironment(
    'PCVERSE_API_BASE',
    defaultValue: 'http://127.0.0.1:8080/api',
  );

  /// پایهٔ HTTP لوکال **PCVerse Probe** (هم‌خوان با `config/diagnostic.php` → `windows_agent.local_port`).
  static const String windowsAgentBase = String.fromEnvironment(
    'PCVERSE_AGENT_BASE',
    defaultValue: 'http://127.0.0.1:18765',
  );

  /// مسیر لوگو روی سرور (پوشهٔ `public/` در ریپو).
  static const String publicLogoPath = '/pcverse.png';

  /// کلید SharedPreferences برای توکن API موبایل (پس از OTP؛ هدر `X-PCVERSE-Api-Token`).
  static const String mobileApiTokenPrefsKey = '_pcverse_mobile_api_token_v1';

  /// URL کامل فایل PNG برند PCVerse (فاویکون و هدر اپ).
  static String get logoUrl => '$siteOrigin$publicLogoPath';

  /// ریشهٔ سایت (بدون `/api`) — لینک وب، اشتراک‌گذاری، نوتیفیکیشن.
  static String get siteOrigin {
    final b = apiBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (b.endsWith('/api')) return b.substring(0, b.length - 4);
    return b.replaceAll(RegExp(r'/api/?$'), '');
  }
}
