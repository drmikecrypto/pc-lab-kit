# Flutter app ↔ PHP API alignment

The mobile app uses `PcverseAppConfig.apiBase`, which **must end with `/api`** (e.g. `https://pcverse.ir/api`). All Dart paths below are appended to that base (so `/categories` → `GET /api/categories` on the server).

Headers: `X-App-Platform: mobile` (via `ApiClient` and diagnostic posts) so catalog and CSRF rules match `config/security.php` and `CsrfMiddleware`. پس از ورود OTP، پاسخ `api_token` در اپ ذخیره می‌شود و روی همهٔ درخواست‌ها هدر **`X-PCVERSE-Api-Token`** (هم‌نام `PcverseAppConfig.mobileApiTokenPrefsKey`) ارسال می‌گردد؛ بک‌اند در `bootstrap` با `MobileApiAuthService::tryHydrateSession()` همان `$_SESSION['user_id']` وب را پر می‌کند. خروج از اپ: `POST /api/auth/mobile-logout` با بدنهٔ `{ "token": "..." }`.

| App usage (Dart path) | HTTP | Server route (`app/bootstrap.php`) |
|----------------------|------|--------------------------------------|
| `/categories` | GET | `/api/categories` |
| `/parts/{slug}` | GET | `/api/parts/{slug}` (اختیاری: `q`, `brand`, `socket`, `selected_parts`، `vertical_gpu=1` برای فیلتر لیست GPU در حالت عمودی) |
| `/part/{id}` | GET | `/api/part/{id}` |
| `/build/analyze` | POST | `/api/build/analyze` (بدنه: `part_ids`؛ اختیاری `ram_stick_count`، `igpu_only_ack`، `vertical_gpu`، **`fingerprint`**، **`reco_hint_state`**؛ پاسخ: `parts` + `parts_core`، **`simulator`** {`thermal`, `power`, **`expectations`** (بازهٔ FPS)، `upgrade_paths_fa`}، **`community_lab`** (تجمیع حرارتی ۲۴س ناشناس)، `recommendation` + `recommendation_hints[]` (سیگنال شبیه‌ساز/جامعه در موتور عصبی ادغام)، `reco_meta`، `swap_suggestions[]`، `benchmark.benchmark_board`) |
| `/build/checkout-links` | POST | `/api/build/checkout-links` (وب: هدر `X-CSRF-TOKEN`؛ اپ: `X-App-Platform: mobile` معاف از CSRF) |
| `/build/prefill/{token}` | GET | `/api/build/prefill/{token}` (اسمبل اشتراکی → قطعات + `missing` + `amin_note_fa` + `ram_stick_count` + `igpu_only_ack` + `vertical_gpu`) |
| `/home/showcase` | GET | `/api/home/showcase` (کارت‌های «اسمبل‌های انجام‌شده» + `home_services_html` + `home_feature_pillars_html`) |
| `/home/showcase-live` | GET | `/api/home/showcase-live?tokens=...` (قیمت زندهٔ کارت‌های خانه؛ وب و اپ) |
| `/shop/checkout-options` | GET | `/api/shop/checkout-options` (گزینه‌های ارسال، بیمه حمل، پرداخت، گارانتی) |
| `/shop/my-orders` | GET | `/api/shop/my-orders` (سفارش‌های سبد برای `?fp=`؛ با کوکی نشست همان منطق پروفایل) |
| `/shop/checkout-submit` | POST | `/api/shop/checkout-submit` (وب: CSRF؛ بدنه JSON سبد + آدرس + انتخاب‌ها؛ `cart` مثل `PCVerseCart.toApiCart()`؛ `express_handling` اختیاری) |
| `/shop/cart-stock` | POST | `/api/shop/cart-stock` |
| `/shop/pay-wait-info` | GET | `/api/shop/pay-wait-info` — query: `order_id`، `key` (همان `resume_key` از checkout) |
| `/shop/payment-retry` | POST | `/api/shop/payment-retry` — بدنه JSON: `order_id`، `key`؛ پاسخ: `pending_gateway_url`، `resume_key`، `payment_deadline_at` |
| `/profile/custom-payables` | GET | `/api/profile/custom-payables` (پس از OTP؛ لیست قبض‌های دستی؛ در اپ: صفحهٔ **قبض و پرداخت ویژه** + نشان تعداد `pending` روی تب پروفایل و آیکن AppBar) |
| `/profile/custom-payable-pay` | POST | `/api/profile/custom-payable-pay` (بدنه `{ "id": <قبض> }`؛ پاسخ `pending_gateway_url` برای باز کردن درگاه) |
| `/compare/list`, `/compare/add`, `/compare/clear` | GET/POST | `/api/compare/*` |
| `/wishlist/toggle` | POST | `/api/wishlist/toggle` |
| `/templates` | GET | `/api/templates` |
| `/referral/link` | GET | `/api/referral/link` |
| `/price-alerts` | GET | `/api/price-alerts` (ردیف‌هایی با `?fp=` **یا** `phone` همان کاربری که پس از OTP به این fingerprint در `user_intelligence` وصل شده) |
| `/price-alert` | POST | `/api/price-alert` (`phone`, `part_id`, `target_price`) |
| `/tribe/feed` | GET | `/api/tribe/feed` |
| `/tribe/like` | POST | `/api/tribe/like` |
| `/tribe/comment` | POST | `/api/tribe/comment` |
| `/tribe/comments/{id}` | GET | `/api/tribe/comments/{id}` |
| `/track/event`, `/track/intervention` | POST/GET | `/api/track/*` |
| `/push/register`, `/push/unregister`, `/push/config` | POST/GET | `/api/push/*` |
| `/notifications/pull`, `/notifications/list`, `/notifications/mark-read` | GET/POST | `/api/notifications/*` |
| `/app/update/check` | GET | `/api/app/update/check` |
| `/otp/send`, `/otp/verify` | POST | `/api/otp/send`, `/api/otp/verify` (پاسخ verify در صورت موفقیت ممکن است `api_token` و `api_token_expires_at` داشته باشد) |
| `/auth/mobile-logout` | POST | `/api/auth/mobile-logout` — باطل‌کردن توکن موبایل |
| `/feedback/active`, `/feedback/respond`, `/feedback/dismiss` | GET/POST | `/api/feedback/*` |

