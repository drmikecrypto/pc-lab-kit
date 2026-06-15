(function () {
  const cfg = window.PCVERSE_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  const POLL_MS = 3000;
  let activeTab = 'cpu';
  let pollTimer = null;
  let lastProbe = null;
  let history = [];
  let telemetryTracked = false;

  const root = document.getElementById('dx-telemetry');
  if (!root) return;

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  function gaugeHtml(id, label, value, max, unit, severity) {
    const pct = max > 0 ? Math.min(100, (value / max) * 100) : 0;
    const col = severity === 'critical' ? '#ef4444' : severity === 'warn' ? '#f29f05' : '#22d3ee';
    return `<div class="dx-tel-gauge" data-gauge="${id}">
      <svg viewBox="0 0 80 80" class="dx-tel-gauge-svg">
        <circle cx="40" cy="40" r="34" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="6"/>
        <circle cx="40" cy="40" r="34" fill="none" stroke="${col}" stroke-width="6"
          stroke-dasharray="${(pct * 2.14).toFixed(1)} 214" stroke-linecap="round"
          transform="rotate(-90 40 40)" class="dx-tel-gauge-arc"/>
      </svg>
      <div class="dx-tel-gauge-val">${esc(String(value))}<small>${esc(unit)}</small></div>
      <div class="dx-tel-gauge-lbl">${esc(label)}</div>
    </div>`;
  }

  function drawSparklines() {
    const canvas = document.getElementById('dx-tel-spark');
    if (!canvas || history.length < 2) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width = canvas.offsetWidth * 2;
    const h = canvas.height = canvas.offsetHeight * 2;
    ctx.scale(2, 2);
    ctx.clearRect(0, 0, w, h);

    const cw = canvas.offsetWidth;
    const ch = canvas.offsetHeight;
    const series = [
      { key: 'cpu_temp', color: '#22d3ee', label: 'CPU' },
      { key: 'gpu_temp', color: '#f29f05', label: 'GPU' },
      { key: 'gpu_power', color: '#a78bfa', label: 'W' },
    ];

    series.forEach((s, si) => {
      const vals = history.map((h) => parseFloat(h[s.key])).filter((v) => !isNaN(v) && v > 0);
      if (vals.length < 2) return;
      const max = Math.max(...vals) * 1.1 || 1;
      ctx.beginPath();
      ctx.strokeStyle = s.color;
      ctx.lineWidth = 1.5;
      vals.forEach((v, i) => {
        const x = (i / (vals.length - 1)) * cw;
        const y = ch - (v / max) * (ch - 8) - 4 - si * 0;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.stroke();
    });
  }

  async function fetchHistory() {
    try {
      const res = await fetch(`${AGENT}/telemetry/history`, { mode: 'cors' });
      if (res.ok) {
        history = await res.json();
        if (!Array.isArray(history)) history = [];
        drawSparklines();
      }
    } catch (_) {}
  }

  async function fetchTelemetry() {
    try {
      let probe = null;
      try {
        const h = await fetch(`${AGENT}/health`, { mode: 'cors' });
        if (h.ok) {
          const t = await fetch(`${AGENT}/telemetry`, { mode: 'cors' });
          if (t.ok) probe = await t.json();
        }
      } catch (_) {}

      if (!probe && window.__dxLastProbe) probe = window.__dxLastProbe;
      if (!probe) {
        setOffline();
        return;
      }

      lastProbe = probe;
      window.__dxLastProbe = probe.full ? probe : { telemetry: probe, probe_version: 4, collected_at: probe.collected_at };

      const payload = probe.telemetry ? probe : { telemetry: probe, probe_version: 4, collected_at: probe.collected_at };
      const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
      const res = await fetch('/api/diagnostic/telemetry/present', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      render(data);
      setOnline(data.collected_at || probe.collected_at, data.hwmon_available);
      fetchHistory();
    } catch (e) {
      setOffline();
    }
  }

  function setOnline(ts, hwmon) {
    const st = document.getElementById('dx-tel-status');
    if (st) {
      st.className = 'dx-tel-status';
      const badge = hwmon ? ' · LHM ✓' : '';
      st.innerHTML = `<span class="dx-tel-status-dot"></span> LIVE v4${badge} · ${ts ? new Date(ts).toLocaleTimeString('fa-IR') : 'agent'}`;
    }
    if (!telemetryTracked && window.dxTrackLab) {
      telemetryTracked = true;
      window.dxTrackLab('vakhsh_telemetry_open', { hwmon: !!hwmon });
    }
  }

  function setOffline() {
    const st = document.getElementById('dx-tel-status');
    if (st) {
      st.className = 'dx-tel-status offline';
      st.textContent = 'Probe offline — run Start-PCVerseProbe.bat';
    }
    if (!lastProbe) {
      document.getElementById('dx-tel-highlights').innerHTML = '';
      document.getElementById('dx-tel-gauges').innerHTML = '';
      document.getElementById('dx-tel-panels').innerHTML = `<div class="dx-tel-empty">
        <p><strong>Deep Telemetry Console</strong></p>
        <p>LibreHardwareMonitor · PresentMon · per-core · SMART · WHEA · sparklines</p>
        <p><code>Start-PCVerseProbe.bat</code></p>
      </div>`;
    }
  }

  function drawSpikeMap(chart) {
    const wrap = document.getElementById('dx-tel-charts');
    if (!wrap || !chart || !chart.series || chart.series.length < 2) {
      if (wrap) wrap.innerHTML = '';
      return;
    }

    const stats = chart.stats || {};
    wrap.innerHTML = `
      <div class="dx-tel-chart-block">
        <div class="dx-tel-chart-title">In-game frametime spike map</div>
        <div class="dx-tel-chart-meta">mean ${esc(String(stats.mean_ms ?? '—'))} ms · P99 ${esc(String(stats.p99_ms ?? '—'))} ms · spikes ${esc(String(stats.spike_count ?? 0))}</div>
        <canvas id="dx-tel-spike" class="dx-tel-spike-canvas"></canvas>
      </div>`;

    const canvas = document.getElementById('dx-tel-spike');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const cw = canvas.offsetWidth || 640;
    const ch = 120;
    canvas.width = cw * 2;
    canvas.height = ch * 2;
    ctx.scale(2, 2);
    ctx.clearRect(0, 0, cw, ch);

    const series = chart.series;
    const spikes = chart.spikes || [];
    const fts = series.map((p) => parseFloat(p.ft_ms)).filter((v) => !isNaN(v));
    const maxFt = Math.max(...fts, stats.threshold_ms || 30, 20) * 1.15;
    const ref16 = (16.67 / maxFt) * (ch - 20);

    ctx.strokeStyle = 'rgba(34,197,94,0.35)';
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(0, ch - ref16 - 10);
    ctx.lineTo(cw, ch - ref16 - 10);
    ctx.stroke();
    ctx.setLineDash([]);

    ctx.beginPath();
    ctx.strokeStyle = '#22d3ee';
    ctx.lineWidth = 1.5;
    series.forEach((p, i) => {
      const x = (i / (series.length - 1)) * cw;
      const y = ch - (parseFloat(p.ft_ms) / maxFt) * (ch - 20) - 10;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    spikes.forEach((s) => {
      const idx = series.findIndex((p) => Math.abs(parseFloat(p.t_ms) - parseFloat(s.t_ms)) < 50);
      const i = idx >= 0 ? idx : Math.min(series.length - 1, Math.floor((parseFloat(s.t_ms) / (series[series.length - 1]?.t_ms || 1)) * series.length));
      const x = (i / (series.length - 1)) * cw;
      const col = s.severity === 'critical' ? '#ef4444' : s.severity === 'high' ? '#f97316' : '#f29f05';
      ctx.fillStyle = col;
      ctx.beginPath();
      ctx.arc(x, 8, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillRect(x - 1, 10, 2, ch - 20);
    });
  }

  function drawCstateBars(bars) {
    const el = document.getElementById('dx-tel-cstates');
    if (!el || !bars || !bars.length) {
      if (el) el.innerHTML = '';
      return;
    }
    el.innerHTML = `
      <div class="dx-tel-chart-block">
        <div class="dx-tel-chart-title">C-State residency</div>
        <div class="dx-tel-cstate-bars">${bars.map((b) => `
          <div class="dx-tel-cstate-row">
            <span class="dx-tel-cstate-lbl">${esc(b.state)}</span>
            <div class="dx-tel-cstate-track"><div class="dx-tel-cstate-fill" style="width:${Math.min(100, b.pct)}%"></div></div>
            <span class="dx-tel-cstate-val">${esc(String(Math.round(b.pct * 10) / 10))}%</span>
          </div>`).join('')}
      </div>`;
  }

  function render(data) {
    const hl = document.getElementById('dx-tel-highlights');
    const gauges = document.getElementById('dx-tel-gauges');
    const tabs = document.getElementById('dx-tel-tabs');
    const panels = document.getElementById('dx-tel-panels');

    hl.innerHTML = (data.highlights || []).map((h) => `
      <div class="dx-tel-hl ${esc(h.severity || 'ok')}">
        <div class="dx-tel-hl-val">${esc(String(h.value))}${h.unit ? `<span class="dx-tel-unit">${esc(h.unit)}</span>` : ''}</div>
        <div class="dx-tel-hl-lbl">${esc(h.label_fa)}</div>
      </div>`).join('');

    const gh = (data.highlights || []).filter((h) => ['cpu_temp', 'gpu_temp', 'gpu_power', 'gpu_util'].includes(h.id));
    gauges.innerHTML = gh.map((h) => {
      const max = h.id.includes('temp') ? 100 : h.id.includes('power') ? 300 : 100;
      const v = parseFloat(h.value) || 0;
      return gaugeHtml(h.id, h.label_fa, v, max, h.unit || '', h.severity);
    }).join('');

    tabs.innerHTML = (data.tabs || []).map((t) => `
      <button type="button" class="dx-tel-tab${t.id === activeTab ? ' active' : ''}" data-tab="${esc(t.id)}">${esc(t.label_fa)}</button>
    `).join('');

    tabs.querySelectorAll('.dx-tel-tab').forEach((btn) => {
      btn.addEventListener('click', () => { activeTab = btn.dataset.tab; render(data); });
    });

    const tab = (data.tabs || []).find((t) => t.id === activeTab) || (data.tabs || [])[0];
    if (!tab) { panels.innerHTML = ''; return; }

    panels.innerHTML = (tab.sections || []).map((sec) => {
      const wide = (sec.rows || []).length > 8;
      return `<div class="dx-tel-panel${wide ? ' dx-tel-panel-wide' : ''}">
        <div class="dx-tel-panel-title">${esc(sec.title_fa)}</div>
        ${(sec.rows || []).map((r) => `
          <div class="dx-tel-row">
            <span class="dx-tel-row-key">${esc(r.key)}</span>
            <span class="dx-tel-row-val">${esc(r.value)}</span>
          </div>`).join('')}
      </div>`;
    }).join('');

    drawSpikeMap((data.charts || {}).spike_map);
    drawCstateBars((data.charts || {}).cstate_bars);
  }

  window.dxRefreshTelemetry = fetchTelemetry;
  window.addEventListener('dx:probe-ready', (e) => {
    if (e.detail) { window.__dxLastProbe = e.detail; lastProbe = e.detail; }
    fetchTelemetry();
  });
  window.addEventListener('resize', drawSparklines);

  fetchTelemetry();
  pollTimer = setInterval(fetchTelemetry, POLL_MS);
})();
