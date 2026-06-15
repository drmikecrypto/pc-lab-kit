(function () {
  const cfg = window.PCVERSE_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  let catalog = null;
  let filter = 'all';
  let probeOk = false;

  const el = (id) => document.getElementById(id);

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  async function probeHealth() {
    try {
      const res = await fetch(AGENT + '/health');
      probeOk = res.ok;
    } catch (_) {
      probeOk = false;
    }
    const st = el('dx-toolkit-run-status');
    if (st) {
      st.textContent = probeOk
        ? 'Probe connected — select a benchmark or stress test.'
        : 'Start PCVerse Probe to run native benchmarks and stress tests (Windows).';
    }
    document.querySelectorAll('.dx-toolkit-run-btn').forEach((btn) => {
      btn.disabled = !probeOk || btn.dataset.busy === '1';
    });
  }

  async function loadCatalog() {
    try {
      const res = await fetch('/api/diagnostic/toolkit');
      if (!res.ok) return;
      catalog = await res.json();
      renderCatalog(catalog);
      renderRunButtons(catalog.runnable || {});
    } catch (_) {}
  }

  function renderSummary(summary) {
    const head = el('dx-toolkit-headline');
    if (head && summary?.headline) head.textContent = summary.headline;

    const stats = el('dx-toolkit-stats');
    if (!stats || !summary?.coverage) return;
    const labels = { live: 'Live', beta: 'Beta native', import: 'Import', orchestrate: 'Orchestrate', planned: 'Roadmap' };
    stats.innerHTML = Object.entries(summary.coverage)
      .filter(([, n]) => n > 0)
      .map(([k, n]) => `<span class="dx-toolkit-stat dx-toolkit-stat--${k}">${labels[k] || k}: ${n}</span>`)
      .join('');
  }

  function renderFilters(categories) {
    const wrap = el('dx-toolkit-filters');
    if (!wrap) return;
    const buttons = [{ id: 'all', label: 'All' }];
    Object.entries(categories || {}).forEach(([id, label]) => buttons.push({ id, label }));
    wrap.innerHTML = buttons.map((b) =>
      `<button type="button" class="dx-toolkit-filter${filter === b.id ? ' is-active' : ''}" data-filter="${esc(b.id)}">${esc(b.label)}</button>`
    ).join('');
    wrap.querySelectorAll('.dx-toolkit-filter').forEach((btn) => {
      btn.addEventListener('click', () => {
        filter = btn.getAttribute('data-filter') || 'all';
        renderFilters(categories);
        renderGrid(catalog?.tools || []);
      });
    });
  }

  function renderGrid(tools) {
    const grid = el('dx-toolkit-grid');
    if (!grid) return;
    const list = (tools || []).filter((t) => filter === 'all' || t.category === filter);
    grid.innerHTML = list.map((t) => {
      const cov = t.coverage || 'planned';
      return `<article class="dx-toolkit-card">
        <div class="dx-toolkit-card-head">
          <strong>${esc(t.name)}</strong>
          <span class="dx-toolkit-badge dx-toolkit-badge--${esc(cov)}">${esc(cov)}</span>
        </div>
        <p>${esc(t.pcverse || '')}</p>
      </article>`;
    }).join('');
  }

  function renderCatalog(data) {
    renderSummary(data.summary || {});
    renderFilters(data.categories || {});
    renderGrid(data.tools || []);
  }

  function renderRunButtons(runnable) {
    const wrap = el('dx-toolkit-run');
    if (!wrap) return;
    const items = [];
    (runnable.bench || []).forEach((b) => {
      items.push({ kind: 'bench', id: b.id, label: b.label, desc: b.desc });
    });
    (runnable.stress || []).forEach((s) => {
      items.push({ kind: 'stress', id: s.id, label: s.label, desc: s.desc, seconds: 15 });
    });
    wrap.innerHTML = items.map((item) =>
      `<button type="button" class="dx-toolkit-run-btn" data-kind="${esc(item.kind)}" data-id="${esc(item.id)}" disabled>
        <strong>${esc(item.label)}</strong>
        <span>${esc(item.desc)}</span>
      </button>`
    ).join('');
    wrap.querySelectorAll('.dx-toolkit-run-btn').forEach((btn) => {
      btn.addEventListener('click', () => runTest(btn));
    });
    probeHealth();
  }

  async function runTest(btn) {
    if (!probeOk) return;
    const kind = btn.getAttribute('data-kind');
    const id = btn.getAttribute('data-id');
    const out = el('dx-toolkit-result');
    const st = el('dx-toolkit-run-status');
    btn.dataset.busy = '1';
    btn.disabled = true;
    if (st) st.textContent = 'Running ' + btn.querySelector('strong')?.textContent + '…';
    if (out) { out.hidden = false; out.textContent = 'Working…'; }
    try {
      const path = kind === 'stress' ? '/stress/run' : '/bench/run';
      const body = kind === 'stress' ? { id, seconds: 15 } : { id, seconds: 5 };
      const res = await fetch(AGENT + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (out) out.textContent = JSON.stringify(data, null, 2);
      if (st) st.textContent = 'Completed — result below.';
    } catch (e) {
      if (out) out.textContent = String(e);
      if (st) st.textContent = 'Run failed — is Probe running?';
    } finally {
      btn.dataset.busy = '0';
      btn.disabled = !probeOk;
    }
  }

  loadCatalog();
  setInterval(probeHealth, 12000);
})();