| `/diagnostic/lite`, `/diagnostic/full`, `/diagnostic/agent`, `/diagnostic/import`, … | POST/GET | `/api/diagnostic/*` — پاسخ lite/full/agent علاوه بر تحلیل شامل **`consultant`**: `stance`, `headline_fa`, `honest_assessment_fa`, `horizons[]`, `catalog_angle_fa`, `catalog_highlight_fa` (در صورت ⭐)، **`catalog_picks[]`** (`part_id`, `name_fa`, `category_slug`, **`category_url`** مثل `/parts/gpu`, `price_toman`, `is_partner`, `url`, `why_fa`)، `neural_tags`؛ هر آیتم **`upgrade_suggestions`** فیلدهای **`reason_fa`** و **`category_url`** دارد. تلمتری `diagnostic_*` روی سرور: `health_score`, `gpu_score_bucket`, `thermal_band`, `vram_gb`, `upgrade_top_category`, `catalog_pick_ids`, `bottleneck_component`, … |
| `/diagnostic/rgb/catalog` | GET | `/api/diagnostic/rgb/catalog` (کاتالوگ افکت برای لاب وب) |
| `/diagnostic/config` | GET | `/api/diagnostic/config` |

`HumanGuardService` calls `${apiBase}/security/human/challenge` and `…/verify` (same as `/api/security/...`).

`DiagnosticService` uses `${PcverseAppConfig.apiBase}/diagnostic/...` (no duplicate `/api`).

When adding a new **authenticated** JSON route for mobile, either keep `X-App-Platform: mobile` or send CSRF (`X-CSRF-TOKEN`) per web rules.

### Diagnostic lite — `skip_app_download_pitch` و هدر `X-PCVERSE-Client`

پاسخ **`POST /api/diagnostic/lite`** می‌تواند فیلد بولی **`skip_app_download_pitch`** داشته باشد. اگر **`true`** باشد، لاب تشخیص وب نباید پاپ‌آپ «دانلود اپ» را نشان دهد؛ سرور این مقدار را وقتی هدر **`X-PCVERSE-Client: pcverse-flutter`** (در PHP: `HTTP_X_PCVERSE_CLIENT`) برابر `pcverse-flutter` باشد **`true`** برمی‌گرداند تا کاربری که همان گزارش را از **اپ رسمی** فرستاده، در تب مرورگر پیام تکراری نبیند.

اپ Flutter روی ارسال گزارش سنگین (مثلاً `submitFullReport` / مسیر diagnostic متناظر در `DiagnosticService`) این هدر را ست می‌کند. برای هر endpoint جدیدی که همان سناریو را دارد، یا همان هدر را بفرستید یا در JSON پاسخ **`skip_app_download_pitch: true`** قرار دهید تا فرانت و لاب یکسان بمانند.

**یادآوری:** منطق نمایش پاپ‌آپ در وب علاوه بر این فیلد، سیگنال‌های محلی (Probe، `localStorage` اسکن عمیق، متریک دما در پاسخ) را هم در نظر می‌گیرد؛ مستند کامل UI در همان اسکریپت لاب است.

Smoke tests (including `/api/tribe/comments/...`): `php scripts/smoke-test-routes.php <base-url>` or `PCVERSE_SMOKE_URL=...`.
