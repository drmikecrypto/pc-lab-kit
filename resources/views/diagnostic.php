<?php
/** @var array $config */
$cfg = $config ?? [];
$steps = $cfg['lite_steps'] ?? [];
$tools = $cfg['pro_tools'] ?? [];
$probeDl = (string) (($cfg['windows_agent'] ?? [])['download_url'] ?? '/download/pcverse-windows-x64');
$importFormats = $cfg['import_formats'] ?? [];
$product = $cfg['product'] ?? [];
$toolKit = new \App\Services\DiagnosticToolCatalogService();
$toolTotal = $toolKit->total();
?>
<link rel="stylesheet" href="/assets/css/diagnostic-shell.css?v=1.0.1">
<link rel="stylesheet" href="/assets/css/diagnostic-toolkit.css?v=1.0.0">
<link rel="stylesheet" href="/assets/css/diagnostic-pulse.css?v=1.0.0">
<link rel="stylesheet" href="/assets/css/diagnostic-lab.css?v=1.6.6">
<link rel="stylesheet" href="/assets/css/diagnostic-live.css?v=1.4.1">
<link rel="stylesheet" href="/assets/css/diagnostic-telemetry.css?v=1.5.0">
<link rel="stylesheet" href="/assets/css/diagnostic-rgb.css?v=1.0.0">

