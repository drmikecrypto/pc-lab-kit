/**
 * OS maintenance panel — SFC / DISM / pnputil via Probe (confirm + elevated).
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

  async function probeJsonHeaders() {
    if (window.PcLabProbeAuth) {
      await window.PcLabProbeAuth.ensure();
      return window.PcLabProbeAuth.jsonHeaders();
    }
    return { 'Content-Type': 'application/json' };
  }

  async function loadCatalog() {
    const box = el('dx-repair-tools');
    const note = el('dx-repair-note');
    if (!box) return;
    box.innerHTML = `<p class="muted fs-sm">Loading…</p>`;
    try {
      const res = await fetch(AGENT() + '/repair/catalog', { mode: 'cors' });
      const data = await res.json().catch(() => ({}));
      if (note) {
        note.textContent =
          (data.note || 'OS maintenance') +
          (data.elevated ? ' · Probe elevated' : ' · Probe not elevated — elevate to run');
      }
      const tools = data.tools || [];
      box.innerHTML = tools
        .map(
          (t) => `<article class="dx-repair-card">
          <strong>${esc(t.label || t.id)}</strong>
          <p class="muted fs-xs">${esc(t.description || '')}</p>
          <button type="button" class="dx-btn ghost dx-repair-run" data-id="${esc(t.id)}" ${
            data.elevated ? '' : 'disabled title="Elevate Probe first"'
          }>Run (confirm)</button>
        </article>`
        )
        .join('');
      box.querySelectorAll('.dx-repair-run').forEach((btn) => {
        btn.addEventListener('click', () => runTool(btn.getAttribute('data-id')));
      });
    } catch (e) {
      box.innerHTML = `<div class="dx-panel-empty is-error"><strong>Catalog failed</strong>
        <p class="muted fs-sm">${esc(e.message || e)}</p></div>`;
    }
  }

  async function runTool(id) {
    if (
      !window.confirm(
        `Run Windows ${id}? This is OS maintenance (SFC/DISM/pnputil), not a PC Lab Kit hardware repair. Stay nearby — scans can take a long time.`
      )
    ) {
      return;
    }
    const log = el('dx-repair-log');
    if (log) {
      log.hidden = false;
      log.textContent = `Starting ${id}…`;
    }
    try {
      const res = await fetch(AGENT() + '/repair/run', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify({ id, confirm: true }),
      });
      const data = await res.json().catch(() => ({}));
      if (log) {
        log.textContent = [
          data.ok ? 'OK' : 'FAILED',
          `exit ${data.exit_code ?? '—'}`,
          data.note || data.error || '',
          data.output_tail || '',
        ]
          .filter(Boolean)
          .join('\n\n');
      }
    } catch (e) {
      if (log) log.textContent = e.message || String(e);
    }
  }

  function bind() {
    el('dx-repair-refresh')?.addEventListener('click', loadCatalog);
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'advanced') loadCatalog();
    });
    if (el('dx-repair-tools')) loadCatalog();
  }

  window.PcLabRepair = { loadCatalog, runTool };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
