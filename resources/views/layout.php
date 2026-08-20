<?php

declare(strict_types=1);

$config = $config ?? require __DIR__ . '/../../config/app.php';
$titleFull = (isset($document_title) && is_string($document_title) && $document_title !== '')
    ? $document_title
    : (($title ?? 'PC Lab Kit') . ' | ' . ($config['name_en'] ?? 'PC Lab Kit'));
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}
if (empty($_SESSION['pclab_csrf'])) {
    $_SESSION['pclab_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string) $_SESSION['pclab_csrf'];
?>
<!DOCTYPE html>
<html lang="en" dir="ltr" data-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= e($titleFull) ?></title>
    <meta name="description" content="<?= e($meta_description ?? 'PC Lab Kit — local PC laboratory. Probe, test, monitor, tune.') ?>">
    <meta name="theme-color" content="#0a0e17">
    <meta name="csrf-token" content="<?= e($csrf) ?>">
    <script>
    (function () {
      if (window.__TAURI_INTERNALS__ || window.__TAURI__) {
        document.documentElement.classList.add('pclab-desktop');
      }
    })();
    </script>
    <link rel="stylesheet" href="/assets/css/lab-shell.css?v=1.3.1">
</head>
<body class="pclab-body">
<?php if (empty($footer_minimal)): ?>
<div id="pclab-update-banner" class="pclab-update-banner" hidden aria-live="polite"></div>
<header class="pclab-header">
    <a href="/diagnostic" class="pclab-brand">PC Lab Kit</a>
    <nav class="pclab-nav">
        <a href="/diagnostic">Lab</a>
        <button type="button" class="pclab-nav-btn pclab-update-nav-btn" id="pclab-update-btn" hidden aria-label="Update available">Update</button>
        <button type="button" class="pclab-nav-btn" id="dx-settings-open" aria-haspopup="dialog">Settings</button>
    </nav>
</header>
<?php endif; ?>
<main class="pclab-main">
    <?= $content ?? '' ?>
</main>
<?php if (empty($footer_minimal)): ?>
<footer class="pclab-footer">
    <span>PC Lab Kit — runs locally on your PC · <a href="https://github.com/drmikecrypto/pc-lab-kit/blob/main/LICENSE" target="_blank" rel="noopener">Elastic License 2.0</a></span>
</footer>

<div id="dx-settings" class="dx-settings-overlay" hidden aria-hidden="true">
    <div class="dx-settings-panel" role="dialog" aria-modal="true" aria-labelledby="dx-settings-title">
        <div class="dx-settings-head">
            <h2 id="dx-settings-title">Settings</h2>
            <button type="button" class="dx-settings-close" id="dx-settings-close" aria-label="Close">×</button>
        </div>
        <p class="dx-settings-lead muted fs-sm">Optional AI advisor — stored locally in <code>storage/settings/local.json</code>. The lab works fully without it.</p>
        <form id="dx-settings-form" class="dx-settings-form">
            <label class="dx-settings-field">
                <span>Provider preset</span>
                <select id="dx-settings-preset" name="llm_preset">
                    <option value="openai">OpenAI</option>
                    <option value="anthropic">Anthropic-compatible</option>
                    <option value="ollama">Ollama (local)</option>
                    <option value="custom">Custom URL</option>
                </select>
            </label>
            <label class="dx-settings-field">
                <span>API key</span>
                <input type="password" id="dx-settings-key" name="llm_api_key" autocomplete="off" placeholder="sk-… (leave blank to keep current)">
                <small id="dx-settings-key-hint" class="muted"></small>
            </label>
            <label class="dx-settings-field">
                <span>API base URL</span>
                <input type="url" id="dx-settings-base" name="llm_base_url" placeholder="https://api.openai.com/v1">
            </label>
            <label class="dx-settings-field">
                <span>Model</span>
                <input type="text" id="dx-settings-model" name="llm_model" placeholder="gpt-4o-mini">
            </label>
            <label class="dx-settings-field">
                <span>Shop name (Assembly Certificate)</span>
                <input type="text" id="dx-settings-shop" name="shop_name" placeholder="PC Lab Kit" maxlength="80">
            </label>
            <p id="dx-settings-status" class="dx-settings-status muted fs-xs" role="status"></p>
            <div class="dx-settings-actions">
                <button type="submit" class="dx-btn primary">Save</button>
                <button type="button" class="dx-btn ghost" id="dx-settings-clear-key">Remove saved key</button>
            </div>
            <div class="dx-settings-update">
                <p class="muted fs-sm m-0">App updates come from GitHub Releases.</p>
                <p id="dx-settings-update-status" class="dx-settings-status muted fs-xs" role="status"></p>
                <button type="button" class="dx-btn ghost" id="dx-settings-check-update">Check for updates</button>
            </div>
        </form>
    </div>
</div>
<script defer src="/assets/js/diagnostic-settings.js?v=1.2.0"></script>
<script defer src="/assets/js/app-update.js?v=1.1.0"></script>
<?php endif; ?>
</body>
</html>
