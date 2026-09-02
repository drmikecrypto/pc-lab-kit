/**
 * SMART / NVMe health panel + PresentMon capture / session into lab context.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';

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
            source: 'presentmon',
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
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  async function startSession() {
    const st = el('dx-pm-status');
    if (st) st.textContent = 'Starting PresentMon session…';
    try {
      const res = await fetch(AGENT() + '/presentmon/session/start', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify({}),
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
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'full' || ev.detail?.tab === 'command' || ev.detail?.tab === 'advanced') {
        refreshSmart();
        refreshSessionStatus();
      }
    });
    if (el('dx-smart-body')) refreshSmart();
    refreshSessionStatus();
  }

  window.PcLabSmartFrames = { refreshSmart, capturePresentMon, startSession, stopSession };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
