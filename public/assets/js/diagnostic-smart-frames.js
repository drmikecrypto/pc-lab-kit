/**
 * SMART / NVMe health panel + PresentMon capture / CapFrameX-lite Session Review.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';

  let sessionsCache = [];
  let sessionA = null;
  let sessionB = null;

  function el(id) {
    return document.getElementById(id);
  }

  function esc(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function csrfHeaders() {
    const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    return { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t };
  }

  async function probeJsonHeaders() {
    if (window.PcLabProbeAuth) {
      await window.PcLabProbeAuth.ensure();
      return window.PcLabProbeAuth.jsonHeaders();
    }
    return { 'Content-Type': 'application/json' };
  }

  function deviceHint(row, index) {
    if (row.device) return String(row.device);
    if (row.serial) return '\\\\.\\PhysicalDrive' + index;
    return '\\\\.\\PhysicalDrive' + index;
  }

  function depthBadge(depth, admin) {
    const d = String(depth || 'os_reliability');
    const elevated = /elevated|ioctl|smartctl|admin|nvme_log/i.test(d) || !!admin;
    const cls = elevated ? (admin ? 'is-admin' : 'is-elevated') : '';
    return `<span class="dx-smart-depth-badge ${cls}" title="${esc(d)}">${esc(d)}</span>`;
  }

  async function enqueueSelfTest(device, type) {
    const st = el('dx-smart-selftest-status');
    if (st) st.textContent = `Enqueueing ${type} self-test…`;
    try {
      const res = await fetch(AGENT() + '/storage/smart/self-test', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify({ device, type }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data.ok === false) {
        throw new Error(data.note || data.error || `HTTP ${res.status}`);
      }
      if (st) st.textContent = data.note || `${type} self-test enqueued on ${device}`;
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  async function refreshSmart() {
    const box = el('dx-smart-body');
    if (!box) return;
    box.innerHTML = `<p class="muted fs-sm">Loading SMART…</p>`;
    try {
      const res = await fetch(AGENT() + '/storage/smart', { mode: 'cors' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      window.__dxLastSmart = data;
      const rows = data.storage?.smart || [];
      const detailed = data.nvme_detailed || [];
      const byName = {};
      for (const d of detailed) {
        if (d.friendly_name) byName[String(d.friendly_name).toLowerCase()] = d;
      }
      const enqueue = data.storage?.self_test_enqueue || {};
      if (!rows.length) {
        box.innerHTML = `<div class="dx-panel-empty"><strong>No reliability counters</strong>
          <p class="muted fs-sm">StorageReliability may be empty on this OS. Install smartctl for deeper SMART / self-test.</p></div>`;
        return;
      }
      const canTest = !!enqueue.available;
      box.innerHTML = `<table class="dx-smart-table"><thead><tr>
        <th>Drive</th><th>Health</th><th>Temp</th><th>Wear</th><th>POH</th><th>Depth</th><th>Self-test</th>
      </tr></thead><tbody>${rows
        .map((r, i) => {
          const deep = byName[String(r.friendly_name || '').toLowerCase()] || {};
          const depth = deep.smart_depth || r.smart_depth || 'os_reliability';
          const admin = !!(deep.admin_smart || r.admin_smart);
          const dev = esc(deviceHint(r, i));
          const actions = canTest
            ? `<button type="button" class="dx-btn ghost dx-smart-st" data-device="${dev}" data-type="short">Short</button>
               <button type="button" class="dx-btn ghost dx-smart-st" data-device="${dev}" data-type="long">Long</button>`
            : `<span class="muted fs-xs">—</span>`;
          return `<tr>
        <td>${esc(r.friendly_name || '—')}${r.is_nvme ? ' <span class="muted fs-xs">NVMe</span>' : ''}</td>
        <td>${esc(r.health_status || '—')}</td>
        <td>${r.temperature_c != null ? esc(r.temperature_c) + '°C' : '—'}</td>
        <td>${r.wear_pct != null ? esc(r.wear_pct) + '%' : '—'}</td>
        <td>${r.power_on_hours != null ? esc(r.power_on_hours) : '—'}</td>
        <td>${depthBadge(depth, admin)}</td>
        <td class="dx-smart-actions">${actions}</td>
      </tr>`;
        })
        .join('')}</tbody></table>
        <p class="muted fs-xs mt-1" id="dx-smart-selftest-status">${esc(
          canTest
            ? enqueue.note || 'smartctl ready — Short/Long enqueue Admin SMART self-tests.'
            : enqueue.note || 'Install smartctl (or tools/smartctl.exe) for self-test enqueue.'
        )}</p>`;
      box.querySelectorAll('.dx-smart-st').forEach((btn) => {
        btn.addEventListener('click', () => {
          enqueueSelfTest(btn.getAttribute('data-device'), btn.getAttribute('data-type') || 'short');
        });
      });
    } catch (e) {
      box.innerHTML = `<div class="dx-panel-empty is-error"><strong>SMART failed</strong>
        <p class="muted fs-sm">${esc(e.message || e)}</p></div>`;
    }
  }

  function drawSeries(data) {
    const canvas = el('dx-pm-spark');
    if (!canvas) return;
    const series = data.fps_series || data.frametime_series || [];
    if (!series.length) {
      canvas.hidden = true;
      return;
    }
    canvas.hidden = false;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    const vals = series.map(Number).filter((n) => Number.isFinite(n));
    if (vals.length < 2) return;
    const min = Math.min(...vals);
    const max = Math.max(...vals);
    const span = Math.max(1e-6, max - min);
    ctx.strokeStyle = 'rgba(34, 211, 238, 0.85)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    vals.forEach((v, i) => {
      const x = (i / (vals.length - 1)) * (w - 4) + 2;
      const y = h - 4 - ((v - min) / span) * (h - 8);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  }

  function drawHistogram(session) {
    const canvas = el('dx-pm-hist');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    const hist = session?.histogram;
    const counts = hist?.counts || [];
    if (!counts.length) {
      ctx.fillStyle = 'rgba(148,163,184,0.7)';
      ctx.font = '12px sans-serif';
      ctx.fillText('No histogram yet', 12, h / 2);
      return;
    }
    const maxC = Math.max(...counts.map(Number), 1);
    const barW = (w - 16) / counts.length;
    counts.forEach((c, i) => {
      const bh = (Number(c) / maxC) * (h - 20);
      const x = 8 + i * barW;
      const y = h - 8 - bh;
      ctx.fillStyle = 'rgba(34, 211, 238, 0.55)';
      ctx.fillRect(x + 1, y, Math.max(1, barW - 2), bh);
    });
    if (hist.min != null && hist.max != null) {
      ctx.fillStyle = 'rgba(148,163,184,0.85)';
      ctx.font = '11px ui-monospace, monospace';
      ctx.fillText(`${hist.min}–${hist.max} FPS`, 8, 14);
    }
  }

  function drawCompare(a, b) {
    const canvas = el('dx-pm-compare');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);

    function strokeSeries(series, color) {
      const vals = (series || []).map(Number).filter((n) => Number.isFinite(n));
      if (vals.length < 2) return;
      const min = Math.min(...vals);
      const max = Math.max(...vals);
      const span = Math.max(1e-6, max - min);
      ctx.strokeStyle = color;
      ctx.lineWidth = 1.4;
      ctx.beginPath();
      vals.forEach((v, i) => {
        const x = (i / (vals.length - 1)) * (w - 4) + 2;
        const y = h - 4 - ((v - min) / span) * (h - 8);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.stroke();
    }

    strokeSeries(a?.fps_series, 'rgba(34, 211, 238, 0.9)');
    if (b?.fps_series?.length) {
      strokeSeries(b.fps_series, 'rgba(251, 146, 60, 0.85)');
    }
  }

  function renderStatStrip(a, b) {
    const box = el('dx-pm-stat-strip');
    if (!box) return;
    if (!a) {
      box.innerHTML = `<p class="muted fs-sm">No saved sessions yet — stop a PresentMon run or import CapFrameX JSON.</p>`;
      return;
    }
    const cell = (label, val, unit = '') =>
      `<div class="dx-pm-stat"><span class="dx-pm-stat-label">${esc(label)}</span><strong>${esc(val ?? '—')}${unit}</strong></div>`;
    let html = `<div class="dx-pm-stat-row is-a">
      ${cell('Avg', a.fps_avg)}
      ${cell('1% low', a.fps_1pct_low)}
      ${cell('0.1% low', a.fps_0_1pct_low)}
      ${cell('P99', a.frametime_p99_ms, ' ms')}
      ${cell('Duration', a.duration_s, ' s')}
      ${cell('Samples', a.sample_count)}
    </div>`;
    if (b) {
      const d = (x, y) => (x != null && y != null ? (Number(x) - Number(y)).toFixed(1) : '—');
      html += `<div class="dx-pm-stat-row is-b">
        ${cell('B avg', b.fps_avg)}
        ${cell('B 1%', b.fps_1pct_low)}
        ${cell('B 0.1%', b.fps_0_1pct_low)}
        ${cell('Δ avg', d(a.fps_avg, b.fps_avg))}
        ${cell('Δ 1%', d(a.fps_1pct_low, b.fps_1pct_low))}
        ${cell('Source', `${a.source || '—'} / ${b.source || '—'}`)}
      </div>`;
    }
    box.innerHTML = html;
  }

  function renderSpikes(session) {
    const box = el('dx-pm-spikes');
    if (!box) return;
    const spikes = session?.spikes?.spikes || [];
    const thr = session?.spikes?.threshold_ms;
    const ctxNote = session?.context?.note;
    const ctxOk = !!(session?.context?.available || session?.spikes?.context_attached);
    if (!spikes.length) {
      box.innerHTML = `<p class="muted fs-sm">No stutter spikes above threshold${thr != null ? ` (${thr} ms)` : ''}.</p>
        ${ctxNote && !ctxOk ? `<p class="muted fs-xs">${esc(ctxNote)}</p>` : ''}`;
      return;
    }
    const fmt = (v, u = '') => (v != null && v !== '' ? `${esc(v)}${u}` : '—');
    box.innerHTML = `<div class="dx-pm-spikes-head">Spikes (≥ ${esc(thr ?? '—')} ms) · ${spikes.length}${
      ctxOk ? ' · temps from Probe ring' : ctxNote ? ` · ${esc(ctxNote)}` : ' · no thermal context'
    }</div>
      <table class="dx-smart-table dx-pm-spikes-table"><thead><tr>
        <th>#</th><th>t (ms)</th><th>ft</th><th>FPS</th><th>CPU</th><th>GPU</th><th>Hotspot</th><th>Pkg W</th><th>Cause</th>
      </tr></thead><tbody>${spikes
        .map(
          (s, i) => `<tr>
        <td>${i + 1}</td>
        <td>${esc(s.t_ms)}</td>
        <td>${esc(s.ft_ms)}</td>
        <td>${esc(s.fps ?? '—')}</td>
        <td>${fmt(s.cpu_c, '°')}</td>
        <td>${fmt(s.gpu_c, '°')}</td>
        <td>${fmt(s.gpu_hotspot_c, '°')}</td>
        <td>${fmt(s.package_w)}</td>
        <td>${esc(s.likely_cause || '—')}</td>
      </tr>`
        )
        .join('')}</tbody></table>`;
  }

  function drawTrend(sessions) {
    const canvas = el('dx-pm-trend');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    ctx.clearRect(0, 0, w, h);
    const list = (sessions || []).slice(0, 12).reverse();
    if (list.length < 1) {
      ctx.fillStyle = 'rgba(148,163,184,0.7)';
      ctx.font = '12px sans-serif';
      ctx.fillText('No sessions yet', 12, h / 2);
      canvas.onclick = null;
      return;
    }
    const lows = list.map((s) => Number(s.fps_1pct_low)).filter((n) => Number.isFinite(n));
    const avgs = list.map((s) => Number(s.fps_avg)).filter((n) => Number.isFinite(n));
    const vals = [...lows, ...avgs];
    const min = vals.length ? Math.min(...vals) : 0;
    const max = vals.length ? Math.max(...vals) : 1;
    const span = Math.max(1e-6, max - min);
    const barW = (w - 16) / list.length;
    list.forEach((s, i) => {
      const low = Number(s.fps_1pct_low);
      if (!Number.isFinite(low)) return;
      const bh = ((low - min) / span) * (h - 18);
      const x = 8 + i * barW;
      ctx.fillStyle = 'rgba(34, 211, 238, 0.65)';
      ctx.fillRect(x + 2, h - 6 - bh, Math.max(2, barW - 4), bh);
      const avg = Number(s.fps_avg);
      if (Number.isFinite(avg)) {
        const y = h - 6 - ((avg - min) / span) * (h - 18);
        ctx.fillStyle = 'rgba(251, 146, 60, 0.9)';
        ctx.fillRect(x + 2, y - 1, Math.max(2, barW - 4), 2);
      }
    });
    canvas.onclick = (ev) => {
      const rect = canvas.getBoundingClientRect();
      const x = ((ev.clientX - rect.left) / rect.width) * w;
      const i = Math.min(list.length - 1, Math.max(0, Math.floor((x - 8) / barW)));
      const id = list[i]?.id;
      if (!id) return;
      const aSel = el('dx-pm-session-a');
      if (aSel) {
        aSel.value = id;
        selectSessions(id, el('dx-pm-session-b')?.value || '');
      }
    };
  }

  function sessionLabel(s) {
    const src = s.source === 'import' ? 'CX' : 'PM';
    const avg = s.fps_avg != null ? `${s.fps_avg} avg` : 'n/a';
    const low = s.fps_1pct_low != null ? ` · 1% ${s.fps_1pct_low}` : '';
    const lab = s.label || s.process_name || s.id;
    return `[${src}] ${lab} · ${avg}${low}`;
  }

  function fillSessionSelects(preferId) {
    const aSel = el('dx-pm-session-a');
    const bSel = el('dx-pm-session-b');
    if (!aSel || !bSel) return;
    const prevA = preferId || aSel.value;
    const prevB = bSel.value;
    aSel.innerHTML = sessionsCache.length
      ? sessionsCache.map((s) => `<option value="${esc(s.id)}">${esc(sessionLabel(s))}</option>`).join('')
      : `<option value="">— no sessions —</option>`;
    bSel.innerHTML =
      `<option value="">— none —</option>` +
      sessionsCache.map((s) => `<option value="${esc(s.id)}">${esc(sessionLabel(s))}</option>`).join('');
    if (prevA && [...aSel.options].some((o) => o.value === prevA)) aSel.value = prevA;
    if (prevB && [...bSel.options].some((o) => o.value === prevB)) bSel.value = prevB;
  }

  async function loadSessionDetail(id) {
    if (!id) return null;
    const res = await fetch(AGENT() + `/presentmon/sessions/${encodeURIComponent(id)}`, { mode: 'cors' });
    const data = await res.json().catch(() => ({}));
    if (!data.ok || !data.session) throw new Error(data.message || data.error || 'Session not found');
    return data.session;
  }

  async function refreshReview(preferId) {
    try {
      const res = await fetch(AGENT() + '/presentmon/sessions?limit=20', { mode: 'cors' });
      const data = await res.json().catch(() => ({}));
      sessionsCache = data.sessions || [];
      fillSessionSelects(preferId);
      drawTrend(sessionsCache);
      const aId = el('dx-pm-session-a')?.value;
      if (!aId) {
        sessionA = null;
        sessionB = null;
        renderStatStrip(null);
        drawHistogram(null);
        drawCompare(null, null);
        renderSpikes(null);
        drawTrend(sessionsCache);
        if (data.presentmon_missing && el('dx-pm-status') && !el('dx-pm-status').textContent) {
          el('dx-pm-status').textContent = data.note || 'PresentMon missing — CapFrameX import still works.';
        }
        return;
      }
      await selectSessions(aId, el('dx-pm-session-b')?.value || '');
    } catch (e) {
      const box = el('dx-pm-spikes');
      if (box) box.innerHTML = `<p class="muted fs-sm is-error">${esc(e.message || e)}</p>`;
    }
  }

  async function selectSessions(aId, bId) {
    try {
      sessionA = aId ? await loadSessionDetail(aId) : null;
      sessionB = bId ? await loadSessionDetail(bId) : null;
      renderStatStrip(sessionA, sessionB);
      drawHistogram(sessionA);
      drawCompare(sessionA, sessionB);
      renderSpikes(sessionA);
      if (sessionA) {
        drawSeries(sessionA);
        window.__dxLastPresentMon = sessionA;
      }
    } catch (e) {
      renderSpikes(null);
      const box = el('dx-pm-spikes');
      if (box) box.innerHTML = `<p class="muted fs-sm is-error">${esc(e.message || e)}</p>`;
    }
  }

  async function importCapFrameXFile(file) {
    const st = el('dx-pm-status');
    if (st) st.textContent = `Importing ${file.name}…`;
    try {
      const text = await file.text();
      const res = await fetch(AGENT() + '/presentmon/sessions/import', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify({ json: text, label: file.name.replace(/\.json$/i, '') }),
      });
      const data = await res.json().catch(() => ({}));
      if (!data.ok) throw new Error(data.message || data.error || `HTTP ${res.status}`);
      if (st) st.textContent = data.message || `Imported ${data.id}`;
      await refreshReview(data.id);
      if (data.session) await pushPresentToLab(data.session);
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  async function pushPresentToLab(data) {
    window.__dxLastPresentMon = data;
    try {
      sessionStorage.setItem('pclab_last_presentmon', JSON.stringify(data));
    } catch (_) {}
    try {
      await fetch('/api/diagnostic/telemetry/present', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({
          gaming: {
            fps_avg: data.fps_avg,
            fps_1pct_low: data.fps_1pct_low,
            fps_0_1pct_low: data.fps_0_1pct_low,
            frametime_p99_ms: data.frametime_p99_ms,
            source: data.source || 'presentmon',
            methodology: data.methodology,
            samples: data.sample_count,
          },
          presentmon: data,
        }),
      });
    } catch (_) {}
  }

  function setSessionButtons(running) {
    const start = el('dx-pm-session-start');
    const stop = el('dx-pm-session-stop');
    if (start) start.disabled = !!running;
    if (stop) stop.disabled = !running;
  }

  async function capturePresentMon() {
    const st = el('dx-pm-status');
    const sec = Math.max(3, Math.min(120, Number(el('dx-pm-seconds')?.value || 10)));
    if (st) st.textContent = `Capturing ${sec}s…`;
    try {
      const res = await fetch(AGENT() + `/presentmon/capture?seconds=${sec}`, { mode: 'cors' });
      const data = await res.json().catch(() => ({}));
      if (!data.available) {
        if (st) st.textContent = data.note || data.error || 'PresentMon not available';
        return;
      }
      await pushPresentToLab(data);
      drawSeries(data);
      if (st) {
        st.textContent = `FPS avg ${data.fps_avg ?? '—'} · 1% ${data.fps_1pct_low ?? '—'} · 0.1% ${data.fps_0_1pct_low ?? '—'} · P99 ${data.frametime_p99_ms ?? '—'} ms`;
      }
      if (data.session_id) await refreshReview(data.session_id);
      else await refreshReview();
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  async function useForegroundProcess() {
    const st = el('dx-pm-status');
    try {
      const res = await fetch(AGENT() + '/presentmon/session/foreground', { mode: 'cors' });
      const data = await res.json().catch(() => ({}));
      if (data.process_name && el('dx-pm-process')) {
        el('dx-pm-process').value = data.process_name;
      }
      if (st) st.textContent = data.note || (data.process_name ? `Foreground: ${data.process_name}` : 'No foreground process');
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  async function exportCapFrameX() {
    const st = el('dx-pm-status');
    const id = el('dx-pm-session-a')?.value || sessionA?.id;
    if (!id) {
      if (st) st.textContent = 'Select Session A to export';
      return;
    }
    if (st) st.textContent = 'Exporting CapFrameX JSON…';
    try {
      const res = await fetch(AGENT() + `/presentmon/sessions/${encodeURIComponent(id)}/export`, { mode: 'cors' });
      const data = await res.json().catch(() => ({}));
      if (!data.ok || !data.export) throw new Error(data.message || data.error || 'Export failed');
      const blob = new Blob([JSON.stringify(data.export, null, 2)], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = data.filename || `pclab_${id}_capframex.json`;
      a.click();
      URL.revokeObjectURL(a.href);
      if (st) st.textContent = `Exported ${a.download}`;
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  async function startSession() {
    const st = el('dx-pm-status');
    if (st) st.textContent = 'Starting PresentMon session…';
    try {
      const process_name = (el('dx-pm-process')?.value || '').trim();
      const res = await fetch(AGENT() + '/presentmon/session/start', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify(process_name ? { process_name } : {}),
      });
      const data = await res.json().catch(() => ({}));
      if (!data.ok && !data.running) {
        if (st) st.textContent = data.note || data.error || 'Could not start session';
        setSessionButtons(false);
        return;
      }
      setSessionButtons(true);
      if (st) st.textContent = data.note || data.process_note || 'Session running — stop when ready to review';
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
      setSessionButtons(false);
    }
  }

  async function stopSession() {
    const st = el('dx-pm-status');
    if (st) st.textContent = 'Stopping & parsing session…';
    try {
      const res = await fetch(AGENT() + '/presentmon/session/stop', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: '{}',
      });
      const data = await res.json().catch(() => ({}));
      setSessionButtons(false);
      if (!data.available && data.sample_count == null) {
        if (st) st.textContent = data.note || data.error || 'No session data';
        return;
      }
      await pushPresentToLab(data);
      drawSeries(data);
      if (st) {
        st.textContent = `Session ${data.duration_s ?? '—'}s · FPS avg ${data.fps_avg ?? '—'} · 1% ${data.fps_1pct_low ?? '—'} · 0.1% ${data.fps_0_1pct_low ?? '—'} · n=${data.sample_count ?? 0}`;
      }
      await refreshReview(data.session_id || null);
    } catch (e) {
      setSessionButtons(false);
      if (st) st.textContent = e.message || String(e);
    }
  }

  async function refreshSessionStatus() {
    try {
      const res = await fetch(AGENT() + '/presentmon/session/status', { mode: 'cors' });
      const data = await res.json().catch(() => ({}));
      setSessionButtons(!!data.running);
    } catch (_) {}
  }

  function bind() {
    el('dx-smart-refresh')?.addEventListener('click', refreshSmart);
    el('dx-pm-capture')?.addEventListener('click', capturePresentMon);
    el('dx-pm-session-start')?.addEventListener('click', startSession);
    el('dx-pm-session-stop')?.addEventListener('click', stopSession);
    el('dx-pm-use-fg')?.addEventListener('click', useForegroundProcess);
    el('dx-pm-export-cx')?.addEventListener('click', exportCapFrameX);
    el('dx-pm-review-refresh')?.addEventListener('click', () => refreshReview());
    el('dx-pm-session-a')?.addEventListener('change', () => {
      selectSessions(el('dx-pm-session-a').value, el('dx-pm-session-b')?.value || '');
    });
    el('dx-pm-session-b')?.addEventListener('change', () => {
      selectSessions(el('dx-pm-session-a')?.value || '', el('dx-pm-session-b').value);
    });
    el('dx-pm-import-file')?.addEventListener('change', (ev) => {
      const f = ev.target.files && ev.target.files[0];
      if (f) importCapFrameXFile(f);
      ev.target.value = '';
    });
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'full' || ev.detail?.tab === 'command' || ev.detail?.tab === 'advanced') {
        refreshSmart();
        refreshSessionStatus();
        refreshReview();
      }
    });
    if (el('dx-smart-body')) refreshSmart();
    refreshSessionStatus();
    refreshReview();
  }

  window.PcLabSmartFrames = {
    refreshSmart,
    capturePresentMon,
    startSession,
    stopSession,
    refreshReview,
    importCapFrameXFile,
    exportCapFrameX,
    useForegroundProcess,
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
