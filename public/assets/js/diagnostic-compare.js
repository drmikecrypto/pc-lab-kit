(function () {
  function renderComparisonBlock(comparison) {
    if (!comparison || !comparison.has_previous) return '';

    const delta = comparison.delta || {};
    const scoreDelta = delta.health_score ?? 0;
    const scoreClass = scoreDelta > 0 ? 'up' : (scoreDelta < 0 ? 'down' : 'flat');
    const scoreLabel = scoreDelta > 0 ? '+' + scoreDelta : String(scoreDelta);

    const metrics = (comparison.metrics || []).slice(0, 4).map((m) => {
      if (m.delta == null || Math.abs(m.delta) < 0.01) return '';
      const cls = m.improved === true ? 'up' : (m.improved === false ? 'down' : 'flat');
      const sign = m.delta > 0 ? '+' : '';
      return `<div class="dx-compare-metric ${cls}"><span>${esc(m.label)}</span><strong>${sign}${m.delta}${esc(m.unit || '')}</strong></div>`;
    }).filter(Boolean).join('');

    const prev = comparison.previous || {};
    const aiChanges = comparison.ai_changes || '';

    return `<div class="dx-compare-panel">
      <div class="dx-compare-head">
        <span class="dx-compare-title">Compared with last test</span>
        <span class="dx-compare-prev muted fs-xs">${esc(prev.ago || '')} · score ${prev.score}/${esc(prev.grade || '')}</span>
      </div>
      <div class="dx-compare-score ${scoreClass}">${scoreLabel} <small>health points</small></div>
      <p class="dx-compare-summary muted fs-sm">${esc(comparison.summary || '')}</p>
      ${metrics ? `<div class="dx-compare-metrics">${metrics}</div>` : ''}
      ${aiChanges ? `<p class="dx-compare-ai fs-sm">${esc(aiChanges)}</p>` : ''}
    </div>`;
  }

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  window.dxRenderComparison = renderComparisonBlock;
})();
