<?php
/** @var array $config */
$cfg = $config ?? [];
$steps = $cfg['lite_steps'] ?? [];
$tools = $cfg['pro_tools'] ?? [];
$ua = strtolower((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''));
$isLinuxClient = str_contains($ua, 'linux') && !str_contains($ua, 'android');
$probeDl = $isLinuxClient
    ? (string) (($cfg['linux_agent'] ?? [])['download_url'] ?? ($cfg['app_download']['linux'] ?? '/download/probe-linux'))
    : (string) (($cfg['windows_agent'] ?? [])['download_url'] ?? '/download/probe-windows');
$importFormats = $cfg['import_formats'] ?? [];
$product = $cfg['product'] ?? [];
$toolKit = new \App\Services\DiagnosticToolCatalogService();
$toolTotal = $toolKit->total();
?>
<link rel="stylesheet" href="/assets/css/diagnostic-shell.css?v=1.2.0">
<link rel="stylesheet" href="/assets/css/diagnostic-toolkit.css?v=1.0.0">
<link rel="stylesheet" href="/assets/css/diagnostic-pulse.css?v=1.1.0">
<link rel="stylesheet" href="/assets/css/diagnostic-lab.css?v=1.6.6">
<link rel="stylesheet" href="/assets/css/diagnostic-live.css?v=1.7.0">
<link rel="stylesheet" href="/assets/css/diagnostic-telemetry.css?v=1.5.0">
<link rel="stylesheet" href="/assets/css/diagnostic-rgb.css?v=1.0.0">
<link rel="stylesheet" href="/assets/css/diagnostic-command.css?v=1.4.0">
<link rel="stylesheet" href="/assets/css/diagnostic-command-layout.css?v=1.4.0">
<link rel="stylesheet" href="/assets/css/diagnostic-arena.css?v=1.0.0">
<link rel="stylesheet" href="/assets/css/diagnostic-drivers-stress.css?v=1.1.0">

