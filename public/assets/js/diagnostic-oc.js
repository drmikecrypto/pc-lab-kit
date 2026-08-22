(function () {
  const cfg = window.PCLAB_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  let lastOcPlan = null;
  let lastApply = null;
  let lastPreflight = null;
  let lastWatch = null;
  let countdownTimer = null;
  let cancelCountdown = false;

  async function probeJsonHeaders() {
    if (window.PcLabProbeAuth) await window.PcLabProbeAuth.ensure();
    return (window.PcLabProbeAuth && window.PcLabProbeAuth.jsonHeaders()) || { 'Content-Type': 'application/json' };
  }

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
            <div class="dx-oc-brand">PC Lab Kit · Safe OC</div>
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

        <div class="dx-oc-flow" aria-label="Safe OC steps">
          <span data-oc-step="preflight">1 Preflight</span>
          <span data-oc-step="apply">2 Apply</span>
          <span data-oc-step="watch">3 Watch</span>
          <span data-oc-step="rollback">4 Rollback</span>
        </div>

        <div class="dx-oc-headroom">
          <span>CPU ${esc(String(plan.headroom?.cpu_temp_c ?? '—'))}°C</span>
          <span>CPU margin ${esc(String(plan.headroom?.thermal_margin_cpu ?? '—'))}°</span>
          <span>GPU ${esc(String(plan.headroom?.gpu_temp_c ?? '—'))}°C</span>
          <span>GPU margin ${esc(String(plan.headroom?.thermal_margin_gpu ?? '—'))}°</span>
        </div>

        <div class="dx-oc-targets">${targetRows || '<p class="muted fs-sm">Run a deep scan to see safe OC targets here.</p>'}</div>

        <p class="dx-oc-disclaimer muted fs-xs">${esc(plan.disclaimer || plan.disclaimer_fa || '')}</p>

        <div class="dx-oc-actions">
          <button type="button" class="dx-btn ghost" id="dx-oc-preflight" ${eligible ? '' : 'disabled'}>Pre-flight sample</button>
          <button type="button" class="dx-btn primary" id="dx-oc-apply" ${eligible ? '' : 'disabled'}>
            Apply safe tuning (${auto.length})
          </button>
          <button type="button" class="dx-btn ghost" id="dx-oc-rollback">Rollback</button>
          <button type="button" class="dx-btn ghost" id="dx-oc-report" hidden>OC report (PDF)</button>
          <button type="button" class="dx-btn ghost" id="dx-oc-cancel" hidden>Cancel countdown</button>
        </div>
        <div id="dx-oc-status" class="muted fs-xs mt-2"></div>
      </div>`;

    mountEl.querySelector('#dx-oc-preflight')?.addEventListener('click', runPreflight);
    mountEl.querySelector('#dx-oc-apply')?.addEventListener('click', applyOc);
    mountEl.querySelector('#dx-oc-rollback')?.addEventListener('click', rollbackOc);
    mountEl.querySelector('#dx-oc-report')?.addEventListener('click', exportOcReport);
    mountEl.querySelector('#dx-oc-cancel')?.addEventListener('click', () => { cancelCountdown = true; });
  }

  function setOcStep(step) {
    document.querySelectorAll('[data-oc-step]').forEach((el) => {
      el.classList.toggle('is-active', el.getAttribute('data-oc-step') === step);
    });
  }

  async function runPreflight() {
    const st = document.getElementById('dx-oc-status');
    setOcStep('preflight');
    if (st) st.textContent = 'Pre-flight: idle + load sample (≈30s)…';
    try {
      const res = await fetch(`${AGENT}/oc/preflight`, {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify({ idle_seconds: 10, load_seconds: 10 }),
      });
      lastPreflight = await res.json();
      if (st) {
        st.textContent = lastPreflight.message
          || (lastPreflight.ok ? 'Pre-flight OK.' : 'Pre-flight blocked.');
      }
    } catch (_) {
      if (st) st.textContent = 'Pre-flight failed — is Probe running?';
    }
  }

  function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
  }

  async function countdown(seconds, st, cancelBtn) {
    cancelCountdown = false;
    if (cancelBtn) cancelBtn.hidden = false;
    for (let i = seconds; i > 0; i--) {
      if (cancelCountdown) {
        if (cancelBtn) cancelBtn.hidden = true;
        return false;
      }
      if (st) st.textContent = `Applying in ${i}s — click Cancel to abort…`;
      await sleep(1000);
    }
    if (cancelBtn) cancelBtn.hidden = true;
    return !cancelCountdown;
  }

  async function applyOc() {
    const st = document.getElementById('dx-oc-status');
    const cancelBtn = document.getElementById('dx-oc-cancel');
    const reportBtn = document.getElementById('dx-oc-report');
    if (!lastOcPlan || !lastOcPlan.eligible) return;

    if (lastPreflight && lastPreflight.ok === false) {
      if (st) st.textContent = 'Pre-flight blocked apply. Cool down, then retry.';
      return;
    }

    const go = await countdown(10, st, cancelBtn);
    if (!go) {
      if (st) st.textContent = 'Apply cancelled.';
      return;
    }

    if (st) st.textContent = 'Applying via Probe…';
    setOcStep('apply');
    try {
      const res = await fetch(`${AGENT}/oc/apply`, {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify(lastOcPlan),
      });
      lastApply = await res.json();
      if (!lastApply.ok) throw new Error('apply failed');
      setOcStep('watch');
      if (st) st.textContent = (lastApply.message || 'Applied') + ' — watching thermals (auto-rollback on)…';

      // Post-apply watch (shorter default for UI responsiveness; Probe enforces min 30s)
      const watchRes = await fetch(`${AGENT}/oc/watch`, {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify({ seconds: 60, breach_seconds: 20, auto_rollback: true }),
      });
      lastWatch = await watchRes.json();
      if (lastWatch.rolled_back) {
        if (st) st.textContent = 'Auto-rollback triggered: ' + (lastWatch.reason || 'limits exceeded');
      } else if (st) {
        st.textContent = 'Watch complete — temps stayed within limits. Export OC report if needed.';
      }
      if (reportBtn) reportBtn.hidden = false;

      if (window.dxTrackLab && lastOcPlan) {
        window.dxTrackLab('oc_apply', {
          profile: lastOcPlan.profile || '',
          safety_score: lastOcPlan.safety_score,
          targets: (lastOcPlan.auto_targets || []).length,
          rolled_back: !!lastWatch?.rolled_back,
        });
      }
    } catch (_) {
      if (st) st.textContent = 'Could not apply — run PcLab Probe locally.';
    }
  }

  async function rollbackOc() {
    const st = document.getElementById('dx-oc-status');
    setOcStep('rollback');
    if (st) st.textContent = 'Rolling back…';
    try {
      const res = await fetch(`${AGENT}/oc/rollback`, {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: '{}',
      });
      const data = await res.json();
      if (!data.ok) throw new Error('rollback failed');
      if (st) st.textContent = 'Previous settings restored.';
    } catch (_) {
      if (st) st.textContent = 'Rollback failed — check Probe is running.';
    }
  }

  async function exportOcReport() {
    const st = document.getElementById('dx-oc-status');
    if (!lastOcPlan) return;
    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
      const res = await fetch('/api/diagnostic/oc/report', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
        body: JSON.stringify({
          plan: lastOcPlan,
          apply: lastApply || {},
          samples: lastWatch?.samples || lastPreflight?.samples_load || [],
          preflight: lastPreflight,
          watch: lastWatch,
          rolled_back: !!lastWatch?.rolled_back,
          format: 'html',
        }),
      });
      const html = await res.text();
      const w = window.open('', '_blank');
      if (w) {
        w.document.write(html);
        w.document.close();
      }
      if (st) st.textContent = 'OC report opened — use Print → Save as PDF.';
    } catch (_) {
      if (st) st.textContent = 'Could not build OC report.';
    }
  }

  function onScanComplete(e) {
    const data = e.detail || {};
    const plan = data.oc_plan;
    const mount = document.getElementById('dx-oc-panel');
    if (mount && plan) renderOcPanel(plan, mount);
    mount?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }

  window.dxRenderOcPanel = renderOcPanel;
  window.addEventListener('dx:scan-complete', onScanComplete);
})();
