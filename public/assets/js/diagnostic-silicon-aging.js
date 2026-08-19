/**
 * Silicon Aging Index dashboard — session drift timeline.
 */
(function () {
  const API = '/api/diagnostic/silicon-aging';

  function render(data, root) {
    if (!root) return;
    const idx = data.current_index;
    const label = data.current_label || 'no_data';
    const trend = data.trend || 'insufficient_data';
    const rows = (data.timeline || []).map((t) =>
      `<tr><td>${t.signed_at || '—'}</td><td><strong>${t.silicon_aging_index ?? '—'}</strong></td><td>${t.label}</td><td>${(t.notes || []).join('; ') || '—'}</td></tr>`
    ).join('');
    root.innerHTML = `
      <section class="dx-panel-card">
        <h2>Silicon Aging Index</h2>
        <p class="muted fs-sm">Track therm spread, SMART wear, and open-book drift across .pclab sessions.</p>
        <div class="dx-arena-stats">
          <div class="dx-arena-stat"><strong>${idx ?? '—'}</strong><span>Current index</span></div>
          <div class="dx-arena-stat"><strong>${label}</strong><span>Status</span></div>
          <div class="dx-arena-stat"><strong>${trend.replace(/_/g, ' ')}</strong><span>Trend</span></div>
          <div class="dx-arena-stat"><strong>${data.session_count ?? 0}</strong><span>Sessions</span></div>
        </div>
        ${rows ? `<table class="dx-hwref__fields"><thead><tr><th>Signed</th><th>Index</th><th>Label</th><th>Notes</th></tr></thead><tbody>${rows}</tbody></table>` : '<p class="muted fs-sm">Run Full Lab and export .pclab to start aging timeline.</p>'}
      </section>`;
  }

  async function load() {
    const root = document.getElementById('dx-silicon-aging');
    if (!root) return;
    try {
      const r = await fetch(API, { cache: 'no-store' });
      render(await r.json(), root);
    } catch (e) {
      root.innerHTML = `<p class="muted fs-sm">Silicon aging unavailable: ${e.message}</p>`;
    }
  }

  document.addEventListener('DOMContentLoaded', load);
  window.PcLabSiliconAging = { load };
})();