<div class="container dx-shell">

    <header class="dx-shell-hero">
        <div class="dx-shell-hero__inner">
            <p class="dx-shell-eyebrow">PC Lab Kit</p>
            <h1 class="dx-shell-title sr-only">PC Lab Kit</h1>
            <p class="dx-shell-lead"><?= e($product['full_tagline'] ?? 'Detect hardware · choose drivers or tests · everything stays on this PC.') ?></p>
            <div class="dx-shell-meta">
                <span class="dx-shell-pill dx-shell-pill--live">Local only</span>
                <span class="dx-shell-pill"><?= (int) $toolTotal ?> tools unified</span>
                <button type="button" class="dx-shell-pill dx-shell-pill--btn" id="dx-settings-open-inline" aria-haspopup="dialog">AI advisor</button>
                <span class="dx-shell-pill" id="dx-live-updated">Loading…</span>
            </div>
        </div>
    </header>

    <div class="dx-lab-workspace">
        <nav class="dx-lab-nav" aria-label="Lab modules">
            <p class="dx-lab-nav__brand">PC Lab Kit</p>
            <button type="button" class="dx-lab-nav-btn is-active" data-dx-nav="command" aria-selected="true"><span class="dx-lab-nav-btn__icon" data-mark="OV"></span>Overview</button>
            <p class="dx-lab-nav__section">Lab</p>
            <button type="button" class="dx-lab-nav-btn" data-dx-nav="drivers" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="DR"></span>Drivers</button>
            <button type="button" class="dx-lab-nav-btn" data-dx-nav="stress" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="TE"></span>Test</button>
            <button type="button" class="dx-lab-nav-btn" data-dx-nav="openbook" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="OB"></span>Open Book</button>
            <button type="button" class="dx-lab-nav-btn" data-dx-nav="history" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="H"></span>History</button>
            <details class="dx-lab-nav__more">
                <summary>Advanced</summary>
                <button type="button" class="dx-lab-nav-btn" data-dx-nav="arena" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="BA"></span>Benchmark Arena</button>
                <button type="button" class="dx-lab-nav-btn" data-dx-nav="quick" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="Q"></span>Quick scan</button>
                <button type="button" class="dx-lab-nav-btn" data-dx-nav="hardware" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="HW"></span>Hardware Reference</button>
                <button type="button" class="dx-lab-nav-btn" data-dx-nav="full" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="FS"></span>Full scan</button>
                <button type="button" class="dx-lab-nav-btn" data-dx-nav="toolkit" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="TK"></span>Toolkit</button>
                <button type="button" class="dx-lab-nav-btn" data-dx-nav="advanced" aria-selected="false"><span class="dx-lab-nav-btn__icon" data-mark="+"></span>Settings &amp; RGB</button>
            </details>
        </nav>

        <div class="dx-lab-main">
    <div id="dx-probe-sla" class="dx-probe-sla" hidden aria-live="polite"></div>

    <nav class="dx-tabs dx-tabs--legacy-hidden" aria-label="Lab sections">
        <div class="dx-tabs__list" role="tablist">
            <button type="button" class="dx-tab-btn is-active" role="tab" data-dx-tab="command" aria-selected="true">Overview</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="quick" aria-selected="false">Quick scan</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="hardware" aria-selected="false">Hardware Reference</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="openbook" aria-selected="false">Open Book</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="drivers" aria-selected="false">Drivers</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="stress" aria-selected="false">Test</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="full" aria-selected="false">Full scan</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="arena" aria-selected="false">Benchmark Arena</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="toolkit" aria-selected="false">Toolkit</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="history" aria-selected="false">History</button>
            <button type="button" class="dx-tab-btn" role="tab" data-dx-tab="advanced" aria-selected="false">Advanced</button>
        </div>
    </nav>

    <div class="dx-tab-panel is-active" data-dx-panel="command" role="tabpanel" id="dx-command-panel">
        <section class="dx-command-center dx-overview glass-effect" id="dx-command-center" aria-label="Overview">
            <p class="dx-command-center__eyebrow">Overview</p>
            <h2 class="dx-command-center__title">Detect → decide → execute</h2>
            <p class="dx-command-center__lead">See what Probe found, then open Drivers or Test for that component. No forced full run.</p>

            <div class="dx-overview-probe" id="dx-overview-probe" role="status" aria-live="polite">
                <div class="dx-overview-probe__row">
                    <span class="dx-overview-probe__dot" id="dx-overview-probe-dot" data-state="unknown" aria-hidden="true"></span>
                    <div>
                        <strong id="dx-overview-probe-label">Probe</strong>
                        <p class="muted fs-sm" id="dx-overview-probe-detail">Checking local Probe…</p>
                    </div>
                    <button type="button" class="dx-btn ghost" id="dx-overview-probe-retry">Recheck</button>
                </div>
            </div>

            <div class="dx-overview-detected" aria-label="Detected hardware">
                <div class="dx-overview-detected__head">
                    <h3>Detected hardware</h3>
                    <button type="button" class="dx-btn ghost" id="dx-overview-refresh">Rescan</button>
                </div>
                <div class="dx-overview-grid" id="dx-overview-grid">
                    <p class="muted fs-sm dx-empty-hint">Waiting for Probe inventory…</p>
                </div>
            </div>

            <section class="dx-lab-canvas" aria-label="Live canvas">
                <div class="dx-lab-canvas__head">
                    <h2>Live twin</h2>
                    <span class="muted fs-xs">3D topology · probe SLA above</span>
                </div>
                <div class="dx-lab-canvas__grid">
                    <section class="dx-pulse-visible dx-pulse-demoted" id="dx-intelligence-pulse" aria-label="Lab activity" hidden>
                        <div class="dx-pulse-bridge">
                            <article class="dx-pulse-node engine">
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
                                <span class="dx-pulse-sync" id="dx-pulse-sync">● PC Lab Kit local</span>
                            </div>
                            <article class="dx-pulse-node advisor">
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
                    <div class="dx-lab-twin-preview" id="dx-lab-twin-preview" aria-label="3D digital twin preview">
                        <span class="dx-lab-twin-preview__label">3D twin</span>
                        <span class="dx-topology-node-hint">Click nodes → Hardware Reference</span>
                    </div>
                </div>
            </section>

            <details class="dx-programmed-suite" id="dx-programmed-suite">
                <summary>Programmed suite <span class="muted fs-xs">optional batch · benches + stress in one plan</span></summary>
                <div class="dx-programmed-suite__body">
                    <ol class="dx-oem-phases" aria-label="Suite phases">
                        <li data-dx-oem-phase="run" class="is-active">Run</li>
                        <li data-dx-oem-phase="progress">Progress</li>
                        <li data-dx-oem-phase="verdict">Verdict</li>
                        <li data-dx-oem-phase="cert">Cert</li>
                    </ol>
                    <div class="dx-command-center__row">
                        <label class="sr-only" for="dx-suite-profile">Suite profile</label>
                        <select id="dx-suite-profile" aria-label="Suite profile">
                            <option value="adaptive" selected>Adaptive Lab (this machine)</option>
                            <option value="quick">Quick Lab (~5 min)</option>
                            <option value="standard">Full Lab (~12 min)</option>
                            <option value="deep">Deep Lab (~20 min)</option>
                            <option value="soak_15">Soak 15 min</option>
                            <option value="soak_30">Soak 30 min</option>
                            <option value="soak_60">Soak 60 min</option>
                        </select>
                        <button type="button" class="dx-btn primary" id="dx-suite-run">Start Adaptive Lab</button>
                        <button type="button" class="dx-btn ghost" id="dx-suite-cancel" hidden>Cancel</button>
                        <button type="button" class="dx-btn ghost" id="dx-suite-preview-plan">Preview plan</button>
                        <button type="button" class="dx-btn ghost" id="dx-platform-audit-export">Export Platform Audit</button>
                        <label class="dx-btn ghost dx-suite-import-label" for="dx-suite-import-file">Import .pclab</label>
                        <input type="file" id="dx-suite-import-file" accept=".json,.pclab,.pclab.json,application/json" hidden>
                    </div>
                    <div id="dx-suite-plan-preview" class="dx-suite-plan-preview muted fs-sm" hidden></div>
                    <div id="dx-suite-import-result" class="dx-suite-import-result" hidden></div>
                    <div id="dx-suite-resume" class="dx-suite-resume" hidden role="status"></div>
                    <div class="dx-suite-progress" aria-hidden="true"><span id="dx-suite-progress-bar"></span></div>
                    <div class="dx-suite-meta">
                        <span id="dx-suite-step">Idle</span>
                        <span id="dx-suite-status">Ready when Probe is running</span>
                    </div>
                    <div id="dx-suite-error" class="dx-suite-error" hidden role="alert"></div>
                </div>
            </details>
            <div id="dx-advisor-cards" class="dx-advisor-cards" hidden></div>
            <div id="dx-suite-result" class="dx-suite-result" hidden></div>
        </section>
    </div>

    <div class="dx-tab-panel" data-dx-panel="quick" role="tabpanel" id="dx-wizard-panel" hidden>
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

    <div class="dx-tab-panel" data-dx-panel="hardware" role="tabpanel" id="dx-hardware-ref" hidden>
        <section class="dx-hwref glass-effect" aria-label="Hardware Reference">
            <div class="dx-hwref__head">
                <div>
                    <p class="dx-command-center__eyebrow">Hardware Reference</p>
                    <h2>Every device · confidence tagged</h2>
                    <p class="muted fs-sm">PnP including hidden/ghost · EDID · SPD · PCI/USB trees. Values show measured vs heuristic.</p>
                </div>
                <div class="dx-hwref__toolbar">
                    <button type="button" class="dx-btn primary" id="dx-hwref-refresh">Scan inventory</button>
                    <button type="button" class="dx-btn ghost" id="dx-hwref-export">Export JSON</button>
                    <span class="dx-hwref__status" id="dx-hwref-status">Waiting for Probe…</span>
                </div>
            </div>
            <div class="dx-hwref__banner" id="dx-hwref-elevate" hidden></div>
            <div class="dx-hwref__filters" id="dx-hwref-filters">
                <label><input type="checkbox" data-hw-filter="present" checked> Present</label>
                <label><input type="checkbox" data-hw-filter="hidden" checked> Hidden</label>
                <label><input type="checkbox" data-hw-filter="problem" checked> Problem</label>
                <label><input type="checkbox" data-hw-filter="driverless" checked> Driverless</label>
                <input type="search" id="dx-hwref-search" placeholder="Search name, VEN, DEV, instance…" class="dx-hwref__search">
            </div>
            <div class="dx-hwref__layout">
                <div class="dx-hwref__tree" id="dx-hwref-tree"><p class="muted fs-sm dx-empty-hint">No inventory yet. Click <strong>Scan inventory</strong> — Probe must be running (it starts with the desktop app).</p></div>
                <div class="dx-hwref__detail" id="dx-hwref-detail"><p class="muted fs-sm dx-empty-hint">Select a device in the tree to see every measured field and confidence tag.</p></div>
            </div>
            <div class="dx-hwref__topo" id="dx-hwref-topology" aria-label="System topology"></div>
            <div class="dx-hwref__openbook" id="dx-hwref-openbook" aria-label="Open-book sensors">
                <h3 class="dx-hwref__openbook-title">Open Book sensors</h3>
                <p class="muted fs-xs">Recovered registers NVIDIA/AMD/Intel hide from public APIs. Requires elevated Probe. Values tagged with source — not official NVAPI.</p>
                <div id="dx-hwref-openbook-table"><p class="muted fs-sm">Scan inventory or wait for Probe thermal sample.</p></div>
            </div>
            <div class="dx-hwref__dossier" id="dx-hwref-dossier" aria-label="Silicon dossier">
                <h3 class="dx-hwref__openbook-title">Silicon Dossier</h3>
                <p class="muted fs-xs">Chip IDs, serials, PCI config, EDID hex. Export for RMA / client records.</p>
                <div class="dx-hwref__toolbar">
                    <button type="button" class="dx-btn ghost" id="dx-hwref-dossier-export">Export dossier JSON</button>
                </div>
                <div id="dx-hwref-dossier-body"><p class="muted fs-sm">Scan inventory to load identity dumps.</p></div>
            </div>
            <div class="dx-hwref__drivers" id="dx-hwref-drivers">
                <p class="muted fs-sm">Driver install/update lives in the <button type="button" class="dx-btn ghost" data-dx-goto="drivers">Drivers</button> tab — Install appears on each problem device.</p>
            </div>
        </section>
    </div>

    <div class="dx-tab-panel" data-dx-panel="openbook" role="tabpanel" id="dx-openbook-lab" hidden>
        <section class="dx-openbook-lab glass-effect" aria-label="Open Book Lab">
            <div class="dx-openbook-lab__head">
                <div>
                    <p class="dx-command-center__eyebrow">Open Book Lab</p>
                    <h2>Silicon truth · firmware · recovered sensors</h2>
                    <p class="muted fs-sm">BIOS/UEFI, VBIOS, microcode, PCI config, SPD, EDID, and register-level thermals the vendor APIs hide. Requires elevated Probe. Soak tests live in the <strong>Test</strong> tab.</p>
                </div>
                <div class="dx-hwref__toolbar">
                    <button type="button" class="dx-btn primary" id="dx-ob-refresh">Refresh</button>
                    <button type="button" class="dx-btn ghost" id="dx-ob-export-dossier">Export dossier</button>
                    <button type="button" class="dx-btn ghost" data-dx-goto="stress">Open Test</button>
                    <span class="dx-hwref__status" id="dx-ob-status">Waiting for Probe…</span>
                </div>
            </div>
            <div class="dx-truth-cards" id="dx-ob-truth-cards" aria-label="Firmware identity cards"></div>
            <div class="dx-openbook-lab__grid dx-openbook-lab__grid--two">
                <aside class="dx-openbook-lab__col" id="dx-ob-dossier" aria-label="Silicon dossier">
                    <h3>Silicon Dossier</h3>
                    <div id="dx-ob-dossier-body"><p class="muted fs-sm dx-empty-hint">Click <strong>Refresh</strong> with Probe running to load CPU, GPU, RAM, and board identity.</p></div>
                </aside>
                <div class="dx-openbook-lab__col dx-openbook-lab__col--center" aria-label="Live open-book gauges">
                    <h3>Live open-book</h3>
                    <div id="dx-ob-gauges" class="dx-openbook-lab__gauges"></div>
                    <div id="dx-ob-table" class="dx-scroll-panel"></div>
                </div>
            </div>
            <p class="muted fs-xs dx-truth-caveat">We read registers and firmware identity on your PC. We do not flash BIOS/VBIOS or ship proprietary vendor MODS binaries. Absolute °C may differ slightly from manufacturer tools — deltas and provenance tags matter more.</p>
        </section>
    </div>

    <div class="dx-tab-panel" data-dx-panel="drivers" role="tabpanel" id="dx-drivers-lab" hidden>
        <section class="dx-drivers-lab glass-effect" aria-label="Drivers">
            <div class="dx-drivers-lab__head">
                <div>
                    <p class="dx-command-center__eyebrow">Drivers</p>
                    <h2 id="dx-drivers-heading">Hardware that needs install or update</h2>
                    <p class="muted fs-sm" id="dx-drivers-lead">Problem, driverless, or outdated devices — Install/Update on that row. Probe must be running.</p>
                </div>
                <div class="dx-hwref__toolbar">
                    <button type="button" class="dx-btn primary" id="dx-drivers-rescan">Rescan devices</button>
                    <button type="button" class="dx-btn ghost" id="dx-drivers-wu">Windows Update scan</button>
                    <span class="dx-hwref__status" id="dx-drivers-status">Idle</span>
                </div>
            </div>
            <p class="muted fs-xs" id="dx-drivers-note" role="status"></p>
            <div id="dx-driver-actions" class="dx-driver-actions dx-scroll-panel">
                <div class="dx-panel-empty" id="dx-drivers-empty">
                    <strong>No scan yet</strong>
                    <p class="muted fs-sm">Click <em>Rescan devices</em>. If Probe is offline, open the PC Lab Kit desktop app first.</p>
                </div>
            </div>
            <p class="muted fs-sm">Need PnP identity? <button type="button" class="dx-btn ghost" data-dx-goto="hardware">Hardware Reference</button></p>
        </section>
    </div>

    <div class="dx-tab-panel" data-dx-panel="stress" role="tabpanel" id="dx-stress-lab" hidden>
        <section class="dx-stress-lab glass-effect" aria-label="Test">
            <div class="dx-stress-lab__head">
                <div>
                    <p class="dx-command-center__eyebrow">Test</p>
                    <h2>Choose hardware · set duration · run</h2>
                    <p class="muted fs-sm">Select targets and how long to soak. Results and certificates stay on this PC.</p>
                </div>
                <span class="dx-hwref__status" id="dx-stress-status">Idle</span>
            </div>
            <div class="dx-test-composer">
                <fieldset class="dx-test-targets">
                    <legend>Targets</legend>
                    <label class="dx-test-check"><input type="checkbox" name="dx-test-target" value="cpu" checked> CPU</label>
                    <label class="dx-test-check"><input type="checkbox" name="dx-test-target" value="gpu" checked> GPU</label>
                    <label class="dx-test-check"><input type="checkbox" name="dx-test-target" value="memory" checked> Memory</label>
                </fieldset>
                <div class="dx-test-duration">
                    <span class="dx-test-duration__label">Duration</span>
                    <div class="dx-test-presets" role="group" aria-label="Duration presets">
                        <button type="button" class="dx-test-preset" data-minutes="1">1 min</button>
                        <button type="button" class="dx-test-preset is-active" data-minutes="5">5 min</button>
                        <button type="button" class="dx-test-preset" data-minutes="15">15 min</button>
                        <button type="button" class="dx-test-preset" data-minutes="30">30 min</button>
                    </div>
                    <div class="dx-stress-controls dx-stress-controls--compact">
                        <label class="dx-stress-field">
                            <span>Hours</span>
                            <input type="number" id="dx-stress-hours" min="0" max="24" step="1" value="0" aria-label="Test hours">
                        </label>
                        <label class="dx-stress-field">
                            <span>Minutes</span>
                            <input type="number" id="dx-stress-minutes" min="0" max="1440" step="1" value="5" aria-label="Test minutes">
                        </label>
                    </div>
                </div>
                <details class="dx-test-advanced">
                    <summary>Advanced</summary>
                    <label class="dx-test-check"><input type="checkbox" id="dx-stress-oracle"> Stability oracle (instead of selected targets)</label>
                    <select id="dx-stress-profile" class="sr-only" aria-hidden="true" tabindex="-1">
                        <option value="combined" selected>Combined</option>
                        <option value="cpu">CPU</option>
                        <option value="gpu">GPU</option>
                        <option value="memory">Memory</option>
                        <option value="quick">Quick</option>
                        <option value="oracle">Oracle</option>
                    </select>
                </details>
                <div class="dx-test-actions">
                    <button type="button" class="dx-btn primary" id="dx-stress-run">Start CPU+GPU+Memory · 5 min</button>
                    <button type="button" class="dx-btn ghost" id="dx-stress-stop" hidden>Stop</button>
                </div>
            </div>
            <div class="dx-suite-progress" id="dx-stress-progress" aria-hidden="true"><span id="dx-stress-progress-bar"></span></div>
            <div class="dx-stress-live" id="dx-stress-live" aria-live="polite"></div>
            <div class="dx-stress-cert" id="dx-stress-cert">
                <h3>Certificate</h3>
                <p class="muted fs-sm" id="dx-ob-cert-status">Complete a test here to issue an Assembly Certificate.</p>
                <div id="dx-ob-cert-actions"></div>
                <div id="dx-ob-cert-frame" class="dx-scroll-panel" hidden></div>
            </div>
        </section>
    </div>

    <div class="dx-tab-panel" data-dx-panel="full" role="tabpanel" id="dx-full-scan" hidden>
        <div class="dx-full-layout">
            <section class="dx-full-scan glass-effect">
                <div class="dx-full-head">
                    <p class="dx-full-kicker">Windows · local PC</p>
                    <h2>Full scan with <span class="dx-gradient">PcLab Probe</span></h2>
                    <p class="dx-full-lead">Real sensors, bottlenecks, game performance, and stability — everything runs on your machine.</p>
                </div>
                <div class="dx-full-primary dx-web-only">
                    <a href="<?= e($probeDl) ?>" class="dx-btn primary dx-full-dl-main" download>Download PcLab Probe</a>
                    <p class="muted fs-sm dx-full-note">Install and run locally — no cloud required.</p>
                </div>
                <div class="dx-full-primary dx-desktop-only">
                    <button type="button" class="dx-btn primary" id="dx-fetch-probe">Connect Probe</button>
                    <p class="muted fs-sm dx-full-note">Probe starts with this app. Connect for a live snapshot, or use Overview → Programmed suite for a batch plan.</p>
                </div>
                <p id="dx-probe-status" class="muted fs-xs dx-probe-status" role="status"></p>
                <details class="dx-full-advanced">
                    <summary>Connect Probe or import a report</summary>
                    <div class="dx-full-advanced-body">
                        <div class="dx-full-grid">
                            <div class="dx-full-card">
                                <h3>1. Local Probe</h3>
                                <p class="muted fs-sm">Run PcLab Probe, then click Connect.</p>
                                <a href="<?= e($probeDl) ?>" class="dx-btn primary dx-full-dl dx-web-only" download>Download Probe</a>
                                <button type="button" class="dx-btn ghost dx-full-dl dx-web-only" id="dx-fetch-probe-web">Connect</button>
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
                <div id="dx-oc-panel" class="dx-oc-panel-wrap"></div>
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
                <p class="muted fs-sm">Requires PcLab Probe on Windows. Replaces Cinebench, Prime95, OCCT, CrystalDiskMark, MemTest workflows.</p>
                <div class="dx-toolkit-run-grid" id="dx-toolkit-run"></div>
                <div class="dx-toolkit-run-status muted fs-sm" id="dx-toolkit-run-status">Connect Probe to run tests.</div>
                <pre class="dx-toolkit-result" id="dx-toolkit-result" hidden></pre>
            </div>
            <div class="dx-toolkit-filters" id="dx-toolkit-filters" role="tablist" aria-label="Tool categories"></div>
            <div class="dx-toolkit-grid" id="dx-toolkit-grid"></div>
        </div>
    </div>

    <div class="dx-tab-panel" data-dx-panel="arena" role="tabpanel" id="dx-arena" hidden>
        <div class="dx-arena">
            <section class="dx-arena-hero">
                <p class="dx-command-center__eyebrow">Benchmark Arena</p>
                <h2>Your rig vs the reference library</h2>
                <p class="muted fs-sm">Percentile rings from <?= (int) $toolTotal ?>-tool native benches vs PassMark lab + gold crowd datasets — fully local.</p>
                <div class="dx-arena-stats" id="dx-arena-stats"></div>
            </section>
            <div class="dx-arena-grid" id="dx-arena-grid"></div>
            <section class="dx-arena-radar-wrap">
                <h3>Component radar (percentile)</h3>
                <div id="dx-arena-radar"></div>
            </section>
            <details class="dx-arena-datasets">
                <summary>Reference datasets (<?= (int) $toolTotal ?> tool catalog)</summary>
                <div class="dx-arena-dataset-list" id="dx-arena-datasets-list"></div>
            </details>
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
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-cpu">—</div><div class="dx-sensor-lbl">CPU Package</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-cpu-hs">—</div><div class="dx-sensor-lbl">CPU Hot Spot</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-gpu">—</div><div class="dx-sensor-lbl">GPU Core</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-gpu-hs">—</div><div class="dx-sensor-lbl">GPU Hot Spot</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-gpu-delta">—</div><div class="dx-sensor-lbl">HS Δ</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-vram">—</div><div class="dx-sensor-lbl">VRAM</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-util">—</div><div class="dx-sensor-lbl">GPU Util</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-ram">—</div><div class="dx-sensor-lbl">RAM</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-drivers">—</div><div class="dx-sensor-lbl">Drivers</div></div>
                            <div class="dx-sensor-cell"><div class="dx-sensor-val" id="dx-s-bat">—</div><div class="dx-sensor-lbl">Battery</div></div>
                        </div>
                        <p class="muted fs-xs" id="dx-sensor-note" hidden></p>
                        <p class="muted fs-sm"><button type="button" class="dx-btn ghost" data-dx-goto="drivers">Open Drivers tab</button> for install/update per device.</p>
                    </div>
                </div>
                <div id="dx-silicon-aging"></div>
                <div id="dx-hw-graph-mount"></div>
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
            <section class="dx-sensor-deck dx-panel-card" id="dx-sensor-deck">
                <div class="dx-tel-head">
                    <div>
                        <h2>Sensor Deck</h2>
                        <p>Live gauges from Probe telemetry — save layout or export Rainmeter/JSON placeholders</p>
                    </div>
                    <div class="dx-tel-status" id="dx-deck-status">Waiting…</div>
                </div>
                <div class="dx-command-center__row" style="margin-bottom:0.75rem">
                    <button type="button" class="dx-btn ghost" id="dx-deck-save">Save layout</button>
                    <button type="button" class="dx-btn ghost" id="dx-deck-export-json">Export JSON</button>
                    <button type="button" class="dx-btn ghost" id="dx-deck-export-csv">Export CSV timeline</button>
                    <button type="button" class="dx-btn ghost" id="dx-deck-export-rain">Export Rainmeter</button>
                </div>
                <div class="dx-sensor-deck__grid" id="dx-deck-grid"></div>
            </section>

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
                        <button type="button" class="dx-btn primary" id="dx-rgb-auto">Auto setup</button>
                        <button type="button" class="dx-btn ghost" id="dx-rgb-apply">Apply zones</button>
                        <button type="button" class="dx-btn ghost" id="dx-rgb-stop">Stop blink</button>
                    </div>
                    <div class="dx-rgb-devices" id="dx-rgb-devices"><div class="dx-rgb-empty">Scanning USB/HID…</div></div>
                </div>
            </section>

            <section class="dx-panel-card" id="dx-advanced-topology">
                <div class="dx-tel-head">
                    <div>
                        <h2>System topology</h2>
                        <p>Always-on graph from Probe inventory — chipset, DIMMs, cooler, PCI</p>
                    </div>
                    <button type="button" class="dx-btn ghost" id="dx-topo-refresh">Refresh topology</button>
                    <button type="button" class="dx-btn ghost" id="dx-topo-3d-toggle" aria-pressed="false">3D view</button>
                </div>
                <div id="dx-advanced-topo-svg" class="dx-hwref__topo"></div>
                <div id="dx-advanced-topo-3d" class="dx-hwref__topo dx-topology-3d" hidden style="min-height:320px"></div>
            </section>

            <section class="dx-panel-card" id="dx-launchers">
                <p class="muted fs-sm">Loading external launchers…</p>
            </section>
        </div>
    </div>

        </div><!-- /.dx-lab-main -->

        <aside class="dx-lab-rail" aria-label="Advisor rail">
            <p class="dx-lab-rail__title">Advisor</p>
            <div id="dx-rail-empty" class="dx-rail-empty">
                <strong>Advisor waits for results</strong>
                Cards appear after a Programmed suite or Test finishes. Detect hardware on Overview first; Probe starts with the desktop app.
            </div>
            <div id="dx-rail-advisor" class="dx-advisor-cards" hidden></div>
            <div class="dx-lab-rail-cert">
                <h3>Certificates</h3>
                <p class="muted fs-xs">After a Test or Programmed suite, export certificates from Open Book or Overview results.</p>
                <button type="button" class="dx-btn ghost" id="dx-rail-verify" onclick="location.hash='dx-openbook-lab'">Open Book Lab</button>
            </div>
        </aside>
    </div><!-- /.dx-lab-workspace -->

