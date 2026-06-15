(function () {
  const cfg = window.PCVERSE_DIAGNOSTIC || {};
  const steps = cfg.steps || [];
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';

  function jsonHeadersWithCsrf() {
    const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    return { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t };
  }

  let stepIdx = 0;
  const answers = {};
  let probePayload = null;
  let importContent = null;
  let importFormat = '';
  const selectedGames = new Set();
  let gameSearchTimer = null;

  const container = document.getElementById('dx-step-container');
  const progressBar = document.getElementById('dx-progress-bar');
  const btnPrev = document.getElementById('dx-prev');
  const btnNext = document.getElementById('dx-next');
  const resultsEl = document.getElementById('dx-results');
  const popup = document.getElementById('dx-app-popup');

  const USER_ERROR = 'Something went wrong. Please try again.';

  async function parseApiResponse(res) {
    if (!res.ok) throw new Error('bad');
    const data = await res.json();
    if (data.ok === false || data.error) throw new Error('bad');
    return data;
  }

  function renderStep() {
    const step = steps[stepIdx];
    if (!step) return;
    progressBar.style.width = ((stepIdx + 1) / steps.length * 100) + '%';
    btnPrev.disabled = stepIdx === 0;
    btnNext.textContent = stepIdx === steps.length - 1 ? 'Run quick analysis' : 'Next';

    let html = `<h2 class="dx-step-title">${esc(step.title || step.title_fa || '')}</h2>`;
    step.questions.forEach((q) => {
      html += `<p class="muted fs-sm mb-2">${esc(q.label || q.label_fa || '')}</p>`;
      q.options.forEach((opt) => {
        const selected = q.type === 'multi'
          ? ((answers[q.id] || []).includes(opt.value) ? ' selected' : '')
          : (answers[q.id] === opt.value ? ' selected' : '');
        html += `<button type="button" class="dx-option${selected}" data-q="${escAttr(q.id)}" data-v="${escAttr(opt.value)}" data-multi="${q.type === 'multi' ? '1' : '0'}">${esc(opt.label || opt.label_fa || '')}</button>`;
      });
    });
    container.innerHTML = html;
    container.querySelectorAll('.dx-option').forEach((btn) => {
      btn.addEventListener('click', () => selectOption(btn));
    });
  }

  function selectOption(btn) {
    const q = btn.dataset.q;
    const v = btn.dataset.v;
    const multi = btn.dataset.multi === '1';
    if (multi) {
      answers[q] = answers[q] || [];
      const i = answers[q].indexOf(v);
      if (i >= 0) answers[q].splice(i, 1);
      else answers[q].push(v);
    } else {
      answers[q] = v;
    }
    renderStep();
  }

  async function submitLite() {
    btnNext.disabled = true;
    btnNext.textContent = 'Analyzing…';
    try {
      const res = await fetch('/api/diagnostic/lite', {
        method: 'POST',
        headers: jsonHeadersWithCsrf(),
        body: JSON.stringify(answers),
      });
      const data = await parseApiResponse(res);
      showResults(data, resultsEl);
    } catch (_) {
      alert(USER_ERROR);
    }
    btnNext.disabled = false;
    btnNext.textContent = 'Run quick analysis';
  }

  function showResults(data, targetEl) {
    const issues = (data.issues || []).map((i) => `
      <div class="dx-issue"><strong>${esc(i.title || i.title_fa || '')}</strong><br><span class="muted fs-sm">${esc(i.detail || i.detail_fa || '')}</span></div>`).join('');

    const risks = (data.risks || []).map((r) => `
      <div class="dx-risk">${esc(r.message || r.message_fa || '')}</div>`).join('');

    const metrics = data.metrics || {};
    const metricHtml = Object.keys(metrics).length ? `
      <div class="dx-metric-grid">
        ${metrics.cpu_score ? `<div class="dx-metric"><strong>${metrics.cpu_score}</strong>CPU score</div>` : ''}
        ${metrics.gpu_score ? `<div class="dx-metric"><strong>${metrics.gpu_score}</strong>GPU score</div>` : ''}
        ${metrics.ram_gb ? `<div class="dx-metric"><strong>${metrics.ram_gb}GB</strong>RAM</div>` : ''}
        ${metrics.gpu_temp_max ? `<div class="dx-metric"><strong>${metrics.gpu_temp_max}°</strong>GPU temp</div>` : ''}
        ${metrics.cpu_temp_max ? `<div class="dx-metric"><strong>${metrics.cpu_temp_max}°</strong>CPU temp</div>` : ''}
        ${metrics.lan_link_mbps ? `<div class="dx-metric"><strong>${metrics.lan_link_mbps}</strong>Mbps LAN</div>` : ''}
      </div>` : '';

    const gameSettings = (data.game_settings || []).map((g) => {
      const rec = g.recommended || {};
      return `<div class="dx-issue"><strong>${esc(g.game_name || '')}</strong><br><span class="muted fs-sm">${esc(rec.resolution || '')} · ${esc(rec.preset || '')} · ${esc(rec.fps_target || '')} FPS</span></div>`;
    }).join('');

    const aiPlan = (() => {
      const ai = data.ai || {};
      const actions = (ai.priority_actions || []).map((x) => `<li>${esc(String(x))}</li>`).join('');
      const upgrades = (ai.upgrade_plan || []).map((row) => {
        if (typeof row === 'string') return `<li>${esc(row)}</li>`;
        const rec = row.recommendation || row.suggestion || '';
        const why = row.rationale || row.why || '';
        return `<li><strong>${esc(row.component || 'Upgrade')}:</strong> ${esc(rec)}${why ? `<span class="muted"> — ${esc(why)}</span>` : ''}</li>`;
      }).join('');
      const burns = (ai.burn_risk || []).filter(Boolean).map((x) => `<li>${esc(String(x))}</li>`).join('');
      const swaps = (ai.swap_pairs || []).map((p) =>
        `<li>${esc(p.from || '')} → ${esc(p.to || '')}: ${esc(p.reason || '')}</li>`
      ).join('');
      const headline = ai.headline || '';
      const summary = ai.summary || '';
      if (!headline && !summary && !actions && !upgrades) {
        if (ai.upgrade_plan && ai.upgrade_plan.length) {
          return `<div class="dx-ai-plan mt-3"><h4>AI upgrade suggestions</h4><ul class="muted fs-sm">${ai.upgrade_plan.map((x) => `<li>${esc(String(typeof x === 'string' ? x : (x.recommendation || '')))}</li>`).join('')}</ul></div>`;
        }
        return '';
      }

      return `<div class="dx-ai-block mt-3 p-3">
        <div class="dx-ai-block-label">AI analysis</div>
        ${headline ? `<p class="dx-ai-headline m-0 mt-2">${esc(headline)}</p>` : ''}
        ${summary ? `<p class="muted fs-sm m-0 mt-2">${esc(summary)}</p>` : ''}
        ${actions ? `<h4 class="mt-3 mb-1">Do this first</h4><ul class="muted fs-sm">${actions}</ul>` : ''}
        ${upgrades ? `<h4 class="mt-3 mb-1">Upgrade plan</h4><ul class="muted fs-sm">${upgrades}</ul>` : ''}
        ${burns ? `<h4 class="mt-3 mb-1">Thermal &amp; stability</h4><ul class="muted fs-sm">${burns}</ul>` : ''}
        ${swaps ? `<h4 class="mt-3 mb-1">Worth swapping</h4><ul class="muted fs-sm">${swaps}</ul>` : ''}
      </div>`;
    })();

    const aiHint = !data.ai_available && !data.ai
      ? `<p class="muted fs-xs mt-2">${esc(data.ai_hint || 'Open Settings and add your API key for expert analysis after each scan.')}</p>`
      : (data.ai_error ? `<p class="dx-ai-error fs-xs mt-2">${esc(data.ai_error)}</p>` : '');

    const consult = data.consultant || {};
    const consultHead = (consult.headline || consult.headline_fa)
      ? `<div class="dx-consultant-block mb-3 p-3" style="border-radius:12px;border:1px solid rgba(167,139,250,0.35);background:rgba(26,21,40,0.6)">
        <div class="fs-sm" style="color:#c4b5fd;font-weight:600">PCVerse Advisor</div>
        <p class="m-0 mt-2 fs-sm">${esc(consult.headline || consult.headline_fa || '')}</p>
        ${consult.honest_assessment || consult.honest_assessment_fa ? `<p class="muted fs-xs m-0 mt-2">${esc(consult.honest_assessment || consult.honest_assessment_fa || '')}</p>` : ''}
        ${consult.angle ? `<p class="muted fs-xs m-0 mt-2">${esc(consult.angle)}</p>` : ''}
      </div>`
      : '';

    const bnMsg = data.bottleneck?.message || data.bottleneck?.message_fa || '';
    const aiNarr = data.ai_narrative || data.ai_narrative_fa || data.ai?.summary || data.ai?.summary_fa || '';
    const fullReason = data.full_scan_reason || data.full_scan_reason_fa || '';

    const aiChanges = data.ai_changes_since_last || (data.ai && data.ai.changes_since_last) || '';
    const compareHtml = window.dxRenderComparison
      ? window.dxRenderComparison(Object.assign({}, data.comparison || {}, { ai_changes: aiChanges }))
      : '';

    targetEl.innerHTML = `
      ${compareHtml}
      <div class="d-flex flex-wrap gap-4 align-items-center mb-4">
        <div class="dx-score-ring">${data.health_score ?? '—'}<span class="fs-sm muted"> / ${esc(data.health_grade || '')}</span></div>
        <div><p class="m-0">${esc(bnMsg)}</p>
        <p class="muted fs-sm m-0 mt-2">${esc(aiNarr)}</p>${aiHint}</div>
      </div>
      ${consultHead}
      ${aiPlan}
      ${metricHtml}
      ${risks ? '<h4>Risks</h4>' + risks : ''}
      ${issues ? '<h4>Notes</h4>' + issues : ''}
      ${gameSettings ? '<h4 class="mt-4">Game settings</h4>' + gameSettings : ''}
      ${fullReason ? `<p class="muted fs-sm mt-4">${esc(fullReason)}</p>` : ''}`;
    targetEl.hidden = false;
    window.dispatchEvent(new CustomEvent('dx:scan-complete', { detail: data }));
    if (window.dxTrackLab) {
      window.dxTrackLab('lab_scan_complete', window.dxLabMetaFromScan ? window.dxLabMetaFromScan(data) : {});
    }
  }

  window.dxShowResults = showResults;

  async function fetchLocalProbe() {
    const status = document.getElementById('dx-probe-status');
    status.textContent = 'Connecting…';
    try {
      const health = await fetch(`${AGENT}/health`, { mode: 'cors' });
      if (!health.ok) throw new Error('health fail');
      const res = await fetch(`${AGENT}/probe`, { mode: 'cors' });
      if (!res.ok) throw new Error('probe fail');
      probePayload = await res.json();
      status.textContent = `✓ Connected — ${probePayload.cpu?.model || probePayload.telemetry?.cpu?.architecture?.model || 'ready'}`;
      window.__dxLastProbe = probePayload;
      window.dispatchEvent(new CustomEvent('dx:probe-ready', { detail: probePayload }));
    } catch (_) {
      status.textContent = 'PCVerse Probe not found — run it locally, then click Connect again.';
      probePayload = null;
    }
  }

  document.getElementById('dx-probe-file')?.addEventListener('change', async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      probePayload = JSON.parse(await file.text());
      document.getElementById('dx-probe-status').textContent = `✓ File: ${file.name}`;
      window.__dxLastProbe = probePayload;
      window.dispatchEvent(new CustomEvent('dx:probe-ready', { detail: probePayload }));
    } catch (_) {
      alert('Invalid JSON file.');
    }
  });

  document.getElementById('dx-import-format')?.addEventListener('change', (e) => {
    importFormat = e.target.value;
  });

  document.getElementById('dx-import-file')?.addEventListener('change', async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    importContent = await file.text();
    if (!importFormat) {
      const ext = file.name.split('.').pop()?.toLowerCase();
      importFormat = ext === 'json' ? 'capframex_json' : 'hwinfo_csv';
      const sel = document.getElementById('dx-import-format');
      if (sel) sel.value = importFormat;
    }
  });

  async function loadGames(q) {
    const chips = document.getElementById('dx-game-chips');
    if (!chips) return;
    try {
      const res = await fetch(`/api/diagnostic/games?q=${encodeURIComponent(q)}&per_page=30`);
      const data = await parseApiResponse(res);
      chips.innerHTML = (data.games || []).map((g) => {
        const sel = selectedGames.has(g.id) ? ' selected' : '';
        return `<button type="button" class="dx-game-chip${sel}" data-id="${escAttr(g.id)}">${esc(g.name)}</button>`;
      }).join('');
      chips.querySelectorAll('.dx-game-chip').forEach((btn) => {
        btn.addEventListener('click', () => {
          const id = btn.dataset.id;
          if (selectedGames.has(id)) selectedGames.delete(id);
          else if (selectedGames.size < 20) selectedGames.add(id);
          btn.classList.toggle('selected');
        });
      });
    } catch (_) {}
  }

  document.getElementById('dx-game-search')?.addEventListener('input', (e) => {
    clearTimeout(gameSearchTimer);
    gameSearchTimer = setTimeout(() => loadGames(e.target.value), 300);
  });

  async function runFullScan() {
    const btn = document.getElementById('dx-run-full');
    const out = document.getElementById('dx-full-results');
    if (!btn || !out) return;
    if (!probePayload) {
      alert('Connect PCVerse Probe or load a report file first.');
      return;
    }
    btn.disabled = true;
    btn.textContent = 'Analyzing…';
    try {
      const payload = { ...probePayload, selected_games: [...selectedGames] };
      if (importFormat && importContent) {
        payload.import_format = importFormat;
        payload.import_content = importContent;
      }
      const res = await fetch('/api/diagnostic/agent', {
        method: 'POST',
        headers: jsonHeadersWithCsrf(),
        body: JSON.stringify(payload),
      });
      const data = await parseApiResponse(res);
      showResults(data, out);
      out.scrollIntoView({ behavior: 'smooth' });
      try { localStorage.setItem('pcverse_lab_has_deep_scan', '1'); } catch (_) {}
    } catch (_) {
      alert(USER_ERROR);
    }
    btn.disabled = false;
    btn.textContent = 'Run full analysis';
  }

  document.getElementById('dx-fetch-probe')?.addEventListener('click', fetchLocalProbe);
  document.getElementById('dx-run-full')?.addEventListener('click', runFullScan);

  btnPrev.addEventListener('click', () => { if (stepIdx > 0) { stepIdx--; renderStep(); } });
  btnNext.addEventListener('click', () => {
    if (stepIdx < steps.length - 1) { stepIdx++; renderStep(); }
    else submitLite();
  });

  function esc(s) { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
  function escAttr(s) { return String(s).replace(/"/g, '&quot;'); }

  if (steps.length) renderStep();
  loadGames('');
})();
