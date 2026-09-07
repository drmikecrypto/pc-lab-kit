/**
 * Shop fleet — discover loopback probes + queue burn-in.
 */
(function () {
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

  async function discover() {
    const box = el('dx-fleet-list');
    if (!box) return;
    box.innerHTML = `<p class="muted fs-sm">Scanning loopback probes…</p>`;
    try {
      const res = await fetch('/api/diagnostic/fleet/discover', { headers: csrfHeaders() });
      const data = await res.json().catch(() => ({}));
      const list = Array.isArray(data.probes) ? data.probes : [];
      if (!list.length) {
        box.innerHTML = `<div class="dx-panel-empty"><strong>No probes found</strong>
          <p class="muted fs-sm">Start the local Probe (or set PCLAB_FLEET_SCAN for multi-port shop floor).</p></div>`;
        return;
      }
      box.innerHTML = list
        .map((h) => {
          const port = h.port || 18765;
          const health = h.health || {};
          const up = health.ok ? 'online' : 'unknown';
          return `<article class="dx-fleet-card" data-port="${esc(port)}">
            <strong>127.0.0.1:${esc(port)}</strong>
            <span class="muted fs-xs">${esc(up)} · v${esc(health.version || '—')} · ${health.service_mode ? 'service' : 'tray'}</span>
            <button type="button" class="dx-btn ghost dx-fleet-burn" data-port="${esc(port)}">Queue burn-in</button>
          </article>`;
        })
        .join('');
      box.querySelectorAll('.dx-fleet-burn').forEach((btn) => {
        btn.addEventListener('click', () => burnIn(btn.getAttribute('data-port')));
      });
    } catch (e) {
      box.innerHTML = `<div class="dx-panel-empty is-error"><strong>Discover failed</strong>
        <p class="muted fs-sm">${esc(e.message || e)}</p></div>`;
    }
  }

  async function burnIn(port) {
    const st = el('dx-fleet-status');
    if (st) st.textContent = 'Queuing…';
    try {
      const res = await fetch('/api/diagnostic/fleet/burn-in', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({
          targets: ['local'],
          profile: 'deep',
          probe_base: `http://127.0.0.1:${port || 18765}`,
          duration_hours: 24,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
      if (st) st.textContent = `Queued ${data.queued || 0} job(s) · ${esc(data.probe_base || '')}`;
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  function bind() {
    el('dx-fleet-refresh')?.addEventListener('click', discover);
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'full') discover();
    });
    if (el('dx-fleet-list')) discover();
  }

  window.PcLabFleet = { discover, burnIn };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
