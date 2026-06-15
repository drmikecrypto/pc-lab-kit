<?php
/** @var bool $windows_ready */
/** @var bool $linux_ready */
/** @var string $windows_url */
/** @var string $linux_url */
/** @var string|null $suggested_platform */
?>
<link rel="stylesheet" href="/assets/css/diagnostic-lab.css?v=1.0.1">
<link rel="stylesheet" href="/assets/css/download-pages.css?v=1.0.1">

<div class="dl-hero">
    <div class="container">
        <h1 class="dl-hero__title">Download <span class="dx-gradient">PCVerse</span></h1>
        <p class="dl-hero__lead">One click. One installer. Everything included — pick your platform and run setup.</p>
    </div>
</div>

<div class="container dl-grid dl-grid--two">
    <article class="dl-card dl-card--windows<?= ($suggested_platform ?? null) === 'windows' ? ' dl-card--suggested' : '' ?>">
        <div class="dl-card__badge">Windows 64-bit</div>
        <h2>PCVerse Setup</h2>
        <p class="muted">Full lab + PCVerse Probe, bundled PHP, desktop shortcut — no Git, no manual steps.</p>
        <ol class="dl-card__steps">
            <li>Download <strong>PCVerse-Setup-Windows-x64.exe</strong></li>
            <li>Run the installer · choose folder · optional desktop shortcut</li>
            <li>Open PCVerse — lab runs at <code>127.0.0.1:8080</code></li>
        </ol>
        <div class="dl-card__actions">
            <?php if ($windows_ready): ?>
            <a href="<?= e($windows_url) ?>" class="dx-btn primary dl-btn-xl" download>Download for Windows</a>
            <?php else: ?>
            <span class="dx-btn primary dl-btn-xl dl-btn--disabled">Windows installer building…</span>
            <?php endif; ?>
        </div>
    </article>

    <article class="dl-card dl-card--unix<?= ($suggested_platform ?? null) === 'linux' ? ' dl-card--suggested' : '' ?>">
        <div class="dl-card__badge">Linux 64-bit</div>
        <h2>PCVerse Setup</h2>
        <p class="muted">Complete diagnostic lab with guided install, folder picker, and optional desktop shortcut.</p>
        <ol class="dl-card__steps">
            <li>Download <strong>PCVerse-Setup-Linux-x64.run</strong></li>
            <li><code>chmod +x</code> then double-click or run in terminal</li>
            <li>Choose install folder · launch from shortcut or <code>PCVerse</code></li>
        </ol>
        <div class="dl-card__actions">
            <?php if ($linux_ready): ?>
            <a href="<?= e($linux_url) ?>" class="dx-btn primary dl-btn-xl" download>Download for Linux</a>
            <?php else: ?>
            <span class="dx-btn primary dl-btn-xl dl-btn--disabled">Linux installer building…</span>
            <?php endif; ?>
        </div>
    </article>
</div>

<div class="container dl-foot">
    <p class="muted fs-sm text-center"><a href="/diagnostic">Already installed? Open the lab →</a></p>
</div>