<div class="container dx-shell">

    <header class="dx-shell-hero">
        <div class="dx-shell-hero__inner">
            <p class="dx-shell-eyebrow">PCVerse diagnostic lab</p>
            <h1 class="dx-shell-title">Check your PC in minutes</h1>
            <p class="dx-shell-lead"><?= e($product['full_tagline'] ?? 'Quick health quiz in the browser · deep scan with PCVerse Probe · history and telemetry on your machine.') ?></p>
            <div class="dx-shell-meta">
                <span class="dx-shell-pill dx-shell-pill--live">Local only</span>
                <span class="dx-shell-pill"><?= (int) $toolTotal ?> tools unified</span>
                <button type="button" class="dx-shell-pill dx-shell-pill--btn" id="dx-settings-open-inline" aria-haspopup="dialog">AI advisor</button>
                <span class="dx-shell-pill" id="dx-live-updated">Loading…</span>
            </div>
        </div>
    </header>

    <section class="dx-pulse-hidden" id="dx-intelligence-pulse" aria-hidden="true">
        <div class="dx-pulse-bridge">
            <article class="dx-pulse-node vakhsh">
                <div class="dx-pulse-ring" aria-hidden="true"></div>
                <span class="dx-pulse-name">Engine</span>
                <span class="dx-pulse-role"><?= e($product['engine_label'] ?? 'Depth · telemetry · RGB · safe OC') ?></span>
                <div class="dx-pulse-metrics">
                    <div class="dx-pulse-metric"><strong id="dx-pulse-v-deep" data-val="0">0</strong><span>Deep scans</span></div>
                    <div class="dx-pulse-metric"><strong id="dx-pulse-v-orch" data-val="0">0</strong><span>RGB orchestration</span></div>
                    <div class="dx-pulse-metric"><strong id="dx-pulse-v-layers" data-val="11">11</strong><span>Sensor layers</span></div>
                    <div class="dx-pulse-metric"><strong id="dx-pulse-v-tools" data-val="0">0</strong><span>Unified tools</span></div>
                </div>
                <p class="dx-pulse-live" id="dx-pulse-v-live">Syncing…</p>
            </article>
            <div class="dx-pulse-synapse" aria-hidden="true">
                <canvas id="dx-pulse-canvas" class="dx-pulse-canvas"></canvas>
                <p class="dx-pulse-tagline" id="dx-pulse-tagline">Tools — not a store</p>
                <span class="dx-pulse-sync" id="dx-pulse-sync">● PCVerse local</span>
            </div>
            <article class="dx-pulse-node amin">
                <div class="dx-pulse-ring" aria-hidden="true"></div>
                <span class="dx-pulse-name">Advisor</span>
                <span class="dx-pulse-role"><?= e($product['advisor_label'] ?? 'Insight · bottleneck · guidance') ?></span>
                <div class="dx-pulse-metrics">
                    <div class="dx-pulse-metric"><strong id="dx-pulse-a-insights" data-val="0">0</strong><span>Analyses</span></div>
                    <div class="dx-pulse-metric"><strong id="dx-pulse-a-today" data-val="0">0</strong><span>Today</span></div>
                    <div class="dx-pulse-metric"><strong id="dx-pulse-a-health">—</strong><span>24h avg health</span></div>
                    <div class="dx-pulse-metric"><strong id="dx-pulse-a-bn" data-val="0">0</strong><span>Bottleneck map</span></div>
                </div>
                <p class="dx-pulse-live" id="dx-pulse-a-live">Syncing…</p>
            </article>
        </div>
        <div class="dx-pulse-whisper"><p id="dx-pulse-whisper-text">Engine adds depth · Advisor adds meaning — all processing stays on your PC.</p></div>
        <div class="dx-pulse-feed" id="dx-pulse-feed"></div>
    </section>

    <nav class="dx-tabs" aria-label="Lab sections">
        <div class="dx-tabs__list" role="tablist">
            <button type="button" class="dx-tab-btn is-active" role="tab" data-dx-tab="quick" aria-selected="true">Quick scan</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="full" aria-selected="false">Full scan</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="toolkit" aria-selected="false">Toolkit</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="history" aria-selected="false">History</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="advanced" aria-selected="false">Advanced</button>
        </div>
    </nav>

    <div class="dx-tab-panel is-active" data-dx-panel="quick" role="tabpanel" id="dx-wizard-panel">
        <div class="dx-quick-layout">
            <div class="dx-wizard glass-effect" id="dx-wizard">
                <div class="dx-progress"><div id="dx-progress-bar"></div></div>
                <div id="dx-step-container"></div>
                <div class="dx-nav">
                    <button type="button" class="dx-btn ghost" id="dx-prev" disabled>Back</button>
                    <button type="button" class="dx-btn primary" id="dx-next">Next</button>
                </div>
            </div>
            <p class="dx-quick-hint muted fs-sm">Answer a few questions for a fast health score. For real sensors and OC suggestions, use <strong>Full scan</strong>.</p>
            <div id="dx-results" class="dx-results glass-effect" hidden></div>
        </div>
    </div>

    <div class="dx-tab-panel" data-dx-panel="full" role="tabpanel" id="dx-full-scan" hidden>
        <div class="dx-full-layout">
            <section class="dx-full-scan glass-effect">
                <div class="dx-full-head">
                    <p class="dx-full-kicker">Windows · local PC</p>
                    <h2>Full scan with <span class="dx-gradient">PCVerse Probe</span></h2>
                    <p class="dx-full-lead">Real sensors, bottlenecks, game performance, and stability — everything runs on your machine.</p>
                </div>
                <div class="dx-full-primary">
                    <a href="<?= e($probeDl) ?>" class="dx-btn primary dx-full-dl-main" download>Download PCVerse Probe</a>
                    <p class="muted fs-sm dx-full-note">Install and run locally — no cloud required.</p>
                </div>
                <details class="dx-full-advanced">
                    <summary>Connect Probe or import a report</summary>
                    <div class="dx-full-advanced-body">
                        <div class="dx-full-grid">
                            <div class="dx-full-card">
                                <h3>1. Local Probe</h3>
                                <p class="muted fs-sm">Run PCVerse Probe, then click Connect.</p>
                                <a href="<?= e($probeDl) ?>" class="dx-btn primary dx-full-dl" download>Download Probe</a>
                                <button type="button" class="dx-btn ghost dx-full-dl" id="dx-fetch-probe">Connect</button>
                                <span id="dx-probe-status" class="muted fs-xs"></span>
                            </div>
                            <div class="dx-full-card">
                                <h3>2. Load report JSON</h3>
                                <input type="file" id="dx-probe-file" accept=".json,application/json" class="dx-file-input">
                            </div>
                            <div class="dx-full-card">
                                <h3>3. Optional game import</h3>
                                <select id="dx-import-format" class="dx-select">
                                    <option value="">— No extra file —</option>
                                    <?php foreach ($importFormats as $fmt): ?>
                                    <option value="<?= e($fmt['id'] ?? '') ?>"><?= e($fmt['label'] ?? $fmt['label_fa'] ?? $fmt['id'] ?? '') ?></option>
                                    <?php endforeach; ?>
                                </select>
                                <input type="file" id="dx-import-file" accept=".csv,.json,.txt" class="dx-file-input">
                            </div>
                        </div>
                        <div class="dx-full-games">
                            <label class="muted fs-sm">Favorite games (optional)</label>
                            <input type="search" id="dx-game-search" placeholder="Search games…" class="dx-select">
                            <div id="dx-game-chips" class="dx-game-chips"></div>
                        </div>
                        <button type="button" class="dx-btn primary" id="dx-run-full">Run full analysis</button>
                    </div>
                </details>
                <div id="dx-full-results" class="dx-results" hidden></div>
                <div id="dx-vakhsh-oc" class="dx-vakhsh-oc-wrap"></div>
            </section>
        </div>
    </div>

    <div class="dx-tab-panel" data-dx-panel="toolkit" role="tabpanel" id="dx-toolkit" hidden>
        <div class="dx-toolkit">
            <div class="dx-toolkit-head dx-panel-card">
                <div>
                    <h2>80 tools → one lab</h2>
                    <p class="muted fs-sm" id="dx-toolkit-headline">Loading toolkit coverage…</p>
                </div>
                <div class="dx-toolkit-stats" id="dx-toolkit-stats"></div>
            </div>
            <div class="dx-toolkit-run dx-panel-card">
                <h3>Run benchmarks &amp; stress tests</h3>
                <p class="muted fs-sm">Requires PCVerse Probe on Windows. Replaces Cinebench, Prime95, OCCT, CrystalDiskMark, MemTest workflows.</p>
                <div class="dx-toolkit-run-grid" id="dx-toolkit-run"></div>
                <div class="dx-toolkit-run-status muted fs-sm" id="dx-toolkit-run-status">Connect Probe to run tests.</div>
                <pre class="dx-toolkit-result" id="dx-toolkit-result" hidden></pre>
            </div>
            <div class="dx-toolkit-filters" id="dx-toolkit-filters" role="tablist" aria-label="Tool categories"></div>
            <div class="dx-toolkit-grid" id="dx-toolkit-grid"></div>
        </div>
    </div>

    <div class="dx-tab-panel" data-dx-panel="history" role="tabpanel" id="dx-live-lab" hidden>
        <div class="dx-live dx-live--history" id="dx-live-lab-inner">
            <div class="dx-live-grid-bg"></div>
            <div class="dx-live-inner">
                <div class="dx-live-stats dx-stats-compact">
                    <div class="dx-live-stat"><span class="dx-live-stat-num" id="dx-stat-today" data-val="0">0</span><span class="dx-live-stat-label">Scans today</span></div>
                    <div class="dx-live-stat"><span class="dx-live-stat-num" id="dx-stat-avg">—</span><span class="dx-live-stat-label">24h average</span></div>
                    <div class="dx-live-stat"><span class="dx-live-stat-num" id="dx-stat-total" data-val="0">0</span><span class="dx-live-stat-label">Total scans</span></div>
                    <div class="dx-live-stat dx-live-stat--ghost"><span class="dx-live-stat-num" id="dx-stat-hour" data-val="0">0</span><span class="dx-live-stat-label">Last hour</span></div>
                    <div class="dx-live-stat dx-live-stat--ghost"><span class="dx-live-stat-num" id="dx-stat-full" data-val="0">0</span><span class="dx-live-stat-label">Deep scans</span></div>
                    <div class="dx-live-stat dx-live-stat--ghost"><span class="dx-live-stat-num" id="dx-stat-tools"><?= (int) $toolTotal ?></span><span class="dx-live-stat-label">Tools unified</span></div>
                </div>
                <div class="dx-history-layout">
                    <div class="dx-history-panel dx-panel-card">
                        <h3>Your history</h3>
                        <p class="dx-history-sub">Saved on this PC — click a run to compare with earlier tests</p>
                        <div class="dx-history-list" id="dx-history-list"></div>
                    </div>
                    <div class="dx-panel-card">
                        <h3 class="dx-sensor-title">Live sensors</h3>
                        <p class="muted fs-sm dx-sensor-sub">From your latest Probe connection</p>
                        <div class="dx-sensor-strip" id="dx-sensor-strip">
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-cpu">—</div><div class="dx-sensor-lbl">CPU Temp</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-gpu">—</div><div class="dx-sensor-lbl">GPU Temp</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-vram">—</div><div class="dx-sensor-lbl">VRAM</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-util">—</div><div class="dx-sensor-lbl">GPU Util</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-ram">—</div><div class="dx-sensor-lbl">RAM</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-bat">—</div><div class="dx-sensor-lbl">Battery</div></div>
                        </div>
                    </div>
                </div>
                <details class="dx-collapsible">
                    <summary>Community feed &amp; benchmarks</summary>
                    <div class="dx-collapsible__body">
                        <div class="dx-ticker-wrap">
                            <div class="dx-ticker-label">Recent scans (anonymous)</div>
                            <div class="dx-ticker-track" id="dx-ticker-track"></div>
                        </div>
                        <div class="dx-tools-section">
                            <h3>Tool snapshot from recent scans</h3>
                            <div class="dx-tools-grid" id="dx-tools-grid"></div>
                        </div>
                        <div class="dx-bench-panel">
                            <h3>Community benchmark</h3>
                            <div class="dx-grade-bars" id="dx-grade-bars"></div>
                            <div class="dx-gpu-bench" id="dx-gpu-bench"></div>
                        </div>
                        <div class="dx-replace-banner" id="dx-replace-banner"></div>
                    </div>
                </details>
            </div>
        </div>
    </div>

    <div class="dx-tab-panel" data-dx-panel="advanced" role="tabpanel" hidden>
        <div class="dx-advanced-stack">
            <section class="dx-tel dx-panel-card" id="dx-telemetry">
                <div class="dx-tel-head">
                    <div>
                        <h2>Telemetry console</h2>
                        <p>Reviewer level — RAM timings · C-states · frametime · SMART</p>
                    </div>
                    <div class="dx-tel-status offline" id="dx-tel-status">Waiting for Probe…</div>
                </div>
                <div class="dx-tel-highlights" id="dx-tel-highlights"></div>
                <div class="dx-tel-viz">
                    <div class="dx-tel-gauges" id="dx-tel-gauges"></div>
                    <div class="dx-tel-spark-wrap">
                        <div class="dx-tel-spark-label">Live frametime trend (up to 120 samples)</div>
                        <canvas id="dx-tel-spark" class="dx-tel-spark"></canvas>
                    </div>
                </div>
                <div class="dx-tel-charts-row"><div id="dx-tel-charts"></div><div id="dx-tel-cstates"></div></div>
                <div class="dx-tel-tabs" id="dx-tel-tabs"></div>
                <div class="dx-tel-body"><div class="dx-tel-panels" id="dx-tel-panels"><div class="dx-tel-empty">Loading console…</div></div></div>
            </section>

            <section class="dx-rgb dx-panel-card" id="dx-rgb-lab">
                <div class="dx-rgb-head">
                    <div>
                        <div class="dx-rgb-brand">RGB lab</div>
                        <h2>Case <span class="dx-gradient">LED · fans · LCD</span></h2>
                        <p class="dx-rgb-privacy">OpenRGB sync, fan curves, and pump LCD — files never leave your PC.</p>
                    </div>
                    <div class="dx-rgb-status warn" id="dx-rgb-status">Waiting for Probe…</div>
                </div>
                <div class="dx-rgb-body">
                    <div class="dx-rgb-toolbar">
                        <button type="button" class="dx-btn ghost" id="dx-rgb-scan">Rescan RGB</button>
                        <button type="button" class="dx-btn primary" id="dx-rgb-vakhsh">Auto setup</button>
                        <button type="button" class="dx-btn ghost" id="dx-rgb-apply">Manual zone</button>
                    </div>
                    <div class="dx-rgb-devices" id="dx-rgb-devices"><div class="dx-rgb-empty">Scanning USB/HID…</div></div>
                </div>
            </section>
        </div>
    </div>

