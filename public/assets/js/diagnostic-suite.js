/**
 * Command Center — Full Lab suite runner (probe suite + PHP finalize).
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';

  function fp() {
    try {
      return localStorage.getItem('pclab_fp') || '';
    } catch (_) {
      return '';
    }
  }

  function csrfHeaders() {
    const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    return { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t };
  }

  function el(id) {
    return document.getElementById(id);
  }

  function setProgress(pct, step) {
    const bar = el('dx-suite-progress-bar');
    const label = el('dx-suite-step');
    if (bar) bar.style.width = Math.max(0, Math.min(100, pct)) + '%';
    if (label) label.textContent = step || '';
  }

  function renderCards(cards) {
    const root = el('dx-advisor-cards');
    if (!root) return;
    if (!Array.isArray(cards) || !cards.length) {
      root.hidden = true;
      root.innerHTML = '';
      return;
    }
    root.hidden = false;
    root.innerHTML = cards
      .map((c) => {
        const sev = (c.severity || 'info').replace(/[^a-z]/g, '');
        return `<article class="dx-advisor-card dx-advisor-card--${sev}">
          <header><strong>${esc(c.title || '')}</strong><span class="dx-advisor-src">${esc(c.source || '')}</span></header>
          <p>${esc(c.body || '')}</p>
        </article>`;
      })
      .join('');
  }

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function renderResult(job) {
    const panel = el('dx-suite-result');
    if (!panel) return;
    const analysis = job?.result?.analysis || {};
    const cert = analysis.stress_certificate || {};
    const score = analysis.health_score ?? '—';
    const grade = analysis.health_grade ?? '—';
    panel.hidden = false;
    panel.innerHTML = `
      <div class="dx-suite-result__head">
        <h3>Full Lab complete</h3>
        <p>Health <strong>${esc(String(grade))}</strong> · score <strong>${esc(String(score))}</strong>
          · stress <strong>${esc(cert.verdict || '—')}</strong></p>
      </div>
      <div class="dx-suite-result__actions">
        <button type="button" class="dx-btn primary" id="dx-suite-open-report">Open report</button>
        <button type="button" class="dx-btn ghost" id="dx-suite-open-cert">Assembly Certificate</button>
        <button type="button" class="dx-btn ghost" id="dx-suite-show-topology">Topology</button>
      </div>
      <div id="dx-suite-report-frame" hidden></div>
      <div id="dx-suite-cert-frame" hidden></div>
      <div id="dx-suite-topology" class="dx-topology" hidden></div>`;

    renderCards(analysis.advisor_cards || []);

    el('dx-suite-open-report')?.addEventListener('click', () => {
      const frame = el('dx-suite-report-frame');
      if (!frame) return;
      frame.hidden = false;
      frame.innerHTML = job?.result?.report_html || '<p class="muted">Report unavailable.</p>';
    });

    el('dx-suite-open-cert')?.addEventListener('click', () => {
      const frame = el('dx-suite-cert-frame');
      if (!frame) return;
      frame.hidden = false;
      frame.innerHTML = job?.result?.assembly_certificate_html || '<p class="muted">Certificate unavailable — finalize Full Lab first.</p>';
    });

    window.dispatchEvent(new CustomEvent('dx:suite-complete', { detail: job }));

    el('dx-suite-show-topology')?.addEventListener('click', async () => {
      const box = el('dx-suite-topology');
      if (!box) return;
      box.hidden = false;
      box.innerHTML = '<p class="muted">Building topology…</p>';
      try {
        const res = await fetch('/api/diagnostic/topology', {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ hardware_graph: analysis.hardware_graph || null }),
        });
        const data = await res.json();
        if (window.PcLabTopology?.render) {
          window.PcLabTopology.render(box, data.topology);
        } else {
          box.innerHTML = `<pre class="dx-topology-fallback">${esc(JSON.stringify(data.topology?.summary || {}, null, 2))}</pre>`;
        }
      } catch (e) {
        box.innerHTML = `<p class="muted">Topology failed: ${esc(e.message || e)}</p>`;
      }
    });
  }

  async function pollProbeSuite() {
    const res = await fetch(AGENT() + '/suite/status');
    return res.json();
  }

  async function runSuite() {
    const profile = el('dx-suite-profile')?.value || 'standard';
    const status = el('dx-suite-status');
    const runBtn = el('dx-suite-run');
    const cancelBtn = el('dx-suite-cancel');
    if (runBtn) runBtn.disabled = true;
    if (cancelBtn) cancelBtn.hidden = false;
    if (status) status.textContent = 'Starting Full Lab…';
    setProgress(2, 'Starting');

    let phpJobId = null;
    try {
      const startRes = await fetch('/api/diagnostic/suite/start', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({ profile, fp: fp() }),
      });
      const startData = await startRes.json();
      phpJobId = startData?.job?.id;
      if (!phpJobId) throw new Error(startData?.error || 'suite start failed');

      let probeOk = false;
      try {
        const pStart = await fetch(AGENT() + '/suite/start', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ profile }),
        });
        const pData = await pStart.json();
        probeOk = !!(pData?.ok || pData?.job);
      } catch (_) {
        probeOk = false;
      }

      if (!probeOk) {
        if (status) status.textContent = 'Probe not reachable — start PcLab Probe, then retry.';
        setProgress(0, 'Probe offline');
        return;
      }

      let done = false;
      let probeJob = null;
      while (!done) {
        await new Promise((r) => setTimeout(r, 2000));
        const st = await pollProbeSuite();
        probeJob = st?.job || st;
        const pct = Number(probeJob?.progress || 0);
        const step = probeJob?.step || 'running';
        setProgress(pct, String(step));
        if (status) status.textContent = `${probeJob?.label || 'Suite'}: ${step} (${pct}%)`;

        if (phpJobId) {
          await fetch(`/api/diagnostic/suite/patch/${phpJobId}`, {
            method: 'POST',
            headers: csrfHeaders(),
            body: JSON.stringify({
              status: probeJob?.status || 'running',
              progress: pct,
              step,
              probe_job: probeJob,
            }),
          }).catch(() => {});
        }

        const s = String(probeJob?.status || '');
        if (s === 'completed' || s === 'failed' || s === 'cancelled') {
          done = true;
        }
      }

      if (String(probeJob?.status) === 'cancelled') {
        if (status) status.textContent = 'Suite cancelled.';
        await fetch(`/api/diagnostic/suite/cancel/${phpJobId}`, {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ id: phpJobId }),
        }).catch(() => {});
        return;
      }

      if (status) status.textContent = 'Analyzing results…';
      setProgress(92, 'analyze');

      const fin = await fetch(`/api/diagnostic/suite/finalize/${phpJobId}`, {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({
          id: phpJobId,
          fp: fp(),
          probe: probeJob?.probe || null,
          suite: {
            status: probeJob?.status,
            benches: probeJob?.benches || [],
            stress: probeJob?.stress || {},
            samples: probeJob?.samples || [],
            duration_s: probeJob?.duration_s || null,
          },
        }),
      });
      const finData = await fin.json();
      if (!finData?.ok) throw new Error(finData?.message || finData?.error || 'finalize failed');
      setProgress(100, 'done');
      if (status) status.textContent = 'Full Lab complete.';
      renderResult(finData.job);
    } catch (e) {
      if (status) status.textContent = 'Suite error: ' + (e.message || e);
      setProgress(0, 'error');
    } finally {
      if (runBtn) runBtn.disabled = false;
      if (cancelBtn) cancelBtn.hidden = true;
    }
  }

  async function cancelSuite() {
    try {
      await fetch(AGENT() + '/suite/cancel', { method: 'POST' });
    } catch (_) {}
    const status = el('dx-suite-status');
    if (status) status.textContent = 'Cancel requested…';
  }

  function boot() {
    el('dx-suite-run')?.addEventListener('click', runSuite);
    el('dx-suite-cancel')?.addEventListener('click', cancelSuite);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  window.PcLabSuite = { run: runSuite, cancel: cancelSuite, renderCards };
})();
