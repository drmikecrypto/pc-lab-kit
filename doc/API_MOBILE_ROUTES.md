# Flutter app ↔ PHP API alignment

The mobile app uses `PcverseAppConfig.apiBase`, which **must end with `/api`** (e.g. `https://pcverse.ir/api`). All Dart paths below are appended to that base (so `/categories` → `GET /api/categories` on the server).

Headers: `X-App-Platform: mobile` (via `ApiClient` and diagnostic posts) so catalog and CSRF rules match `config/security.php` and `CsrfMiddleware`. After OTP login, the response `api_token` is stored in the app and sent on every request via the **`X-PCVERSE-Api-Token`** header (same key as `PcverseAppConfig.mobileApiTokenPrefsKey`); the backend hydrates the web `$_SESSION['user_id']` in `bootstrap` through `MobileApiAuthService::tryHydrateSession()`. App logout: `POST /api/auth/mobile-logout` with body `{ "token": "..." }`.

| App usage (Dart path) | HTTP | Server route (`app/bootstrap.php`) |
|----------------------|------|--------------------------------------|
| `/categories` | GET | `/api/categories` |
| `/parts/{slug}` | GET | `/api/parts/{slug}` (optional query: `q`, `brand`, `socket`, `selected_parts`, `vertical_gpu=1` to filter the GPU list in vertical layout) |
| `/part/{id}` | GET | `/api/part/{id}` |
| `/build/analyze` | POST | `/api/build/analyze` (body: `part_ids`; optional `ram_stick_count`, `igpu_only_ack`, `vertical_gpu`, **`fingerprint`**, **`reco_hint_state`**; response: `parts` + `parts_core`, **`simulator`** {`thermal`, `power`, **`expectations`** (FPS range), `upgrade_paths_fa`}, **`community_lab`** (anonymous 24h thermal aggregate), `recommendation` + `recommendation_hints[]` (simulator/community signals merged into the neural engine), `reco_meta`, `swap_suggestions[]`, `benchmark.benchmark_board`) |
| `/build/checkout-links` | POST | `/api/build/checkout-links` (web: `X-CSRF-TOKEN` header; app: `X-App-Platform: mobile` exempt from CSRF) |
| `/build/prefill/{token}` | GET | `/api/build/prefill/{token}` (shared build → parts + `missing` + `amin_note_fa` + `ram_stick_count` + `igpu_only_ack` + `vertical_gpu`) |
| `/home/showcase` | GET | `/api/home/showcase` (completed-build cards + `home_services_html` + `home_feature_pillars_html`) |
| `/home/showcase-live` | GET | `/api/home/showcase-live?tokens=...` (live pricing for home cards; web and app) |
| `/shop/checkout-options` | GET | `/api/shop/checkout-options` (shipping, transit insurance, payment, warranty options) |
| `/shop/my-orders` | GET | `/api/shop/my-orders` (cart orders for `?fp=`; with session cookie, same logic as profile) |
| `/shop/checkout-submit` | POST | `/api/shop/checkout-submit` (web: CSRF; JSON body with cart + address + selections; `cart` like `PCVerseCart.toApiCart()`; optional `express_handling`) |
| `/shop/cart-stock` | POST | `/api/shop/cart-stock` |
| `/shop/pay-wait-info` | GET | `/api/shop/pay-wait-info` — query: `order_id`, `key` (same `resume_key` from checkout) |
| `/shop/payment-retry` | POST | `/api/shop/payment-retry` — JSON body: `order_id`, `key`; response: `pending_gateway_url`, `resume_key`, `payment_deadline_at` |
| `/profile/custom-payables` | GET | `/api/profile/custom-payables` (after OTP; list of manual invoices; in app: **Custom bills & payments** page + `pending` count badge on profile tab and AppBar icon) |
| `/profile/custom-payable-pay` | POST | `/api/profile/custom-payable-pay` (body `{ "id": <bill_id> }`; response `pending_gateway_url` to open the payment gateway) |
| `/compare/list`, `/compare/add`, `/compare/clear` | GET/POST | `/api/compare/*` |
| `/wishlist/toggle` | POST | `/api/wishlist/toggle` |
| `/templates` | GET | `/api/templates` |
| `/referral/link` | GET | `/api/referral/link` |
| `/price-alerts` | GET | `/api/price-alerts` (rows matching `?fp=` **or** `phone` for the user linked to this fingerprint in `user_intelligence` after OTP) |
| `/price-alert` | POST | `/api/price-alert` (`phone`, `part_id`, `target_price`) |
| `/tribe/feed` | GET | `/api/tribe/feed` |
| `/tribe/like` | POST | `/api/tribe/like` |
| `/tribe/comment` | POST | `/api/tribe/comment` |
| `/tribe/comments/{id}` | GET | `/api/tribe/comments/{id}` |
| `/track/event`, `/track/intervention` | POST/GET | `/api/track/*` |
| `/push/register`, `/push/unregister`, `/push/config` | POST/GET | `/api/push/*` |
| `/notifications/pull`, `/notifications/list`, `/notifications/mark-read` | GET/POST | `/api/notifications/*` |
| `/app/update/check` | GET | `/api/app/update/check` |
| `/otp/send`, `/otp/verify` | POST | `/api/otp/send`, `/api/otp/verify` (verify response may include `api_token` and `api_token_expires_at` on success) |
| `/auth/mobile-logout` | POST | `/api/auth/mobile-logout` — revoke mobile token |
| `/feedback/active`, `/feedback/respond`, `/feedback/dismiss` | GET/POST | `/api/feedback/*` |

