/**
 * Benchmark Arena — percentile rings vs 19 reference datasets.
 */
(function () {
  const ARENA = '/api/diagnostic/arena';

  function ringSvg(pct, label) {
    const p = Math.max(0, Math.min(100, pct ?? 0));
    const r = 52;
    const c = 2 * Math.PI * r;
    const off = c - (p / 100) * c;
    const hasScore = pct != null;
    return `
      <div class="dx-arena-ring" aria-label="${label} percentile ${hasScore ? p : 'unknown'}">
        <svg viewBox="0 0 120 120" role="img">
          <defs>
            <linearGradient id="arenaGrad" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%" stop-color="#3d8bfd"/>
              <stop offset="100%" stop-color="#56d364"/>
            </linearGradient>
          </defs>
          <circle class="dx-arena-ring-bg" cx="60" cy="60" r="${r}"/>
          ${hasScore ? `<circle class="dx-arena-ring-fill" cx="60" cy="60" r="${r}" stroke-dasharray="${c}" stroke-dashoffset="${off}"/>` : ''}
        </svg>
        <div class="dx-arena-ring-pct">${hasScore ? p : '—'}${hasScore ? '<small>percentile</small>' : '<small>no run</small>'}</div>
      </div>`;
  }

  function badgeClass(kind) {
    if (kind === 'verified') return 'dx-arena-badge--verified';
    return 'dx-arena-badge--pending';
  }

  function badgeLabel(kind) {
    if (kind === 'verified') return 'Reproducible ±1%';
    if (kind === 'first_run') return 'First benchmark';
    return 'Run again to verify';
  }

  function renderRadar(radar, root) {
    if (!root || !radar?.labels?.length) return;
    const w = 320;
    const h = 240;
    const cx = w / 2;
    const cy = h / 2 + 10;
    const maxR = 90;
    const n = radar.labels.length;
    const vals = radar.values || [];
    const pts = vals.map((v, i) => {
      const a = (Math.PI * 2 * i) / n - Math.PI / 2;
      const r = (Math.max(0, Math.min(100, v)) / 100) * maxR;
      return `${cx + Math.cos(a) * r},${cy + Math.sin(a) * r}`;
    }).join(' ');
    const axes = radar.labels.map((lbl, i) => {
      const a = (Math.PI * 2 * i) / n - Math.PI / 2;
      const x2 = cx + Math.cos(a) * maxR;
      const y2 = cy + Math.sin(a) * maxR;
      const lx = cx + Math.cos(a) * (maxR + 14);
      const ly = cy + Math.sin(a) * (maxR + 14);
      return `<line x1="${cx}" y1="${cy}" x2="${x2}" y2="${y2}" stroke="rgba(255,255,255,0.08)"/>
        <text x="${lx}" y="${ly}" fill="rgba(255,255,255,0.5)" font-size="10" text-anchor="middle">${lbl}</text>`;
    }).join('');
    root.innerHTML = `<svg class="dx-arena-radar" viewBox="0 0 ${w} ${h}" role="img" aria-label="Benchmark radar">
      ${axes}
      <polygon points="${pts}" fill="rgba(88,166,255,0.25)" stroke="#58a6ff" stroke-width="1.5"/>
    </svg>`;
  }

  function renderCard(c) {
    const ref = c.reference_name ? `<p class="muted fs-xs">Nearest ref: ${c.reference_name}</p>` : '';
    const score = c.score != null ? `<p class="dx-arena-score">Score: <strong>${Number(c.score).toLocaleString()}</strong></p>` : '<p class="muted fs-sm">Run Full Lab or Toolkit benches</p>';
    const badge = c.reproducibility ? `<span class="dx-arena-badge ${badgeClass(c.reproducibility)}">${badgeLabel(c.reproducibility)}</span>` : '';
    return `<article class="dx-arena-card" data-component="${c.id}">
      <h3>${c.label}</h3>
      ${ringSvg(c.percentile, c.label)}
      ${score}
      ${ref}
      ${badge}
    </article>`;
  }

  async function load() {
    const grid = document.getElementById('dx-arena-grid');
    const stats = document.getElementById('dx-arena-stats');
    const radar = document.getElementById('dx-arena-radar');
    const datasets = document.getElementById('dx-arena-datasets-list');
    if (!grid) return;
    grid.innerHTML = '<p class="muted fs-sm">Loading arena…</p>';
    try {
      const r = await fetch(ARENA, { cache: 'no-store' });
      const data = await r.json();
      if (stats && data.global) {
        stats.innerHTML = `
          <div class="dx-arena-stat"><strong>${data.global.total_rows?.toLocaleString?.() ?? data.global.total_rows ?? 0}</strong><span>Reference rows</span></div>
          <div class="dx-arena-stat"><strong>${data.global.datasets ?? 0}</strong><span>Datasets</span></div>
          <div class="dx-arena-stat"><strong>${data.user?.has_run ? 'Yes' : 'No'}</strong><span>Your bench data</span></div>`;
      }
      grid.innerHTML = (data.components || []).map(renderCard).join('');
      renderRadar(data.radar, radar);
      if (datasets && data.datasets) {
        datasets.innerHTML = data.datasets.map((d) =>
          `<div class="dx-arena-dataset-item"><strong>${d.label || d.key}</strong><br>${d.count} rows · ${d.component} · ${d.source_tier}</div>`
        ).join('');
      }
    } catch (e) {
      grid.innerHTML = `<p class="muted fs-sm">Arena unavailable: ${e.message}</p>`;
    }
  }

  window.PcLabArena = { load };
  document.addEventListener('DOMContentLoaded', () => {
    const panel = document.querySelector('[data-dx-panel="arena"]');
    if (!panel) return;
    const obs = new MutationObserver(() => {
      if (panel.classList.contains('is-active') && !panel.dataset.arenaLoaded) {
        panel.dataset.arenaLoaded = '1';
        load();
      }
    });
    obs.observe(panel, { attributes: true, attributeFilter: ['class'] });
    if (panel.classList.contains('is-active')) {
      panel.dataset.arenaLoaded = '1';
      load();
    }
  });
})();
