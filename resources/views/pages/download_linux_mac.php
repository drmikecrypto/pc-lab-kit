<?php
/** @var array $downloads */
/** @var bool $lab_ready */
$tarUrl = $downloads['lab_unix_tar'] ?? '/download/pcverse-lab-linux-mac.tar.gz';
?>
<link rel="stylesheet" href="/assets/css/diagnostic-lab.css?v=1.0.1">
<link rel="stylesheet" href="/assets/css/download-pages.css?v=1.0.0">

<div class="dl-hero dl-hero--unix">
    <div class="container">
        <p class="dl-hero__kicker"><a href="/download">← All downloads</a></p>
        <h1 class="dl-hero__title">PCVerse for <span class="dx-gradient">Linux &amp; macOS</span></h1>
        <p class="dl-hero__lead">Extract, run <code>./scripts/install.sh</code>, then <code>./scripts/start.sh</code>. The full lab UI runs in your browser — no Docker, no cloud account.</p>
    </div>
</div>

<div class="container py-10">
    <div class="grid grid-cols-1 md:grid-cols-2 gap-10 mb-12">
        <div class="glass-effect p-8 border-radius-24">
            <h2 class="fs-3 fw-800 mb-4">1. Download the lab bundle</h2>
            <?php if ($lab_ready): ?>
            <p class="muted mb-4">Includes source, install scripts, benchmark data, and the diagnostic UI. <code>install.sh</code> auto-downloads PHP and Composer on first run.</p>
            <a href="<?= e($tarUrl) ?>" class="dx-btn primary btn-lg mt-2" download>Download pcverse-lab-linux-mac.tar.gz</a>
            <?php else: ?>
            <p class="muted mb-4">Release archive not bundled in this tree yet. Clone from GitHub or run <code>scripts/build-lab-unix.sh</code> to create the tarball.</p>
            <pre class="dl-code-block">git clone https://github.com/YOUR_ORG/pcverse.git
cd pcverse
chmod +x scripts/install.sh scripts/start.sh
./scripts/install.sh
./scripts/start.sh</pre>
            <?php endif; ?>
        </div>
        <div class="glass-effect p-8 border-radius-24">
            <h2 class="fs-3 fw-800 mb-4">2. Open the lab</h2>
            <ol class="muted" style="line-height: 2; padding-left: 1.2rem;">
                <li>After install, run <code>./scripts/start.sh</code> (optional port: <code>./scripts/start.sh 8080</code>).</li>
                <li>Open <strong>http://127.0.0.1:8080/diagnostic</strong> in your browser.</li>
                <li>Optional: add an AI API key via <strong>Settings</strong> in the header.</li>
            </ol>
            <a href="/diagnostic" class="dx-btn ghost mt-4">Open lab (if already running)</a>
        </div>
    </div>

    <div class="glass-effect p-8 border-radius-24 mb-12">
        <h2 class="fs-3 fw-800 mb-4">Requirements</h2>
        <div class="d-flex flex-wrap gap-2 mb-4">
            <span class="dx-tool-chip">PHP 8.2+</span>
            <span class="dx-tool-chip">sqlite · curl · mbstring · json</span>
            <span class="dx-tool-chip">Composer</span>
        </div>
        <p class="muted mb-0">On Ubuntu/Debian: <code>sudo apt install php-cli php-sqlite3 php-curl php-mbstring composer</code><br>
        On macOS with Homebrew: <code>brew install php composer</code></p>
    </div>

    <div class="glass-effect p-8 border-radius-24 mb-12">
        <h2 class="fs-3 fw-800 mb-4">Linux / macOS today</h2>
        <p class="muted">The web lab, quick quiz, community benchmarks, history, and file imports work on Linux and macOS. <strong>PCVerse Probe</strong> (live sensors, RGB, OC apply) is Windows-only for now — use report import or run the lab on Windows for deep scans.</p>
        <p class="mt-3"><a href="/download/windows">Looking for Windows + Probe? →</a></p>
    </div>
</div>
