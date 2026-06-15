(function () {
  const cfg = window.PCVERSE_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  let lastOcPlan = null;

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  function renderOcPanel(plan, mountEl) {
    if (!mountEl || !plan) return;
    lastOcPlan = plan;

    const eligible = plan.eligible === true;
    const score = plan.safety_score ?? '—';
    const targets = plan.targets || [];
    const auto = plan.auto_targets || targets.filter((t) => t.apply_auto);
    const blockers = plan.blockers || [];
    const warnings = plan.warnings || [];

    const targetRows = targets.map((t) => {
      const badge = t.apply_auto ? '<span class="dx-oc-badge auto">Auto</span>' : '<span class="dx-oc-badge manual">Guide</span>';
      const detail = t.reason || t.reason_fa || t.recommendation || t.recommendation_fa || '';
      const val = t.target != null ? ` → ${t.target}` : (t.graphics_offset_mhz ? ` +${t.graphics_offset_mhz} MHz` : '');
      return `<div class="dx-oc-target">
        <div class="dx-oc-target-head"><strong>${esc(t.domain || '')}</strong>${badge}</div>
        <div class="dx-oc-target-body muted fs-sm">${esc(detail)}${esc(val)}</div>
      </div>`;
    }).join('');

    mountEl.innerHTML = `
      <div class="dx-oc-panel glass-effect">
        <div class="dx-oc-head">
          <div>
            <div class="dx-oc-brand">PCVerse · Safe OC</div>
            <h3>Conservative auto-tuning after scan</h3>
            <p class="muted fs-sm">${esc(plan.summary || plan.summary_fa || '')}</p>
          </div>
          <div class="dx-oc-score ${eligible ? 'ok' : 'blocked'}">
            <span class="dx-oc-score-num">${esc(String(score))}</span>
            <span class="dx-oc-score-lbl">Safety score</span>
          </div>
        </div>

        ${blockers.length ? `<div class="dx-oc-blockers">${blockers.map((b) => `<div class="dx-oc-blocker">⛔ ${esc(b)}</div>`).join('')}</div>` : ''}
        ${warnings.length ? `<div class="dx-oc-warnings">${warnings.map((w) => `<div class="dx-oc-warn">⚠ ${esc(w)}</div>`).join('')}</div>` : ''}

        <div class="dx-oc-headroom">
          <span>CPU ${esc(String(plan.headroom?.cpu_temp_c ?? '—'))}°C</span>
          <span>CPU margin ${esc(String(plan.headroom?.thermal_margin_cpu ?? '—'))}°</span>
          <span>GPU ${esc(String(plan.headroom?.gpu_temp_c ?? '—'))}°C</span>
          <span>GPU margin ${esc(String(plan.headroom?.thermal_margin_gpu ?? '—'))}°</span>
        </div>

        <div class="dx-oc-targets">${targetRows || '<p class="muted fs-sm">Run a deep scan to see safe OC targets here.</p>'}</div>

        <p class="dx-oc-disclaimer muted fs-xs">${esc(plan.disclaimer || plan.disclaimer_fa || '')}</p>

        <div class="dx-oc-actions">
          <button type="button" class="dx-btn primary" id="dx-oc-apply" ${eligible ? '' : 'disabled'}>
            Apply safe tuning (${auto.length})
          </button>
          <button type="button" class="dx-btn ghost" id="dx-oc-rollback">Rollback</button>
        </div>
        <div id="dx-oc-status" class="muted fs-xs mt-2"></div>
      </div>`;

    mountEl.querySelector('#dx-oc-apply')?.addEventListener('click', applyOc);
    mountEl.querySelector('#dx-oc-rollback')?.addEventListener('click', rollbackOc);
  }

  async function applyOc() {
    const st = document.getElementById('dx-oc-status');
    if (!lastOcPlan || !lastOcPlan.eligible) return;

    const ok = window.confirm(
      'PCVerse only applies reversible OS/GPU settings.\n\n'
      + `Profile: ${lastOcPlan.profile}\n`
      + `Settings: ${(lastOcPlan.auto_targets || []).length}\n\n`
      + 'Continue?'
    );
    if (!ok) return;

    if (st) st.textContent = 'Applying via Probe…';
    try {
      const res = await fetch(`${AGENT}/oc/apply`, {
        method: 'POST',
        mode: 'cors',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(lastOcPlan),
      });
      const data = await res.json();
      if (!data.ok) throw new Error('apply failed');
      if (st) st.textContent = data.message || 'Applied — use Rollback if needed.';
      if (window.dxTrackLab && lastOcPlan) {
        window.dxTrackLab('vakhsh_oc_apply', {
          profile: lastOcPlan.profile || '',
          safety_score: lastOcPlan.safety_score,
          targets: (lastOcPlan.auto_targets || []).length,
        });
      }
    } catch (_) {
      if (st) st.textContent = 'Could not apply — run PCVerse Probe locally.';
    }
  }

  async function rollbackOc() {
    const st = document.getElementById('dx-oc-status');
    if (st) st.textContent = 'Rolling back…';
    try {
      const res = await fetch(`${AGENT}/oc/rollback`, { method: 'POST', mode: 'cors' });
      const data = await res.json();
      if (!data.ok) throw new Error('rollback failed');
      if (st) st.textContent = 'Previous settings restored.';
    } catch (_) {
      if (st) st.textContent = 'Rollback failed — check Probe is running.';
    }
  }

  function onScanComplete(e) {
    const data = e.detail || {};
    const plan = data.vakhsh_oc;
    const mount = document.getElementById('dx-vakhsh-oc');
    if (mount && plan) renderOcPanel(plan, mount);
    mount?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  window.dxRenderVakhshOc = renderOcPanel;
  window.addEventListener('dx:scan-complete', onScanComplete);
})();
