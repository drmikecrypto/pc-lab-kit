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
    const progress = bar?.parentElement;
    const label = el('dx-suite-step');
    if (bar) bar.style.width = Math.max(0, Math.min(100, pct)) + '%';
    if (label) label.textContent = step || '';
    if (progress) {
      progress.classList.toggle('is-error', String(step || '').toLowerCase().includes('error') || String(step || '').toLowerCase().includes('offline'));
      progress.setAttribute('aria-hidden', pct <= 0 && !progress.classList.contains('is-error') ? 'true' : 'false');
    }
  }

  function showSuiteError(message, detail) {
    const banner = el('dx-suite-error');
    const status = el('dx-suite-status');
    const text = String(message || 'Suite failed');
    console.error('[PcLabSuite]', text, detail || '');
    if (status) {
      status.textContent = text;
      status.classList.add('is-error');
    }
    if (banner) {
      banner.hidden = false;
      banner.innerHTML = `<strong>Full Lab could not start</strong><p>${esc(text)}</p>${
        detail ? `<p class="fs-xs muted">${esc(String(detail).slice(0, 280))}</p>` : ''
      }<div class="dx-suite-error__actions">
        <button type="button" class="dx-btn primary" id="dx-suite-retry">Retry</button>
        <button type="button" class="dx-btn ghost" id="dx-suite-restart-probe">Restart Probe</button>
      </div>`;
      banner.querySelector('#dx-suite-retry')?.addEventListener('click', () => {
        banner.hidden = true;
        runSuite();
      });
      banner.querySelector('#dx-suite-restart-probe')?.addEventListener('click', async () => {
        const ok = await tryRestartProbe();
        if (ok) {
          banner.hidden = true;
          runSuite();
        } else {
          showSuiteError(
            'Could not restart Probe from this window. Use the PC Lab Kit desktop app, then Retry.',
            'restart_probe unavailable'
          );
        }
      });
    }
    setProgress(0, 'error');
  }

  function clearSuiteError() {
    const banner = el('dx-suite-error');
    const status = el('dx-suite-status');
    if (banner) {
      banner.hidden = true;
      banner.innerHTML = '';
    }
    if (status) status.classList.remove('is-error');
  }

  async function cancelPhpJob(phpJobId) {
    if (!phpJobId) return;
    await fetch(`/api/diagnostic/suite/cancel/${phpJobId}`, {
      method: 'POST',
      headers: csrfHeaders(),
      body: JSON.stringify({ id: phpJobId }),
    }).catch(() => {});
  }

  async function probeHealth() {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 4000);
    try {
      const res = await fetch(AGENT() + '/health', { mode: 'cors', signal: ctrl.signal });
      if (!res.ok) {
        return { ok: false, detail: `HTTP ${res.status}` };
      }
      const data = await res.json().catch(() => ({}));
      return { ok: true, data };
    } catch (e) {
      return { ok: false, detail: e.message || String(e) };
    } finally {
      clearTimeout(timer);
    }
  }

  async function tryRestartProbe() {
    try {
      const invoke =
        window.__TAURI__?.core?.invoke ||
        window.__TAURI_INTERNALS__?.invoke ||
        null;
      if (typeof invoke === 'function') {
        await invoke('restart_probe');
        return true;
      }
    } catch (_) {}
    return false;
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
    const oracleLine =
      cert.stability_margin_pct != null || cert.oracle_grade
        ? ` · oracle <strong>${esc(String(cert.oracle_grade || '—'))}</strong> · margin <strong>${esc(String(cert.stability_margin_pct ?? '—'))}%</strong>`
        : '';
    panel.hidden = false;
    panel.innerHTML = `
      <div class="dx-suite-result__head">
        <h3>Full Lab complete</h3>
        <div class="dx-suite-result__score">
          <span class="dx-suite-result__score-num">${esc(String(score))}</span>
          <span class="dx-suite-result__score-grade">${esc(String(grade))}</span>
        </div>
        <p class="dx-suite-result__meta">Stress <strong>${esc(cert.verdict || '—')}</strong>${oracleLine}</p>
      </div>
      <div class="dx-suite-result__actions">
        <button type="button" class="dx-btn primary" id="dx-suite-open-report">Open report</button>
        <button type="button" class="dx-btn ghost" id="dx-suite-open-cert">Assembly Certificate</button>
        <button type="button" class="dx-btn ghost" id="dx-suite-show-topology">Topology 3D</button>
        <button type="button" class="dx-btn ghost" id="dx-suite-export-session">Export .pclab</button>
        <button type="button" class="dx-btn ghost" data-dx-goto="history">History</button>
        <button type="button" class="dx-btn ghost" data-dx-goto="drivers">Drivers</button>
        <button type="button" class="dx-btn ghost" data-dx-goto="stress">Stress</button>
        <button type="button" class="dx-btn ghost" data-dx-goto="openbook">Open Book</button>
      </div>
      <div id="dx-suite-report-frame" hidden></div>
      <div id="dx-suite-cert-frame" hidden></div>
      <div id="dx-suite-topology" class="dx-topology dx-topology-3d" hidden style="min-height:360px"></div>`;

    renderCards(analysis.advisor_cards || []);

    panel.querySelectorAll('[data-dx-goto]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const tab = btn.getAttribute('data-dx-goto');
        if (window.dxActivateTab) window.dxActivateTab(tab);
      });
    });

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
      box.innerHTML = '<p class="muted">Building 3D topology…</p>';
      window.dispatchEvent(new CustomEvent('dx:suite-stress-start'));
      try {
        const res = await fetch('/api/diagnostic/topology', {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ hardware_graph: analysis.hardware_graph || null }),
        });
        const data = await res.json();
        if (window.PcLabTopology3d?.render && data.topology_3d) {
          box.innerHTML = '';
          window.PcLabTopology3d.render(box, data);
        } else if (window.PcLabTopology?.render) {
          window.PcLabTopology.render(box, data.topology);
        } else {
          box.innerHTML = `<pre class="dx-topology-fallback">${esc(JSON.stringify(data.topology?.summary || {}, null, 2))}</pre>`;
        }
      } catch (e) {
        box.innerHTML = `<p class="muted">Topology failed: ${esc(e.message || e)}</p>`;
      }
    });

    el('dx-suite-export-session')?.addEventListener('click', () => {
      const session = job?.result?.pclab_session;
      if (!session) return;
      const blob = new Blob([JSON.stringify(session, null, 2)], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = job?.result?.pclab_session_file || 'session.pclab.json';
      a.click();
      URL.revokeObjectURL(a.href);
    });
  }

  async function pollProbeSuite() {
    const res = await fetch(AGENT() + '/suite/status', { mode: 'cors' });
    if (!res.ok) throw new Error(`suite status HTTP ${res.status}`);
    return res.json();
  }

  async function runSuite() {
    const profile = el('dx-suite-profile')?.value || 'standard';
    const status = el('dx-suite-status');
    const runBtn = el('dx-suite-run');
    const cancelBtn = el('dx-suite-cancel');
    if (runBtn) runBtn.disabled = true;
    if (cancelBtn) cancelBtn.hidden = false;
    clearSuiteError();
    if (status) status.textContent = 'Checking Probe…';
    setProgress(2, 'Starting');

    let phpJobId = null;
    try {
      let health = await probeHealth();
      if (!health.ok) {
        await tryRestartProbe();
        await new Promise((r) => setTimeout(r, 800));
        health = await probeHealth();
      }
      if (!health.ok) {
        showSuiteError(
          'Probe is not reachable. Open PC Lab Kit desktop so the bundled probe starts, then retry.',
          health.detail
        );
        return;
      }

      if (status) status.textContent = 'Starting Full Lab…';
      const startRes = await fetch('/api/diagnostic/suite/start', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({ profile, fp: fp() }),
      });
      const startData = await startRes.json().catch(() => ({}));
      if (!startRes.ok) {
        throw new Error(startData?.error || startData?.message || `suite start HTTP ${startRes.status}`);
      }
      phpJobId = startData?.job?.id;
      if (!phpJobId) throw new Error(startData?.error || 'suite start failed');

      let pStart;
      let pData = {};
      try {
        pStart = await fetch(AGENT() + '/suite/start', {
          method: 'POST',
          mode: 'cors',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ profile }),
        });
        pData = await pStart.json().catch(() => ({}));
      } catch (e) {
        await cancelPhpJob(phpJobId);
        showSuiteError('Probe suite start failed — is Probe running?', e.message || e);
        return;
      }

      if (!pStart.ok || pData?.ok === false || !(pData?.ok || pData?.job)) {
        await cancelPhpJob(phpJobId);
        const why = pData?.error || pData?.message || (pData?.already_running ? 'A suite is already running' : `HTTP ${pStart.status}`);
        showSuiteError('Probe refused to start the suite.', why);
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
        await cancelPhpJob(phpJobId);
        return;
      }

      if (String(probeJob?.status) === 'failed') {
        showSuiteError('Probe suite failed.', probeJob?.error || probeJob?.step || 'failed');
        await cancelPhpJob(phpJobId);
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
      const finData = await fin.json().catch(() => ({}));
      if (!fin.ok || !finData?.ok) throw new Error(finData?.message || finData?.error || 'finalize failed');
      setProgress(100, 'done');
      if (status) status.textContent = 'Full Lab complete.';
      renderResult(finData.job);
    } catch (e) {
      await cancelPhpJob(phpJobId);
      showSuiteError('Suite error: ' + (e.message || e));
    } finally {
      if (runBtn) runBtn.disabled = false;
      if (cancelBtn) cancelBtn.hidden = true;
    }
  }

  async function cancelSuite() {
    try {
      await fetch(AGENT() + '/suite/cancel', { method: 'POST', mode: 'cors' });
    } catch (_) {}
    const status = el('dx-suite-status');
    if (status) status.textContent = 'Cancel requested…';
  }

  function boot() {
    if (!el('dx-suite-run')) {
      console.warn('[PcLabSuite] #dx-suite-run missing — suite UI failed to initialize');
      return;
    }
    document.addEventListener('click', (ev) => {
      const t = ev.target;
      if (!(t instanceof Element)) return;
      if (t.closest('#dx-suite-run')) {
        ev.preventDefault();
        runSuite();
      } else if (t.closest('#dx-suite-cancel')) {
        ev.preventDefault();
        cancelSuite();
      }
    });
    el('dx-suite-import-file')?.addEventListener('change', importSession);
  }

  async function importSession(ev) {
    const file = ev.target?.files?.[0];
    const panel = el('dx-suite-import-result');
    if (!file || !panel) return;
    panel.hidden = false;
    panel.innerHTML = '<p class="muted">Importing session…</p>';
    try {
      const json = await file.text();
      const res = await fetch('/api/diagnostic/session/import', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({ json }),
      });
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'import failed');
      const drift = data.drift;
      const verified = data.session?.verified ? 'verified' : 'unverified signature';
      const aging = drift ? `${drift.silicon_aging_index}/100 (${drift.label})` : '—';
      const notes = (drift?.notes || []).map((n) => `<li>${esc(n)}</li>`).join('');
      panel.innerHTML = `
        <div class="dx-suite-import-card">
          <h3>Imported .pclab session</h3>
          <p class="muted fs-sm">${esc(verified)} · signed ${esc(data.session?.signed_at || '—')}</p>
          <p>Silicon aging index: <strong>${esc(String(aging))}</strong></p>
          ${notes ? `<ul class="fs-sm">${notes}</ul>` : ''}
          <p class="muted fs-xs">Run Full Lab on this machine to compute drift vs current hardware.</p>
        </div>`;
      window.__dxImportedSession = data.session;
      window.dispatchEvent(new CustomEvent('dx:session-imported', { detail: data }));
    } catch (e) {
      panel.innerHTML = `<p class="muted">Import failed: ${esc(e.message || e)}</p>`;
    } finally {
      ev.target.value = '';
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  window.PcLabSuite = { run: runSuite, cancel: cancelSuite, renderCards, probeHealth };
})();
