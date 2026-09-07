/**
 * Interactive hardware knowledge graph explorer.
 */
(function () {
  const API = '/api/diagnostic/hardware-graph';
  let lastProbe = null;

  function renderGraph(explore, root) {
    if (!root || !explore) return;
    const types = Object.keys(explore.by_type || {});
    const filterBtns = types.map((t) =>
      `<button type="button" class="dx-btn ghost dx-hw-graph-filter" data-filter="${t}">${t}</button>`
    ).join('');
    const nodes = explore.nodes || [];
    const edges = explore.edges || [];
    const w = root.clientWidth || 640;
    const h = 280;
    const cx = w / 2;
    const cy = h / 2;
    const n = Math.max(1, nodes.length);
    const nodeEls = nodes.map((node, i) => {
      const a = (Math.PI * 2 * i) / n - Math.PI / 2;
      const r = Math.min(w, h) * 0.35;
      const x = cx + Math.cos(a) * r;
      const y = cy + Math.sin(a) * r;
      const label = (node.label || node.id || '').slice(0, 18);
      return `<g class="dx-hw-graph-node" data-type="${node.type || ''}" data-id="${node.id || ''}">
        <circle cx="${x}" cy="${y}" r="14" fill="#161b22" stroke="#58a6ff" stroke-width="1.5"/>
        <text x="${x}" y="${y + 28}" fill="rgba(255,255,255,0.65)" font-size="9" text-anchor="middle">${label}</text>
      </g>`;
    }).join('');
    const edgeEls = edges.slice(0, 80).map((e) => {
      const si = nodes.findIndex((n) => n.id === e.source);
      const ti = nodes.findIndex((n) => n.id === e.target);
      if (si < 0 || ti < 0) return '';
      const a1 = (Math.PI * 2 * si) / n - Math.PI / 2;
      const a2 = (Math.PI * 2 * ti) / n - Math.PI / 2;
      const rad = Math.min(w, h) * 0.35;
      const x1 = cx + Math.cos(a1) * rad;
      const y1 = cy + Math.sin(a1) * rad;
      const x2 = cx + Math.cos(a2) * rad;
      const y2 = cy + Math.sin(a2) * rad;
      return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="rgba(255,255,255,0.12)" stroke-width="1"/>`;
    }).join('');
    root.innerHTML = `
      <section class="dx-panel-card" id="dx-hw-graph-panel">
        <h2>Hardware knowledge graph</h2>
        <p class="muted fs-sm">${explore.node_count} nodes · ${explore.edge_count} edges — filter by subsystem</p>
        <div class="dx-command-center__row">${filterBtns}<button type="button" class="dx-btn ghost dx-hw-graph-filter is-active" data-filter="all">All</button></div>
        <svg width="${w}" height="${h}" role="img" aria-label="Hardware graph">${edgeEls}${nodeEls}</svg>
        <pre class="dx-hwref__raw muted fs-xs" id="dx-hw-graph-detail">Click a node for details</pre>
      </section>`;
    root.querySelectorAll('.dx-hw-graph-filter').forEach((btn) => {
      btn.addEventListener('click', () => {
        root.querySelectorAll('.dx-hw-graph-filter').forEach((b) => b.classList.remove('is-active'));
        btn.classList.add('is-active');
        const f = btn.getAttribute('data-filter');
        root.querySelectorAll('.dx-hw-graph-node').forEach((g) => {
          const show = f === 'all' || g.getAttribute('data-type') === f;
          g.style.opacity = show ? '1' : '0.15';
        });
      });
    });
    root.querySelectorAll('.dx-hw-graph-node').forEach((g) => {
      g.style.cursor = 'pointer';
      g.addEventListener('click', () => {
        const id = g.getAttribute('data-id');
        const node = nodes.find((n) => n.id === id);
        const detail = document.getElementById('dx-hw-graph-detail');
        if (detail && node) detail.textContent = JSON.stringify(node, null, 2);
      });
    });
  }

  async function load(probe) {
    const root = document.getElementById('dx-hw-graph-mount');
    if (!root) return;
    root.innerHTML = '<p class="muted fs-sm">Building graph…</p>';
    try {
      const r = await fetch(API, {
        method: 'POST',
        headers: (window.PcLabCsrf && window.PcLabCsrf.headers()) || { 'Content-Type': 'application/json' },
        body: JSON.stringify({ probe: probe || lastProbe || {} }),
      });
      const data = await r.json();
      renderGraph(data.explore, root);
    } catch (e) {
      root.innerHTML = `<p class="muted fs-sm">Graph unavailable: ${e.message}</p>`;
    }
  }

  window.addEventListener('dx:probe-connected', (ev) => {
    lastProbe = ev.detail?.probe || null;
    load(lastProbe);
  });

  document.addEventListener('DOMContentLoaded', () => load({}));
  window.PcLabHwGraph = { load };
})();
