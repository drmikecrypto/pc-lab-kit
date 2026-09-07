/**
 * SVG topology renderer from TopologyViewService payload.
 */
(function () {
  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function render(root, topology) {
    if (!root) return;
    const w = topology?.width || 800;
    const h = topology?.height || 480;
    const nodes = topology?.nodes || [];
    const links = topology?.links || [];
    const byId = Object.fromEntries(nodes.map((n) => [n.id, n]));

    const lines = links
      .map((l) => {
        const a = byId[l.source];
        const b = byId[l.target];
        if (!a || !b) return '';
        return `<line x1="${a.x}" y1="${a.y}" x2="${b.x}" y2="${b.y}" stroke="#30363d" stroke-width="2"/>
          <text x="${(a.x + b.x) / 2}" y="${(a.y + b.y) / 2 - 6}" fill="#6e7b8b" font-size="10" text-anchor="middle">${esc(l.relation || '')}</text>`;
      })
      .join('');

    const dots = nodes
      .map((n) => {
        return `<g>
          <circle cx="${n.x}" cy="${n.y}" r="22" fill="#122033" stroke="#58a6ff" stroke-width="2"/>
          <text x="${n.x}" y="${n.y + 4}" fill="#e6edf3" font-size="10" text-anchor="middle">${esc((n.label || n.id).slice(0, 14))}</text>
          <text x="${n.x}" y="${n.y + 38}" fill="#8b98a5" font-size="9" text-anchor="middle">${esc(n.type || '')}</text>
        </g>`;
      })
      .join('');

    root.innerHTML = `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Hardware topology">${lines}${dots}</svg>`;
  }

  window.PcLabTopology = { render };
})();
