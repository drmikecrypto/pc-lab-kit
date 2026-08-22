/**
 * Optional third-party stress launchers (Prime95 / OCCT / TestMem5) via Probe.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';

  function esc(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  async function refresh() {
    const root = document.getElementById('dx-launchers');
    if (!root) return;
    try {
      const res = await fetch(AGENT() + '/launchers');
      const data = await res.json();
      const list = data.launchers || [];
      root.innerHTML = `
        <h3>External stress launchers</h3>
        <p class="muted fs-sm">Optional — launch tools you already installed. Probe overlays thermals; proprietary suites are not bundled.</p>
        <div class="dx-launchers-grid">${list
          .map(
            (l) => `<div class="dx-sensor-deck__gauge">
            <div class="dx-sensor-deck__lbl">${esc(l.label)}</div>
            <div class="muted fs-xs">${l.installed ? esc(l.path) : 'Not installed'}</div>
            <button type="button" class="dx-btn ghost mt-2" data-launch="${esc(l.id)}" ${l.installed ? '' : 'disabled'}>Launch + overlay</button>
          </div>`
          )
          .join('')}</div>
        <div id="dx-launcher-status" class="muted fs-xs mt-2"></div>`;
      root.querySelectorAll('[data-launch]').forEach((btn) => {
        btn.addEventListener('click', () => run(btn.getAttribute('data-launch')));
      });
    } catch (_) {
      root.innerHTML = '<p class="muted fs-sm">Probe offline — launchers unavailable.</p>';
    }
  }

  async function run(id) {
    const status = document.getElementById('dx-launcher-status');
    if (status) status.textContent = 'Launching ' + id + '…';
    try {
      if (window.PcLabProbeAuth) await window.PcLabProbeAuth.ensure();
      const res = await fetch(AGENT() + '/launchers/run', {
        method: 'POST',
        headers: (window.PcLabProbeAuth && window.PcLabProbeAuth.jsonHeaders()) || {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ id, seconds: 90 }),
      });
      const data = await res.json();
      if (!data.ok) {
        if (status) status.textContent = data.message || data.error || 'Launch failed';
        return;
      }
      const certRes = await fetch('/api/diagnostic/stress/certificate', {
        method: 'POST',
        headers: (window.PcLabCsrf && window.PcLabCsrf.headers()) || {
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]')?.content || '',
        },
        body: JSON.stringify({ run: data, samples: data.samples || [] }),
      });
      const cert = await certRes.json();
      if (status) {
        status.textContent =
          (cert.verdict || cert.certificate?.verdict || 'done') +
          ' · samples ' +
          (data.samples?.length || 0) +
          (cert.summary || cert.certificate?.summary ? ' — ' + (cert.summary || cert.certificate.summary) : '');
      }
    } catch (e) {
      if (status) status.textContent = String(e.message || e);
    }
  }

  function boot() {
    if (!document.getElementById('dx-launchers')) return;
    refresh();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
