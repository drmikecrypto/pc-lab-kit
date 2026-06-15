(function () {
  const POLL_MS = 8000;
  const cfg = window.PCVERSE_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  let lastFeedHash = '';
  let pollTimer = null;
  let agentTimer = null;

  const el = (id) => document.getElementById(id);

  /** Match ApiClient / tracker fingerprint so diagnostic live + report use the same user key on MariaDB. */
  function fpQuery() {
    try {
      const fp = localStorage.getItem('_pcverse_fp') || '';
      return fp ? '?fp=' + encodeURIComponent(fp) : '';
    } catch (_) {
      return '';
    }
  }

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  function animateNum(node, target) {
    if (!node) return;
    const cur = parseInt(node.dataset.val || '0', 10);
    const next = parseInt(target, 10) || 0;
    if (cur === next) return;
    node.dataset.val = String(next);
    const steps = 12;
    let step = 0;
    const tick = () => {
      step++;
      const v = Math.round(cur + (next - cur) * (step / steps));
      node.textContent = v.toLocaleString('en-US');
      if (step < steps) requestAnimationFrame(tick);
      else node.textContent = next.toLocaleString('en-US');
    };
    tick();
  }

  async function fetchLive() {
    try {
      const res = await fetch('/api/diagnostic/live' + fpQuery());
      if (!res.ok) return;
      const data = await res.json();
      renderLive(data);
    } catch (_) {}
  }

  function renderLive(data) {
    const stats = data.stats || {};
    animateNum(el('dx-stat-today'), stats.scans_today);
    animateNum(el('dx-stat-hour'), stats.scans_hour);
    animateNum(el('dx-stat-total'), stats.total_scans);
    animateNum(el('dx-stat-full'), stats.full_scans);
    const avgEl = el('dx-stat-avg');
    const toolsEl = el('dx-stat-tools');
    const upd = el('dx-live-updated');
    if (avgEl) avgEl.textContent = stats.avg_health_24h ? stats.avg_health_24h.toLocaleString('en-US') : '—';
    if (toolsEl) toolsEl.textContent = (data.tools_replaced || 80).toLocaleString('en-US');
    if (upd) upd.textContent = 'Updated: ' + new Date().toLocaleTimeString('en-US');

    renderTicker(data.feed || []);
    renderTools(data.capabilities || []);
    renderBenchmark(data.benchmark || {});
    renderHistory(data.yours || []);
    if (data.pulse && window.dxRenderPulse) window.dxRenderPulse(data.pulse);

    const banner = el('dx-replace-banner');
    if (banner) {
      const n = data.tools_replaced || 80;
      banner.innerHTML = `<strong>${n} tools unified</strong> — monitoring, benchmarks, stress, storage, RGB &amp; LCD — <strong>one local lab</strong>`;
    }
  }

  function renderTicker(feed) {
    const track = el('dx-ticker-track');
    if (!track) return;
    const hash = JSON.stringify(feed.map((f) => f.ts + f.score));
    if (hash === lastFeedHash && feed.length) return;
    lastFeedHash = hash;

    if (!feed.length) {
      track.innerHTML = `<div class="dx-ticker-item"><span class="muted">Run your first scan — the live feed starts here</span></div>`;
      return;
    }

    const items = feed.concat(feed).map((f) => {
      const temps = [];
      if (f.gpu_temp) temps.push(`GPU ${f.gpu_temp}°`);
      if (f.cpu_temp) temps.push(`CPU ${f.cpu_temp}°`);
      const extra = temps.length ? ' · ' + temps.join(' ') : '';
      return `<div class="dx-ticker-item">
        <span class="dx-ticker-score">${f.score}</span>
        <span class="dx-ticker-grade">${esc(f.grade)}</span>
        <span>${esc(f.label)}</span>
        <span class="muted">${esc(f.bottleneck_fa || f.bottleneck || '')}${extra}</span>
        <span class="muted fs-xs">${esc(f.ago)}</span>
      </div>`;
    }).join('');
    track.innerHTML = items;
  }

  function renderTools(tools) {
    const grid = el('dx-tools-grid');
    if (!grid) return;
    grid.innerHTML = tools.map((t) => {
      if (t.category) {
        const examples = (t.examples || []).slice(0, 3).join(', ');
        return `<div class="dx-tool-card active" title="${esc(examples)}">
          <span class="dx-tool-check">✓ PCVerse</span>
          <span class="dx-tool-name">${esc(t.category)}</span>
          <span class="dx-tool-live">${t.live_count}/${t.tool_count} live${examples ? ' · ' + esc(examples) : ''}</span>
        </div>`;
      }
      const active = t.live_sample != null && t.live_sample !== 0;
      const live = active
        ? `<span class="dx-tool-live">${esc(t.live_label || '')}: ${formatSample(t.live_sample)}</span>`
        : `<span class="dx-tool-live muted">✓ Replaced</span>`;
      return `<div class="dx-tool-card${active ? ' active' : ''}" title="${esc(t.desc || t.desc_fa || '')}">
        <span class="dx-tool-check">✓ PCVerse</span>
        <span class="dx-tool-name">${esc(t.name)}</span>
        ${live}
      </div>`;
    }).join('');
  }

  function formatSample(v) {
    if (typeof v === 'number') {
      if (v > 200) return v.toFixed(0);
      if (v > 10) return v.toFixed(1);
      return v.toFixed(2);
    }
    return String(v);
  }

  function tempLine(h) {
    const m = h.metrics || {};
    const gt = m.gpu_temp_max;
    const ct = m.cpu_temp_max;
    const parts = [];
    if (gt != null && gt !== '') parts.push('GPU ' + gt + '°');
    if (ct != null && ct !== '') parts.push('CPU ' + ct + '°');
    if (!parts.length) return '';
    return '<br><span class="muted fs-xs">Temps: ' + parts.join(' · ') + '</span>';
  }

  function renderBenchmark(bench) {
    const grades = bench.grades || {};
    const total = Object.values(grades).reduce((a, b) => a + b, 0) || 1;
    const order = ['A', 'B', 'C', 'D', 'F'];
    const bars = el('dx-grade-bars');
    if (bars) {
      bars.innerHTML = order.filter((g) => grades[g]).map((g) => {
        const pct = Math.round((grades[g] / total) * 100);
        return `<div class="dx-grade-row">
          <span>${g}</span>
          <div class="dx-grade-bar"><div class="dx-grade-fill" style="width:${pct}%"></div></div>
          <span>${grades[g]}</span>
        </div>`;
      }).join('') || '<p class="muted fs-xs">Grade distribution appears after a few scans.</p>';
    }

    const gpus = el('dx-gpu-bench');
    if (gpus) {
      gpus.innerHTML = (bench.top_gpus || []).map((g) => `
        <div class="dx-gpu-row">
          <span class="dx-gpu-name">${esc(g.gpu)}</span>
          <span class="dx-gpu-score">${g.avg_score}</span>
          <span class="dx-gpu-count">${g.scans}×</span>
        </div>`).join('') || '<p class="muted fs-xs">Community GPU benchmark from saved scans</p>';
    }

    const lab = bench.thermal_lab_24h || {};
    const labEl = el('dx-thermal-lab');
    const labBody = el('dx-thermal-lab-body');
    const n = parseInt(String(lab.samples || 0), 10) || 0;
    if (labEl && labBody) {
      if (n > 0) {
        labEl.hidden = false;
        const cpuA = lab.cpu_avg_c != null ? formatSample(lab.cpu_avg_c) : '—';
        const gpuA = lab.gpu_avg_c != null ? formatSample(lab.gpu_avg_c) : '—';
        const p95 = lab.gpu_p95_c != null ? lab.gpu_p95_c + '°C GPU' : '—';
        labBody.textContent =
          n +
          ' sensor samples — avg CPU ' +
          cpuA +
          '°C, GPU ' +
          gpuA +
          '°C — GPU P95: ' +
          p95 +
          ' (from saved lab reports)';
      } else {
        labEl.hidden = true;
        labBody.textContent = '';
      }
    }
  }

  function renderHistory(items) {
    const list = el('dx-history-list');
    if (!list) return;
    if (!items.length) {
      list.innerHTML = `<div class="dx-history-empty">No saved tests yet.<br>Run a quick or full scan — your history stays here.</div>`;
      return;
    }
    list.innerHTML = items.map((h) => {
      const delta = h.vs_previous && h.vs_previous.score_delta != null ? h.vs_previous.score_delta : (h.delta_score ?? null);
      let deltaHtml = '';
      if (delta != null && delta !== 0) {
        const cls = delta > 0 ? 'up' : 'down';
        const label = delta > 0 ? '+' + delta : String(delta);
        deltaHtml = `<span class="dx-history-delta ${cls}">${label}</span>`;
      }
      return `
      <div class="dx-history-item" data-token="${esc(h.token)}">
        <div class="dx-history-top">
          <span class="dx-history-score">${h.score}<small class="fs-sm muted">/${esc(h.grade)}</small></span>
          ${deltaHtml}
          <span class="dx-history-mode">${esc(h.mode)}</span>
        </div>
        <div class="dx-history-meta">
          ${h.gpu ? esc(h.gpu) + ' · ' : ''}${h.ram_gb ? h.ram_gb + 'GB · ' : ''}${esc(h.ago)}
          ${tempLine(h)}
          ${h.bottleneck_fa ? '<br><span style="color:rgba(242,159,5,0.9)">' + esc(h.bottleneck_fa) + '</span>' : ''}
          ${h.vs_previous && h.vs_previous.summary ? '<br><span class="muted fs-xs">' + esc(h.vs_previous.summary) + '</span>' : ''}
        </div>
      </div>`;
    }).join('');

    list.querySelectorAll('.dx-history-item').forEach((node) => {
      node.addEventListener('click', () => loadReport(node.dataset.token));
    });
  }

  async function loadReport(token) {
    if (!token) return;
    try {
      const res = await fetch('/api/diagnostic/report/' + encodeURIComponent(token) + fpQuery());
      const data = await res.json();
      if (data.report && window.dxShowResults) {
        const analysis = data.report.report?.analysis || data.report;
        if (data.report.comparison) {
          analysis.comparison = data.report.comparison;
        }
        window.dxShowResults(analysis, document.getElementById('dx-full-results') || document.getElementById('dx-results'));
        (document.getElementById('dx-full-results') || document.getElementById('dx-results'))?.scrollIntoView({ behavior: 'smooth' });
      }
    } catch (_) {}
  }

  async function pollAgentSensors() {
    const strip = el('dx-sensor-strip');
    if (!strip) return;
    try {
      const h = await fetch(`${AGENT}/health`, { mode: 'cors' });
      if (!h.ok) throw new Error('no agent');
      const probe = await (await fetch(`${AGENT}/probe`, { mode: 'cors' })).json();
      strip.classList.add('visible');

      const nvidia = probe.nvidia_smi || {};
      const sensors = probe.sensors || {};
      setSensor('dx-s-cpu', sensors.cpu_temp_max, '°C', 80, 90);
      setSensor('dx-s-gpu', nvidia.temp_c || sensors.gpu_temp_max, '°C', 80, 88);
      setSensor('dx-s-vram', probe.gpu?.vram_gb, ' GB', null, null);
      setSensor('dx-s-util', nvidia.gpu_util_pct, '%', null, null);
      setSensor('dx-s-ram', probe.ram?.total_gb, ' GB', null, null);
      setSensor('dx-s-bat', probe.battery?.health_percent || probe.battery?.estimated_charge, '%', null, null);
    } catch (_) {
      strip.classList.remove('visible');
    }
  }

  function setSensor(id, val, unit, warn, hot) {
    const node = el(id);
    if (!node) return;
    const v = parseFloat(val);
    if (isNaN(v) || v <= 0) {
      node.textContent = '—';
      node.className = 'dx-sensor-val';
      return;
    }
    node.textContent = (Number.isInteger(v) ? v : v.toFixed(1)) + unit;
    node.className = 'dx-sensor-val';
    if (hot && v >= hot) node.classList.add('hot');
    else if (warn && v >= warn) node.classList.add('warn');
  }

  function start() {
    fetchLive();
    pollAgentSensors();
    pollTimer = setInterval(fetchLive, POLL_MS);
    agentTimer = setInterval(pollAgentSensors, 5000);
  }

  window.addEventListener('dx:scan-complete', () => {
    fetchLive();
    pollAgentSensors();
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
