/**
 * SMART / NVMe health panel + PresentMon capture into lab context.
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
        <td class="muted fs-xs">${esc(r.smart_depth || 'os_reliability')}</td>
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

  async function capturePresentMon() {
    const st = el('dx-pm-status');
    const sec = Math.max(3, Math.min(60, Number(el('dx-pm-seconds')?.value || 10)));
    if (st) st.textContent = `Capturing ${sec}s…`;
    try {
      const res = await fetch(AGENT() + `/presentmon/capture?seconds=${sec}`, { mode: 'cors' });
      const data = await res.json().catch(() => ({}));
      if (!data.available) {
        if (st) st.textContent = data.note || data.error || 'PresentMon not available';
        return;
      }
      window.__dxLastPresentMon = data;
      try {
        sessionStorage.setItem('pclab_last_presentmon', JSON.stringify(data));
      } catch (_) {}
      if (st) {
        st.textContent = `FPS avg ${data.fps_avg ?? '—'} · 1% ${data.fps_1pct_low ?? '—'} · 0.1% ${data.fps_0_1pct_low ?? '—'} · P99 ${data.frametime_p99_ms ?? '—'} ms`;
      }
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
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  function bind() {
    el('dx-smart-refresh')?.addEventListener('click', refreshSmart);
    el('dx-pm-capture')?.addEventListener('click', capturePresentMon);
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'full' || ev.detail?.tab === 'command' || ev.detail?.tab === 'advanced') {
        refreshSmart();
      }
    });
    if (el('dx-smart-body')) refreshSmart();
  }

  window.PcLabSmartFrames = { refreshSmart, capturePresentMon };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
