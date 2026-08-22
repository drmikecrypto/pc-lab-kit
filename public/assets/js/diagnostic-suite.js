/**
 * Overview programmed suite runner (probe suite + PHP finalize + resume).
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  const LS_PHP = 'pclab_suite_php_job';
  const LS_PROBE = 'pclab_suite_probe_token';

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

  function probeHeaders(json = true) {
    const auth = window.PcLabProbeAuth;
    if (auth) {
      return json ? auth.jsonHeaders() : auth.headers();
    }
    const h = {};
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  async function ensureProbeAuth() {
    if (window.PcLabProbeAuth) {
      await window.PcLabProbeAuth.ensure();
    }
  }

  function el(id) {
    return document.getElementById(id);
  }

  function savePhpJob(id) {
    try {
      if (id) localStorage.setItem(LS_PHP, id);
      else localStorage.removeItem(LS_PHP);
    } catch (_) {}
  }

  function loadPhpJob() {
    try {
      return localStorage.getItem(LS_PHP) || '';
    } catch (_) {
      return '';
    }
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
    // OEM phase markers
    document.querySelectorAll('[data-dx-oem-phase]').forEach((node) => {
      const phase = node.getAttribute('data-dx-oem-phase');
      let on = false;
      if (phase === 'run' && pct < 5) on = true;
      if (phase === 'progress' && pct >= 5 && pct < 92) on = true;
      if (phase === 'verdict' && pct >= 92 && pct < 100) on = true;
      if (phase === 'cert' && pct >= 100) on = true;
      node.classList.toggle('is-active', on);
    });
  }

  function showSuiteError(message, detail) {
    const banner = el('dx-suite-error');
    const status = el('dx-suite-status');
    const suite = el('dx-programmed-suite');
    if (suite) suite.open = true;
    const text = String(message || 'Suite could not start');
    console.error('[PcLabSuite]', text, detail || '');
    if (status) {
      status.textContent = text;
      status.classList.add('is-error');
    }
    if (banner) {
      banner.hidden = false;
      banner.innerHTML = `<strong>Probe not ready</strong><p>${esc(text)}</p>${
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
            'Could not restart Probe from this window. Open the PC Lab Kit desktop app, then Retry.',
            'restart_probe unavailable'
          );
        }
      });
    }
    setProgress(0, 'offline');
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
    try {
      const res = await fetch(`/api/diagnostic/suite/cancel/${phpJobId}`, {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({ id: phpJobId }),
      });
      if (!res.ok) {
        const status = el('dx-suite-status');
        if (status) status.textContent = `Cancel failed (HTTP ${res.status}). Try Discard.`;
      }
    } catch (e) {
      const status = el('dx-suite-status');
      if (status) status.textContent = 'Cancel failed — ' + (e.message || String(e));
    }
  }

  async function probeHealth() {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 4000);
    try {
      await ensureProbeAuth();
      const res = await fetch(AGENT() + '/health', { mode: 'cors', signal: ctrl.signal });
      if (!res.ok) {
        updateProbeSla({ ok: false });
        return { ok: false, detail: `HTTP ${res.status}` };
      }
      const data = await res.json().catch(() => ({}));
      updateProbeSla(data);
      return { ok: true, data };
    } catch (e) {
      updateProbeSla({ ok: false });
      return { ok: false, detail: e.message || String(e) };
    } finally {
      clearTimeout(timer);
    }
  }

  function updateProbeSla(data) {
    const rail = el('dx-probe-sla');
    if (!rail || !data) return;
    const alive = data.ok ? 'alive' : 'down';
    const elev = data.elevated || data.ring0 ? 'elevated' : 'user';
    const svc = data.service_mode ? 'service' : 'sidecar';
    const up = data.uptime_s != null ? `${Math.round(Number(data.uptime_s))}s` : '—';
    rail.hidden = false;
    rail.innerHTML = `<span class="dx-probe-sla__dot is-${alive}"></span>
      <strong>Probe</strong> ${esc(alive)} · ${esc(elev)} · ${esc(svc)} · up ${esc(up)}
      ${data.last_error ? ` · <span class="warn">${esc(String(data.last_error).slice(0, 80))}</span>` : ''}`;
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

  function renderCdmTable(benches) {
    const storage = (benches || []).find((b) => b && (b.id === 'storage' || b.profiles));
    if (!storage?.profiles) return '';
    const rows = Object.entries(storage.profiles)
      .map(([name, p]) => {
        const read = p.read_mbps ?? p.read_iops ?? '—';
        const write = p.write_mbps ?? p.write_iops ?? '—';
        const riops = p.read_iops != null ? esc(String(p.read_iops)) : '—';
        const wiops = p.write_iops != null ? esc(String(p.write_iops)) : '—';
        const rlat = p.read_latency_us != null ? esc(String(p.read_latency_us)) : '—';
        return `<tr><td>${esc(name)}</td><td>${esc(String(read))}</td><td>${esc(String(write))}</td><td>${riops}</td><td>${wiops}</td><td>${rlat}</td></tr>`;
      })
      .join('');
    return `<div class="dx-cdm-matrix"><h4>Storage (CDM-like)</h4>
      <table class="dx-cdm-table"><thead><tr><th>Profile</th><th>Read MB/s</th><th>Write MB/s</th><th>Read IOPS</th><th>Write IOPS</th><th>Lat µs</th></tr></thead>
      <tbody>${rows}</tbody></table>
      <p class="muted fs-xs">Engine: ${esc(storage.engine || storage.method || '—')}${storage.diskspd_available === false ? ' · DiskSpd missing' : ''}</p></div>`;
  }

  function renderResult(job) {
    const panel = el('dx-suite-result');
    if (!panel) return;
    const analysis = job?.result?.analysis || {};
    const cert = analysis.stress_certificate || {};
    const score = analysis.health_score ?? '—';
    const grade = analysis.health_grade ?? '—';
    const benches = analysis.suite?.benches || [];
    const oracleLine =
      cert.stability_margin_pct != null || cert.oracle_grade
        ? ` · oracle <strong>${esc(String(cert.oracle_grade || '—'))}</strong> · margin <strong>${esc(String(cert.stability_margin_pct ?? '—'))}%</strong>`
        : '';
    panel.hidden = false;
    panel.innerHTML = `
      <div class="dx-suite-result__head" data-dx-oem-phase="verdict">
        <h3>Verdict</h3>
        <div class="dx-suite-result__score">
          <span class="dx-suite-result__score-num">${esc(String(score))}</span>
          <span class="dx-suite-result__score-grade">${esc(String(grade))}</span>
        </div>
        <p class="dx-suite-result__meta">Stress <strong>${esc(cert.verdict || '—')}</strong>${oracleLine}</p>
      </div>
      ${renderCdmTable(benches)}
      <div class="dx-suite-result__actions" data-dx-oem-phase="cert">
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
    setProgress(100, 'done');

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

  async function finalizeFromProbe(phpJobId, probeJob, planFallback) {
    const status = el('dx-suite-status');
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
          plan: probeJob?.plan || planFallback || null,
        },
        fingerprint: probeJob?.probe?.devices?.fingerprint || window.__dxLastDevices?.fingerprint || null,
        platform: probeJob?.probe?.devices?.platform || window.__dxLastDevices?.platform || null,
      }),
    });
    const finData = await fin.json().catch(() => ({}));
    if (!fin.ok || !finData?.ok) throw new Error(finData?.message || finData?.error || 'finalize failed');
    setProgress(100, 'done');
    if (status) status.textContent = 'Programmed suite complete.';
    savePhpJob('');
    try {
      localStorage.removeItem(LS_PROBE);
    } catch (_) {}
    renderResult(finData.job);
    return finData.job;
  }

  async function waitProbeAndFinalize(phpJobId, planFallback) {
    const status = el('dx-suite-status');
    const runBtn = el('dx-suite-run');
    const cancelBtn = el('dx-suite-cancel');
    let done = false;
    let probeJob = null;
    while (!done) {
      await new Promise((r) => setTimeout(r, 2000));
      const st = await pollProbeSuite();
      probeJob = st?.job || st;
      const pct = Number(probeJob?.progress || 0);
      const step = probeJob?.step || 'running';
      const planSteps = probeJob?.plan?.steps || planFallback?.steps || [];
      const match = Array.isArray(planSteps)
        ? planSteps.find((s) => s && (s.id === step || String(step).includes(String(s.id || '').replace('bench:', ''))))
        : null;
      const reason = match?.reason || '';
      setProgress(pct, String(step));
      if (status) {
        status.textContent = reason
          ? `${probeJob?.label || 'Suite'}: ${step} (${pct}%) — ${reason}`
          : `${probeJob?.label || 'Suite'}: ${step} (${pct}%)`;
      }
      const planBox = el('dx-suite-plan-preview');
      if (planBox && Array.isArray(planSteps) && planSteps.length && planBox.hidden) {
        planBox.hidden = false;
        planBox.innerHTML = `<strong>${esc(probeJob?.plan?.label || 'Plan')}</strong>
          <ol>${planSteps.map((s) => `<li class="${s.id === step ? 'is-active' : ''}"><strong>${esc(s.label || s.id)}</strong>${s.reason ? ` — ${esc(s.reason)}` : ''}</li>`).join('')}</ol>`;
      }

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
      if (s === 'completed' || s === 'failed' || s === 'cancelled' || s === 'interrupted') {
        done = true;
      }
    }

    if (String(probeJob?.status) === 'cancelled' && !(probeJob?.benches?.length || probeJob?.probe)) {
      if (status) status.textContent = 'Suite cancelled.';
      await cancelPhpJob(phpJobId);
      savePhpJob('');
      return;
    }

    // Interrupted / failed with partial work → still finalize if we have benches or probe.
    const hasWork = !!(probeJob?.benches?.length || probeJob?.probe || probeJob?.stress);
    if (String(probeJob?.status) === 'failed' && !hasWork) {
      showSuiteError('Probe suite failed.', probeJob?.error || probeJob?.step || 'failed');
      // Soft-cancel only — keep PHP job for retry finalize if payload appears later
      await cancelPhpJob(phpJobId);
      return;
    }

    if (String(probeJob?.status) === 'interrupted' && !hasWork) {
      showResumeBanner(phpJobId, probeJob);
      if (runBtn) runBtn.disabled = false;
      if (cancelBtn) cancelBtn.hidden = true;
      return;
    }

    try {
      await finalizeFromProbe(phpJobId, probeJob, planFallback);
    } catch (e) {
      // Do NOT cancel PHP job — probe work is preserved for Resume.
      showResumeBanner(phpJobId, probeJob, e.message || e);
    }
  }

  function showResumeBanner(phpJobId, probeJob, errMsg) {
    const banner = el('dx-suite-resume');
    const status = el('dx-suite-status');
    if (status) status.textContent = errMsg ? `Paused — ${errMsg}` : 'Suite interrupted — resume available';
    if (!banner) return;
    banner.hidden = false;
    const step = probeJob?.step || 'unknown';
    const pct = probeJob?.progress ?? '—';
    banner.innerHTML = `<strong>Resume programmed suite</strong>
      <p>Progress saved at <code>${esc(String(step))}</code> (${esc(String(pct))}%). Finalize without re-running completed steps.</p>
      <div class="dx-suite-error__actions">
        <button type="button" class="dx-btn primary" id="dx-suite-resume-btn">Resume</button>
        <button type="button" class="dx-btn ghost" id="dx-suite-discard-btn">Discard</button>
      </div>`;
    banner.querySelector('#dx-suite-resume-btn')?.addEventListener('click', () => {
      banner.hidden = true;
      resumeSuite(phpJobId);
    });
    banner.querySelector('#dx-suite-discard-btn')?.addEventListener('click', () => {
      banner.hidden = true;
      discardSuite(phpJobId);
    });
  }

  async function discardSuite(phpJobId) {
    const status = el('dx-suite-status');
    try {
      if (phpJobId) {
        const res = await fetch(`/api/diagnostic/suite/discard/${phpJobId}`, {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ id: phpJobId }),
        });
        if (!res.ok && status) status.textContent = `Discard failed (HTTP ${res.status}).`;
      }
      await ensureProbeAuth();
      const pRes = await fetch(AGENT() + '/suite/discard', {
        method: 'POST',
        mode: 'cors',
        headers: probeHeaders(),
        body: JSON.stringify({}),
      });
      if (!pRes.ok && status) status.textContent = `Probe discard failed (HTTP ${pRes.status}).`;
      else if (status) status.textContent = 'Suite discarded.';
    } catch (e) {
      if (status) status.textContent = 'Discard failed — ' + (e.message || String(e));
    }
    savePhpJob('');
    setProgress(0, 'Idle');
  }

  async function resumeSuite(phpJobId) {
    const status = el('dx-suite-status');
    const runBtn = el('dx-suite-run');
    const cancelBtn = el('dx-suite-cancel');
    if (runBtn) runBtn.disabled = true;
    if (cancelBtn) cancelBtn.hidden = false;
    clearSuiteError();
    if (status) status.textContent = 'Resuming suite…';

    let id = phpJobId || loadPhpJob();
    try {
      await ensureProbeAuth();
      await probeHealth();
      const st = await pollProbeSuite();
      const probeJob = st?.job || st;
      const probeDone = ['completed', 'failed', 'interrupted'].includes(String(probeJob?.status || ''));
      const hasWork = !!(probeJob?.benches?.length || probeJob?.probe);

      if (!id) {
        const list = await fetch('/api/diagnostic/suite/resumable').then((r) => r.json()).catch(() => ({}));
        id = list?.jobs?.[0]?.id || '';
      }
      if (!id) {
        const startRes = await fetch('/api/diagnostic/suite/start', {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ profile: el('dx-suite-profile')?.value || 'adaptive', fp: fp() }),
        });
        const startData = await startRes.json();
        id = startData?.job?.id;
      }
      if (!id) throw new Error('No suite job to resume');
      savePhpJob(id);

      if (probeDone && hasWork) {
        await finalizeFromProbe(id, probeJob, probeJob?.plan);
        return;
      }

      const pStart = await fetch(AGENT() + '/suite/start', {
        method: 'POST',
        mode: 'cors',
        headers: probeHeaders(),
        body: JSON.stringify({ resume: true, resume_token: probeJob?.resume_token || probeJob?.id || '' }),
      });
      const pData = await pStart.json().catch(() => ({}));
      if (!pStart.ok || pData?.ok === false) {
        if (hasWork) {
          await finalizeFromProbe(id, probeJob, probeJob?.plan);
          return;
        }
        throw new Error(pData?.error || 'resume refused');
      }
      await waitProbeAndFinalize(id, pData?.plan || probeJob?.plan);
    } catch (e) {
      showSuiteError('Resume failed: ' + (e.message || e));
    } finally {
      if (runBtn) runBtn.disabled = false;
      if (cancelBtn) cancelBtn.hidden = true;
    }
  }

  async function runSuite() {
    const profile = el('dx-suite-profile')?.value || 'adaptive';
    const status = el('dx-suite-status');
    const runBtn = el('dx-suite-run');
    const cancelBtn = el('dx-suite-cancel');
    if (runBtn) runBtn.disabled = true;
    if (cancelBtn) cancelBtn.hidden = false;
    clearSuiteError();
    const resumeBox = el('dx-suite-resume');
    if (resumeBox) resumeBox.hidden = true;
    if (status) status.textContent = 'Checking Probe…';
    setProgress(2, 'Starting');

    let phpJobId = null;
    try {
      await ensureProbeAuth();
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

      if (status) status.textContent = 'Starting programmed suite…';
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
      savePhpJob(phpJobId);

      let pStart;
      let pData = {};
      try {
        pStart = await fetch(AGENT() + '/suite/start', {
          method: 'POST',
          mode: 'cors',
          headers: probeHeaders(),
          body: JSON.stringify({ profile }),
        });
        pData = await pStart.json().catch(() => ({}));
      } catch (e) {
        showSuiteError('Probe suite start failed — is Probe running?', e.message || e);
        showResumeBanner(phpJobId, null, e.message || e);
        return;
      }

      if (!pStart.ok || pData?.ok === false || !(pData?.ok || pData?.job)) {
        const why = pData?.error || pData?.message || (pData?.already_running ? 'A suite is already running' : `HTTP ${pStart.status}`);
        if (pData?.error === 'already_running' || pData?.resumable) {
          showResumeBanner(phpJobId, pData?.job, why);
          return;
        }
        showSuiteError('Probe refused to start the suite.', why);
        return;
      }

      await waitProbeAndFinalize(phpJobId, pData?.plan);
    } catch (e) {
      // Preserve PHP job for resume — do not hard-cancel.
      showResumeBanner(phpJobId, null, e.message || e);
      showSuiteError('Suite error: ' + (e.message || e));
    } finally {
      if (runBtn) runBtn.disabled = false;
      if (cancelBtn) cancelBtn.hidden = true;
      updateSuiteCtaLabel();
    }
  }

  async function cancelSuite() {
    try {
      await ensureProbeAuth();
      const res = await fetch(AGENT() + '/suite/cancel', {
        method: 'POST',
        mode: 'cors',
        headers: probeHeaders(),
        body: '{}',
      });
      if (!res.ok) {
        const status = el('dx-suite-status');
        if (status) status.textContent = `Probe cancel failed (HTTP ${res.status}).`;
      }
    } catch (e) {
      const status = el('dx-suite-status');
      if (status) status.textContent = 'Probe cancel failed — ' + (e.message || String(e));
    }
    const phpId = loadPhpJob();
    if (phpId) await cancelPhpJob(phpId);
    const status = el('dx-suite-status');
    if (status) status.textContent = 'Cancel requested — checkpoint kept for Resume.';
  }

  async function checkResumableOnBoot() {
    try {
      await probeHealth();
      const [phpList, probeSt] = await Promise.all([
        fetch('/api/diagnostic/suite/resumable').then((r) => r.json()).catch(() => ({})),
        pollProbeSuite().catch(() => null),
      ]);
      const phpJob = phpList?.jobs?.[0];
      const probeJob = probeSt?.job || probeSt;
      const probeResumable = probeJob && (probeJob.resumable || ['interrupted', 'running', 'completed', 'failed'].includes(String(probeJob.status)));
      if (phpJob || (probeResumable && (probeJob.benches?.length || probeJob.probe || probeJob.status === 'running'))) {
        showResumeBanner(phpJob?.id || loadPhpJob(), probeJob);
      }
    } catch (_) {}
  }

  function updateSuiteCtaLabel() {
    const btn = el('dx-suite-run');
    const sel = el('dx-suite-profile');
    if (!btn || !sel || btn.disabled) return;
    const opt = sel.options[sel.selectedIndex];
    const label = (opt?.textContent || 'Lab').replace(/\s*\(~[^)]+\)\s*$/, '').trim();
    btn.textContent = `Start ${label}`;
  }

  function boot() {
    if (!el('dx-suite-run')) {
      console.warn('[PcLabSuite] #dx-suite-run missing — suite UI failed to initialize');
      return;
    }
    if (window.PcLabProbeAuth) {
      window.PcLabProbeAuth.ensure().catch(() => {});
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
      } else if (t.closest('#dx-suite-preview-plan')) {
        ev.preventDefault();
        previewPlan();
      } else if (t.closest('#dx-platform-audit-export')) {
        ev.preventDefault();
        exportPlatformAudit();
      }
    });
    el('dx-suite-import-file')?.addEventListener('change', importSession);
    el('dx-suite-profile')?.addEventListener('change', updateSuiteCtaLabel);
    updateSuiteCtaLabel();
    checkResumableOnBoot();
    setInterval(() => {
      probeHealth().catch(() => updateProbeSla({ ok: false }));
    }, 15000);
  }

  async function previewPlan() {
    const box = el('dx-suite-plan-preview');
    const profile = el('dx-suite-profile')?.value || 'adaptive';
    if (box) {
      box.hidden = false;
      box.textContent = 'Building plan…';
    }
    try {
      let devices = window.__dxLastDevices || null;
      if (!devices) {
        const r = await fetch(AGENT() + '/devices', { mode: 'cors' });
        if (r.ok) devices = await r.json();
      }
      const res = await fetch('/api/diagnostic/suite/plan', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({
          profile,
          fp: fp(),
          devices,
          fingerprint: devices?.fingerprint,
          platform: devices?.platform,
        }),
      });
      const data = await res.json();
      if (!box) return;
      const steps = data.steps || [];
      const why = steps
        .map((s) => `<li><strong>${esc(s.label || s.id)}</strong>${s.reason ? ` — ${esc(s.reason)}` : ''}</li>`)
        .join('');
      box.innerHTML = `<strong>${esc(data.label || profile)}</strong>
        ${data.gated ? ` · <span class="warn">GATED</span> ${esc(data.gate_reason || '')}` : ''}
        · ~${esc(data.duration_hint_min ?? '—')} min
        · coverage ${esc(data.coverage_score ?? '—')}%
        <ol>${why || '<li class="muted">No steps</li>'}</ol>`;
    } catch (e) {
      if (box) box.textContent = 'Plan preview failed — is Probe online?';
    }
  }

  async function exportPlatformAudit() {
    try {
      let devices = window.__dxLastDevices || null;
      let drivers = window.__dxLastDrivers || null;
      if (!devices) {
        const r = await fetch(AGENT() + '/devices', { mode: 'cors' });
        if (r.ok) devices = await r.json();
      }
      if (!drivers) {
        const r = await fetch(AGENT() + '/drivers', { mode: 'cors' });
        if (r.ok) {
          const wrap = await r.json();
          drivers = wrap.drivers || wrap;
        }
      }
      let plan = null;
      try {
        const pr = await fetch('/api/diagnostic/suite/plan', {
          method: 'POST',
          headers: csrfHeaders(),
          body: JSON.stringify({ profile: 'adaptive', devices, fingerprint: devices?.fingerprint, platform: devices?.platform }),
        });
        plan = await pr.json();
      } catch (_) {}
      const res = await fetch('/api/diagnostic/platform/audit', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify({
          devices,
          fingerprint: devices?.fingerprint,
          platform: devices?.platform,
          drivers,
          plan,
        }),
      });
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'audit failed');
      const blob = new Blob([data.html || JSON.stringify(data.audit, null, 2)], {
        type: data.html ? 'text/html' : 'application/json',
      });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = data.html ? 'platform-audit.html' : 'platform-audit.json';
      a.click();
      URL.revokeObjectURL(a.href);
    } catch (e) {
      alert('Platform Audit export failed: ' + (e.message || e));
    }
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
          <p class="muted fs-xs">Run a Programmed suite on this machine to compute drift vs current hardware.</p>
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

  window.PcLabSuite = {
    run: runSuite,
    cancel: cancelSuite,
    resume: resumeSuite,
    discard: discardSuite,
    renderCards,
    probeHealth,
  };
})();
