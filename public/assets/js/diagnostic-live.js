(function () {
  const POLL_MS = 8000;
  const cfg = window.PCLAB_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  let lastFeedHash = '';
  let pollTimer = null;
  let agentTimer = null;

  const el = (id) => document.getElementById(id);

  /** Match ApiClient / tracker fingerprint so diagnostic live + report use the same user key on MariaDB. */
  function fpQuery() {
    try {
      const fp = localStorage.getItem('pclab_fp') || '';
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
          <span class="dx-tool-check">✓ PC Lab Kit</span>
          <span class="dx-tool-name">${esc(t.category)}</span>
          <span class="dx-tool-live">${t.live_count}/${t.tool_count} live${examples ? ' · ' + esc(examples) : ''}</span>
        </div>`;
      }
      const active = t.live_sample != null && t.live_sample !== 0;
      const live = active
        ? `<span class="dx-tool-live">${esc(t.live_label || '')}: ${formatSample(t.live_sample)}</span>`
        : `<span class="dx-tool-live muted">✓ Replaced</span>`;
      return `<div class="dx-tool-card${active ? ' active' : ''}" title="${esc(t.desc || t.desc_fa || '')}">
        <span class="dx-tool-check">✓ PC Lab Kit</span>
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
      list.innerHTML = `<div class="dx-history-empty">No saved tests yet.<br>Run <strong>Full Lab</strong> from Command Center — results stay on this PC.</div>`;
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
      const health = await h.json().catch(() => ({}));
      const probe = await (await fetch(`${AGENT}/probe`, { mode: 'cors' })).json();
      strip.classList.add('visible');

      const nvidia = probe.nvidia_smi || {};
      const sensors = probe.sensors || {};
      const thermal = probe.thermal || {};
      const cpuT = (thermal.cpu || {});
      const gpuT = (probe.telemetry && probe.telemetry.gpu && probe.telemetry.gpu.thermal)
        ? probe.telemetry.gpu.thermal
        : (sensors);

      setSensor('dx-s-cpu', cpuT.package_c || sensors.cpu_temp_max, '°C', 80, 90);
      setSensor('dx-s-cpu-hs', cpuT.hotspot_c || sensors.cpu_hotspot_max, '°C', 85, 95);
      setSensor('dx-s-gpu', gpuT.core_c || nvidia.temp_c || sensors.gpu_temp_max, '°C', 80, 88);
      setSensor('dx-s-gpu-hs', gpuT.hot_spot_c || nvidia.temp_hotspot_c || sensors.gpu_hotspot_max, '°C', 90, 100);
      const delta = gpuT.hotspot_delta_c != null ? gpuT.hotspot_delta_c : sensors.gpu_hotspot_delta;
      setSensor('dx-s-gpu-delta', delta, '°C', 20, 27);
      setSensor('dx-s-vram', probe.gpu?.vram_gb, ' GB', null, null);
      setSensor('dx-s-util', nvidia.gpu_util_pct || (probe.telemetry && probe.telemetry.gpu && probe.telemetry.gpu.render && probe.telemetry.gpu.render.gpu_util_pct), '%', null, null);
      setSensor('dx-s-ram', probe.ram?.total_gb, ' GB', null, null);
      setSensor('dx-s-bat', probe.battery?.health_percent || probe.battery?.estimated_charge, '%', null, null);

      const drivers = probe.drivers || {};
      const grade = drivers.grade || '—';
      const score = drivers.score != null ? drivers.score : null;
      const driverNode = el('dx-s-drivers');
      if (driverNode) {
        if (score != null) {
          driverNode.textContent = score + '/' + grade;
          driverNode.className = 'dx-sensor-val';
          if (score < 60) driverNode.classList.add('hot');
          else if (score < 80) driverNode.classList.add('warn');
        } else {
          driverNode.textContent = '—';
          driverNode.className = 'dx-sensor-val';
        }
      }

      const note = el('dx-sensor-note');
      if (note) {
        const bits = [];
        if (health.elevated === false || probe.elevated === false) {
          bits.push('Probe is not elevated — restart Start-PcLabProbe.bat as Administrator for CPU die temps.');
        }
        if (gpuT.hotspot_source === 'blackwell_therm_mmio') {
          bits.push('GPU hot spot via open-book BAR0 THERM (not NVAPI).');
        } else if (gpuT.hotspot_source && gpuT.hotspot_source !== 'unavailable') {
          bits.push('GPU hot spot via ' + gpuT.hotspot_source);
        } else if (!gpuT.hot_spot_c && !sensors.gpu_hotspot_max) {
          bits.push('GPU hot spot not readable — elevate probe for open-book MMIO on Blackwell.');
        }
        const findings = (thermal.findings || []).slice(0, 2);
        findings.forEach((f) => {
          if (f && f.title) bits.push(f.title);
        });
        if (bits.length) {
          note.hidden = false;
          note.textContent = bits.join(' · ');
        } else {
          note.hidden = true;
          note.textContent = '';
        }
      }

      const devicesForUi = { ...(probe.devices || {}) };
      if (Array.isArray(drivers.driverless) && drivers.driverless.length) {
        devicesForUi.driverless = drivers.driverless;
      }
      renderDriverActions(drivers, devicesForUi);
    } catch (_) {
      strip.classList.remove('visible');
      const note = el('dx-sensor-note');
      if (note) { note.hidden = true; }
      const box = el('dx-driver-actions');
      if (box) { box.hidden = true; box.innerHTML = ''; }
    }
  }

  function driverConfBadge(row) {
    const parts = [];
    const pct = row.match_confidence_pct;
    if (pct != null && pct !== '') parts.push(`${pct}%`);
    else if (row.match_confidence) parts.push(String(row.match_confidence));
    if (row.success_rate != null && row.success_rate !== '') {
      parts.push(`${Math.round(Number(row.success_rate))}% local success`);
    }
    return parts.length ? `<span class="dx-driver-conf">${esc(parts.join(' · '))}</span>` : '';
  }

  function renderDriverActions(drivers, devices) {
    if (window.PcLabDrivers?.render) {
      window.PcLabDrivers.render(drivers, devices);
      return;
    }
    const box = el('dx-driver-actions');
    if (!box) return;
    const actions = (drivers.actions || []).filter((a) => a && (a.severity === 'critical' || a.severity === 'warn')).slice(0, 8);
    const driverless = (devices.driverless || []).slice(0, 4);
    const queue = (drivers.install_queue || []).filter((s) => s && s.status !== 'ok').slice(0, 6);
    if (!actions.length && !driverless.length && !queue.length) {
      box.hidden = true;
      box.innerHTML = '';
      return;
    }
    box.hidden = false;

    const hwId = (a) => {
      const bits = [];
      if (a.vendor_id) bits.push('VEN_' + String(a.vendor_id).toUpperCase());
      if (a.device_id) bits.push('DEV_' + String(a.device_id).toUpperCase());
      if (a.instance_id && !bits.length) bits.push(String(a.instance_id).slice(0, 48));
      return bits.length ? bits.join(' · ') : '';
    };

    const actionHtml = actions.map((a) => {
      const primary = a.primary_link && a.primary_link.url ? a.primary_link : null;
      const links = (a.links || []).slice(0, 2).map((l) =>
        `<a href="${esc(l.url)}" target="_blank" rel="noopener">${esc(l.label || 'Download')}</a>`
      ).join(' · ');
      const conf = driverConfBadge(a);
      const ids = hwId(a);
      const primaryBtn = primary
        ? `<a href="${esc(primary.url)}" class="dx-btn primary dx-driver-primary" target="_blank" rel="noopener">${esc(primary.label || 'Open package')}</a>`
        : '';
      const installBtn = `<button type="button" class="dx-btn ghost dx-driver-install" data-instance="${esc(a.instance_id || '')}" data-category="${esc(a.category || '')}" data-queue="">Install</button>`;
      return `<div class="dx-driver-card ${esc(a.severity || '')}">
        <div class="dx-driver-card-head"><strong>${esc(a.title || '')}</strong>${conf}</div>
        <span class="muted fs-xs">${esc(a.detail || '')}</span>
        ${ids ? `<span class="muted fs-xs dx-driver-hwid">${esc(ids)}</span>` : ''}
        <div class="dx-driver-links">${primaryBtn}${installBtn}${links ? ' · ' + links : ''}</div>
      </div>`;
    }).join('');

    const missingHtml = driverless.map((d) => {
      const ids = hwId(d);
      const conf = driverConfBadge(d);
      const primary = d.primary_link && d.primary_link.url ? d.primary_link : null;
      const links = (d.links || []).slice(0, 2).map((l) =>
        `<a href="${esc(l.url)}" target="_blank" rel="noopener">${esc(l.label || 'Download')}</a>`
      ).join(' · ');
      const primaryBtn = primary
        ? `<a href="${esc(primary.url)}" class="dx-btn primary dx-driver-primary" target="_blank" rel="noopener">${esc(primary.label || 'Open package')}</a>`
        : '';
      const installBtn = `<button type="button" class="dx-btn ghost dx-driver-install" data-instance="${esc(d.instance_id || '')}" data-category="${esc(d.category || '')}" data-queue="">Install</button>`;
      return `<div class="dx-driver-card critical">
        <div class="dx-driver-card-head"><strong>No driver: ${esc(d.name || 'Unknown')}</strong>${conf}</div>
       <span class="muted fs-xs">${esc(d.problem_message || d.category || '')}</span>
       ${ids ? `<span class="muted fs-xs dx-driver-hwid">${esc(ids)}</span>` : ''}
       <div class="dx-driver-links">${primaryBtn}${installBtn}${links ? ' · ' + links : ''}</div>
      </div>`;
    }).join('');

    const queueHtml = queue.length ? `<div class="dx-driver-queue">
      <h5 class="dx-driver-queue-title">Install queue</h5>
      ${queue.map((s) => {
        const pl = s.primary_link && s.primary_link.url ? s.primary_link : ((s.links || [])[0] || null);
        const link = pl ? `<a href="${esc(pl.url)}" target="_blank" rel="noopener">${esc(pl.label || 'Open')}</a>` : '';
        const conf = driverConfBadge(s);
        const ver = s.package_version ? ` · pkg ${esc(s.package_version)}` : '';
        const installBtn = `<button type="button" class="dx-btn ghost dx-driver-install" data-instance="" data-category="${esc(s.id || '')}" data-queue="${esc(s.id || '')}">Install</button>`;
        return `<div class="dx-driver-queue-row">
          <span class="dx-driver-queue-status ${esc(s.status || '')}">${esc(s.status || '')}</span>
          <span><strong>${esc(s.label || s.id || '')}</strong>${conf}${ver}
          <span class="muted fs-xs"> — ${esc(s.why || '')}</span></span>
          ${installBtn} ${link}
        </div>`;
      }).join('')}
    </div>` : '';

    box.innerHTML = `<div class="dx-driver-head">
        <h4 class="dx-driver-title">Driver advisor</h4>
        <div class="dx-driver-toolbar">
          <button type="button" class="dx-btn ghost" id="dx-driver-rescan">Rescan drivers</button>
          <button type="button" class="dx-btn ghost" id="dx-driver-wu">Scan Windows Update drivers</button>
        </div>
      </div>
      <p class="muted fs-xs">Score ${esc(String(drivers.score ?? '—'))} / ${esc(drivers.grade || '—')} — chipset → GPU → audio → network. Click <strong>Install</strong> for the matched latest package (confirm each step).</p>
      ${queueHtml}${missingHtml}${actionHtml}`;

    document.getElementById('dx-driver-rescan')?.addEventListener('click', () => rescanDrivers(false));
    document.getElementById('dx-driver-wu')?.addEventListener('click', () => rescanDrivers(true));
    box.querySelectorAll('.dx-driver-install').forEach((btn) => {
      btn.addEventListener('click', () => installDriver(btn));
    });
  }

  async function installDriver(btn) {
    const instanceId = btn.getAttribute('data-instance') || '';
    const category = btn.getAttribute('data-category') || '';
    const queueId = btn.getAttribute('data-queue') || '';
    const label = category || instanceId || 'driver';
    if (!window.confirm(`Install the matched latest driver for ${label}? This may download a vendor package or open the GPU updater.`)) {
      return;
    }
    const note = el('dx-sensor-note');
    btn.disabled = true;
    try {
      if (note) {
        note.hidden = false;
        note.textContent = 'Installing driver package…';
      }
      const res = await fetch(`${AGENT}/drivers/install`, {
        method: 'POST',
        mode: 'cors',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          confirm: true,
          instance_id: instanceId,
          category,
          queue_id: queueId,
        }),
      });
      const data = await res.json();
      if (note) {
        note.hidden = false;
        note.textContent = data.ok
          ? `Install ${data.status || 'done'}${data.package_version ? ' · ' + data.package_version : ''}. Rescanning…`
          : (`Install failed: ${data.error || data.status || 'unknown'}`);
      }
      await rescanDrivers(false);
    } catch (e) {
      if (note) {
        note.hidden = false;
        note.textContent = 'Install request failed — is Probe running and elevated?';
      }
    } finally {
      btn.disabled = false;
    }
  }

  async function rescanDrivers(includeWu) {
    const box = el('dx-driver-actions');
    const note = el('dx-sensor-note');
    try {
      if (note) {
        note.hidden = false;
        note.textContent = includeWu
          ? 'Scanning Windows Update for drivers (may take several minutes)…'
          : 'Rescanning drivers…';
      }
      const url = includeWu ? `${AGENT}/drivers?wu=1` : `${AGENT}/drivers`;
      const res = await fetch(url, { mode: 'cors' });
      if (!res.ok) throw new Error('drivers endpoint failed');
      const report = await res.json();
      const drivers = report.drivers || report;
      const devices = report.devices || {};
      if (window.__dxLastProbe) {
        window.__dxLastProbe.drivers = drivers;
        window.__dxLastProbe.devices = devices;
      } else {
        window.__dxLastProbe = { drivers, devices };
      }
      window.dispatchEvent(new CustomEvent('dx:drivers-updated', { detail: { drivers, devices } }));

      const driverNode = el('dx-s-drivers');
      if (driverNode && drivers.score != null) {
        driverNode.textContent = drivers.score + '/' + (drivers.grade || '—');
        driverNode.className = 'dx-sensor-val';
        if (drivers.score < 60) driverNode.classList.add('hot');
        else if (drivers.score < 80) driverNode.classList.add('warn');
      }
      renderDriverActions(drivers, devices);
      if (note) {
        note.hidden = false;
        note.textContent = includeWu
          ? `WU scan done — ${drivers.summary?.wu_candidates ?? 0} optional driver candidate(s).`
          : 'Driver rescan complete.';
      }
    } catch (_) {
      if (note) {
        note.hidden = false;
        note.textContent = 'Could not reach Probe /drivers. Is Start-PcLabProbe.bat running?';
      }
      if (box) box.hidden = false;
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