| `/diagnostic/lite`, `/diagnostic/full`, `/diagnostic/agent`, `/diagnostic/import`, … | POST/GET | `/api/diagnostic/*` — lite/full/agent responses include analysis plus **`consultant`**: `stance`, `headline_fa`, `honest_assessment_fa`, `horizons[]`, `catalog_angle_fa`, `catalog_highlight_fa` (when ⭐), **`catalog_picks[]`** (`part_id`, `name_fa`, `category_slug`, **`category_url`** e.g. `/parts/gpu`, `price_toman`, `is_partner`, `url`, `why_fa`), `neural_tags`; each **`upgrade_suggestions`** item has **`reason_fa`** and **`category_url`**. Server `diagnostic_*` telemetry: `health_score`, `gpu_score_bucket`, `thermal_band`, `vram_gb`, `upgrade_top_category`, `catalog_pick_ids`, `bottleneck_component`, … |
| `/diagnostic/rgb/catalog` | GET | `/api/diagnostic/rgb/catalog` (effect catalog for the web diagnostic lab) |
| `/diagnostic/config` | GET | `/api/diagnostic/config` |

`HumanGuardService` calls `${apiBase}/security/human/challenge` and `…/verify` (same as `/api/security/...`).

`DiagnosticService` uses `${PcverseAppConfig.apiBase}/diagnostic/...` (no duplicate `/api`).

When adding a new **authenticated** JSON route for mobile, either keep `X-App-Platform: mobile` or send CSRF (`X-CSRF-TOKEN`) per web rules.

### Diagnostic lite — `skip_app_download_pitch` and `X-PCVERSE-Client` header

The **`POST /api/diagnostic/lite`** response may include a boolean **`skip_app_download_pitch`**. When **`true`**, the web diagnostic lab must not show the “download the app” popup. The server sets this to **`true`** when the **`X-PCVERSE-Client: pcverse-flutter`** header (PHP: `HTTP_X_PCVERSE_CLIENT`) equals `pcverse-flutter`, so users who submitted the same report from the **official app** do not see a duplicate message in the browser tab.

The Flutter app sets this header when submitting heavy reports (e.g. `submitFullReport` / the matching diagnostic path in `DiagnosticService`). For any new endpoint with the same scenario, either send that header or return **`skip_app_download_pitch: true`** in the JSON so web and lab behavior stay aligned.

**Note:** Web popup logic also considers local signals beyond this field (Probe, deep-scan `localStorage`, thermal metrics in the response); full UI behavior is documented in the lab script itself.

Smoke tests (including `/api/tribe/comments/...`): `php scripts/smoke-test-routes.php <base-url>` or `PCVERSE_SMOKE_URL=...`.
