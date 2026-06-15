<?php

declare(strict_types=1);

$config = $config ?? require __DIR__ . '/../../config/app.php';
$titleFull = (isset($document_title) && is_string($document_title) && $document_title !== '')
    ? $document_title
    : (($title ?? 'PCVerse') . ' | ' . ($config['name_en'] ?? 'PCVerse'));
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}
if (empty($_SESSION['_pcverse_csrf'])) {
    $_SESSION['_pcverse_csrf'] = bin2hex(random_bytes(16));
}
$csrf = (string) $_SESSION['_pcverse_csrf'];
?>
<!DOCTYPE html>
<html lang="en" dir="ltr" data-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= e($titleFull) ?></title>
    <meta name="description" content="<?= e($meta_description ?? 'PCVerse — local PC laboratory. Probe, test, monitor, tune.') ?>">
    <meta name="theme-color" content="#0a0e17">
    <meta name="csrf-token" content="<?= e($csrf) ?>">
    <link rel="stylesheet" href="/assets/css/lab-shell.css?v=1.1.0">
</head>
<body class="pclab-body">
<?php if (empty($footer_minimal)): ?>
<div id="pcverse-update-banner" class="pcverse-update-banner" hidden aria-live="polite"></div>
<header class="pclab-header">
    <a href="/diagnostic" class="pclab-brand">PCVerse</a>
    <nav class="pclab-nav">
        <a href="/diagnostic">Lab</a>
        <a href="/lab/pc-test">PC Test</a>
        <a href="/lab/rgb-sync">RGB</a>
        <a href="/download">Download</a>
        <button type="button" class="pclab-nav-btn" id="dx-settings-open" aria-haspopup="dialog">Settings</button>
    </nav>
</header>
<?php endif; ?>
<main class="pclab-main">
    <?= $content ?? '' ?>
</main>
<?php if (empty($footer_minimal)): ?>
<footer class="pclab-footer">
    <span>PCVerse — runs locally on your PC · <a href="https://github.com/drmikecrypto/pc-lab-kit/blob/main/LICENSE" target="_blank" rel="noopener">Elastic License 2.0</a></span>
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
            <p id="dx-settings-status" class="dx-settings-status muted fs-xs" role="status"></p>
            <div class="dx-settings-actions">
                <button type="submit" class="dx-btn primary">Save</button>
                <button type="button" class="dx-btn ghost" id="dx-settings-clear-key">Remove saved key</button>
            </div>
        </form>
    </div>
</div>
<script defer src="/assets/js/diagnostic-settings.js?v=1.0.0"></script>
<script defer src="/assets/js/app-update.js?v=1.0.0"></script>
<?php endif; ?>
</body>
</html>