</div>

<?php
$wa = $cfg['windows_agent'] ?? [];
$agentHost = trim((string) ($wa['local_host'] ?? '127.0.0.1')) ?: '127.0.0.1';
$agentPort = (int) ($wa['local_port'] ?? 18765);
$pcverseAgentBase = 'http://' . $agentHost . ':' . max(1, min(65535, $agentPort));
?>
<script>
window.PCVERSE_DIAGNOSTIC = {
    steps: <?= json_encode($steps, JSON_UNESCAPED_UNICODE) ?>,
    appDownload: <?= json_encode($cfg['app_download'] ?? [], JSON_UNESCAPED_UNICODE) ?>,
    agentBase: <?= json_encode($pcverseAgentBase, JSON_UNESCAPED_UNICODE) ?>
};
</script>
<script defer src="/assets/js/diagnostic-tabs.js?v=1.0.1"></script>
<script defer src="/assets/js/diagnostic-toolkit.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-compare.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-pulse.js?v=1.0.2"></script>
<script defer src="/assets/js/diagnostic-lab.js?v=1.7.2"></script>
<script defer src="/assets/js/diagnostic-live.js?v=1.5.3"></script>
<script defer src="/assets/js/diagnostic-telemetry.js?v=1.5.2"></script>
<script defer src="/assets/js/diagnostic-oc.js?v=1.0.2"></script>
<script defer src="/assets/js/diagnostic-rgb.js?v=1.1.4"></script>