</div>

<?php
$probeAgent = $cfg['probe_agent'] ?? $cfg['windows_agent'] ?? [];
$agentHost = trim((string) ($probeAgent['local_host'] ?? '127.0.0.1')) ?: '127.0.0.1';
$agentPort = (int) ($probeAgent['local_port'] ?? 18765);
$pclabAgentBase = 'http://' . $agentHost . ':' . max(1, min(65535, $agentPort));
?>
<script>
window.PCLAB_DIAGNOSTIC = {
    steps: <?= json_encode($steps, JSON_UNESCAPED_UNICODE) ?>,
    appDownload: <?= json_encode($cfg['app_download'] ?? [], JSON_UNESCAPED_UNICODE) ?>,
    agentBase: <?= json_encode($pclabAgentBase, JSON_UNESCAPED_UNICODE) ?>,
    linuxAgent: <?= json_encode($cfg['linux_agent'] ?? [], JSON_UNESCAPED_UNICODE) ?>,
    windowsAgent: <?= json_encode($cfg['windows_agent'] ?? [], JSON_UNESCAPED_UNICODE) ?>
};
</script>
<script defer src="/assets/js/diagnostic-capabilities.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-tabs.js?v=1.3.0"></script>
<script defer src="/assets/js/diagnostic-command-layout.js?v=1.3.0"></script>
<script defer src="/assets/js/diagnostic-toolkit.js?v=1.1.0"></script>
<script defer src="/assets/js/diagnostic-compare.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-pulse.js?v=1.0.3"></script>
<script defer src="/assets/js/diagnostic-arena.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-lab.js?v=1.7.3"></script>
<script defer src="/assets/js/diagnostic-live.js?v=1.8.0"></script>
<script defer src="/assets/js/diagnostic-overview.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-drivers.js?v=1.1.0"></script>
<script defer src="/assets/js/diagnostic-stress.js?v=1.1.0"></script>
<script defer src="/assets/js/diagnostic-telemetry.js?v=1.6.0"></script>
<script defer src="/assets/js/diagnostic-oc.js?v=1.1.0"></script>
<script defer src="/assets/js/diagnostic-rgb.js?v=1.1.4"></script>
<script defer src="/assets/js/diagnostic-suite.js?v=1.5.0"></script>
<script defer src="/assets/js/diagnostic-sensor-deck.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-topology.js?v=1.1.0"></script>
<script defer src="/assets/js/diagnostic-topology-3d.js?v=1.1.0"></script>
<script defer src="/assets/js/diagnostic-openbook.js?v=1.2.0"></script>
<script defer src="/assets/js/diagnostic-inventory.js?v=1.1.0"></script>
<script defer src="/assets/js/diagnostic-launchers.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-telemetry-stream.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-silicon-aging.js?v=1.0.0"></script>
<script defer src="/assets/js/diagnostic-hw-graph.js?v=1.0.0"></script>
