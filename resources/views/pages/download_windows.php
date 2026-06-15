<?php
/** @var array $agent */
/** @var array $downloads */
/** @var bool $lab_ready */
/** @var bool $probe_ready */
$zipUrl = $agent['download_url'] ?? '/download/pcverse-probe.zip';
$labZip = $downloads['lab_windows_zip'] ?? '/download/pcverse-lab-windows.zip';
$port = (int) ($agent['local_port'] ?? 18765);
?>
<link rel="stylesheet" href="/assets/css/diagnostic-lab.css?v=1.0.1">
<link rel="stylesheet" href="/assets/css/download-pages.css?v=1.0.0">

<div class="dl-hero dl-hero--windows">
    <div class="container">
        <p class="dl-hero__kicker"><a href="/download">← All downloads</a></p>
        <h1 class="dl-hero__title">PCVerse for <span class="dx-gradient">Windows</span></h1>
        <p class="dl-hero__lead">Full stack: web lab + PCVerse Probe for deep scans, RGB, and safe tuning — all local.</p>
    </div>
</div>

<div class="container py-10">
    <div class="grid grid-cols-1 md:grid-cols-2 gap-10 mb-12">
        <div class="glass-effect p-8 border-radius-24">
            <h2 class="fs-3 fw-800 mb-4">PCVerse Probe (recommended)</h2>
            <ol class="muted" style="line-height: 2; padding-left: 1.2rem;">
                <li>Download and extract the ZIP.</li>
                <li>Run <code>Start-PCVerseProbe.bat</code>.</li>
                <li>Keep the window open — agent on <strong>127.0.0.1:<?= (int) $port ?></strong>.</li>
            </ol>
            <?php if ($probe_ready): ?>
            <a href="<?= e($zipUrl) ?>" class="dx-btn primary btn-lg mt-4" download>Download pcverse-probe-windows.zip</a>
            <?php else: ?>
            <p class="muted mt-4">Build the probe bundle: <code>scripts/build-agent-bundle.ps1</code></p>
            <?php endif; ?>
        </div>
        <div class="glass-effect p-8 border-radius-24">
            <h2 class="fs-3 fw-800 mb-4">Full lab (no Git)</h2>
            <ol class="muted" style="line-height: 2; padding-left: 1.2rem;">
                <li>Extract the lab ZIP anywhere.</li>
                <li>Run <code>scripts\install.ps1</code> then <code>scripts\start.ps1</code>.</li>
                <li>Open <strong>http://127.0.0.1:8080/diagnostic</strong>.</li>
            </ol>
            <?php if ($lab_ready): ?>
            <a href="<?= e($labZip) ?>" class="dx-btn primary btn-lg mt-4" download>Download pcverse-lab-windows.zip</a>
            <?php else: ?>
            <p class="muted mt-4">Build: <code>scripts/build-lab-windows.ps1</code> or use Git clone + <code>install.ps1</code>.</p>
            <?php endif; ?>
        </div>
    </div>

    <div class="glass-effect p-8 border-radius-24 mb-12">
        <h2 class="fs-3 fw-800 mb-4">Connect Probe to the lab</h2>
        <ul class="muted" style="line-height: 2; padding-left: 1.2rem;">
            <li>Start the lab (<code>start.ps1</code>) and Probe (<code>Start-PCVerseProbe.bat</code>).</li>
            <li>In the lab, open <strong>Connect</strong> under full scan — or load a JSON report.</li>
            <li>Optional imports: HWiNFO CSV, CapFrameX JSON, CPU-Z TXT.</li>
        </ul>
        <p class="mt-3">Probe v4 · RGB Lab · PcVerseHwMon · OpenRGB in <code>tools/OpenRGB/</code></p>
    </div>

    <div class="text-center">
        <p class="muted"><a href="/download/linux-mac">Linux or macOS? → separate download</a> · <a href="/diagnostic">Open lab</a></p>
    </div>
</div>
