/**
 * Test tab — choose hardware targets + duration, then run Probe stress.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  const MAX_SECONDS = 86400;
  let running = false;
  let finished = false;
  let pollTimer = null;

  function el(id) {
    return document.getElementById(id);
  }

  function esc(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function selectedTargets() {
    return Array.from(document.querySelectorAll('input[name="dx-test-target"]:checked')).map((c) => c.value);
  }

  function resolveProfile() {
    if (el('dx-stress-oracle')?.checked) return 'oracle';
    const gpuMode = el('dx-stress-gpu-mode')?.value || 'fixed';
    const t = selectedTargets();
    if (!t.length) return '';
    if (t.length === 1 && t[0] === 'gpu' && gpuMode !== 'fixed') {
      return gpuMode === 'adaptive' ? 'gpu_adaptive' : gpuMode === 'variable' ? 'gpu_variable' : gpuMode === 'switch' ? 'gpu_switch' : 'gpu';
    }
    if (t.length === 1) return t[0];
    if (t.length === 3) return 'combined';
    if (t.includes('cpu') && t.includes('gpu') && !t.includes('memory')) return 'combined';
    if (t.includes('cpu') && t.includes('memory') && !t.includes('gpu')) return 'combined';
    if (t.includes('gpu') && t.includes('memory') && !t.includes('cpu')) return 'combined';
    return 'combined';
  }

  function syncHiddenProfile() {
    const profile = resolveProfile() || 'combined';
    const sel = el('dx-stress-profile');
    if (sel) sel.value = profile;
    return profile;
  }

  function durationSeconds() {
    const hours = Math.max(0, Math.min(24, Number(el('dx-stress-hours')?.value || 0)));
    const minutes = Math.max(0, Math.min(1440, Number(el('dx-stress-minutes')?.value || 0)));
    let sec = Math.round(hours * 3600 + minutes * 60);
    if (sec < 5) sec = 5;
    if (sec > MAX_SECONDS) sec = MAX_SECONDS;
    return sec;
  }

  function formatDurationLabel(sec) {
    if (sec < 60) return `${sec}s`;
    const m = Math.round(sec / 60);
    if (m < 60) return `${m} min`;
    const h = Math.floor(m / 60);
    const rem = m % 60;
    return rem ? `${h}h ${rem}m` : `${h}h`;
  }

  function targetLabel() {
    if (el('dx-stress-oracle')?.checked) return 'Oracle';
    const t = selectedTargets();
    if (!t.length) return '';
    const map = { cpu: 'CPU', gpu: 'GPU', memory: 'Memory' };
    let label = t.map((x) => map[x] || x).join('+');
    if (t.length === 1 && t[0] === 'gpu') {
      const mode = el('dx-stress-gpu-mode')?.value || 'fixed';
      if (mode !== 'fixed') label = `GPU ${mode}`;
    }
    return label;
  }

  function updateRunLabel() {
    const btn = el('dx-stress-run');
    if (!btn || running) return;
    const targets = targetLabel();
    const sec = durationSeconds();
    if (!targets) {
      btn.textContent = 'Select a target';
      btn.disabled = true;
      return;
    }
    btn.disabled = false;
    btn.textContent = `Start ${targets} · ${formatDurationLabel(sec)}`;
    syncHiddenProfile();
  }

  function setStatus(text, isError) {
    const s = el('dx-stress-status');
    const live = el('dx-stress-live');
    if (s) {
      s.textContent = text;
      s.classList.toggle('is-error', !!isError);
    }
    if (live && text) {
      live.innerHTML = `<p class="${isError ? 'is-error' : ''}">${esc(text)}</p>`;
    }
  }

  function setProgress(pct) {
    const bar = el('dx-stress-progress-bar');
    const wrap = el('dx-stress-progress');
    if (bar) bar.style.width = Math.max(0, Math.min(100, pct)) + '%';
    if (wrap) wrap.setAttribute('aria-hidden', pct <= 0 ? 'true' : 'false');
  }

  function applyPreselect() {
    let target = '';
    try {
      target = sessionStorage.getItem('pclab_test_preselect') || '';
      sessionStorage.removeItem('pclab_test_preselect');
    } catch (_) {}
    if (!target) return;
    document.querySelectorAll('input[name="dx-test-target"]').forEach((cb) => {
      cb.checked = cb.value === target;
    });
    if (el('dx-stress-oracle')) el('dx-stress-oracle').checked = false;
    updateRunLabel();
  }

  async function startStress() {
    if (running) return;
    const profile = syncHiddenProfile();
    if (!profile) {
      setStatus('Select at least one target.', true);
      return;
    }
    const seconds = durationSeconds();
    if (seconds > 1800) {
      const mins = Math.round(seconds / 60);
      if (
        !window.confirm(
          `Run ${targetLabel() || profile} for ${mins} minutes (${(seconds / 3600).toFixed(2)} h)? Long soaks heat the system — stay nearby.`
        )
      ) {
        return;
      }
    }

    running = true;
    finished = false;
    const runBtn = el('dx-stress-run');
    if (runBtn) runBtn.disabled = true;
    const stop = el('dx-stress-stop');
    if (stop) stop.hidden = false;
    setProgress(3);
    setStatus(`Starting ${targetLabel() || profile} for ${formatDurationLabel(seconds)}…`, false);

    try {
      if (window.PcLabProbeAuth) await window.PcLabProbeAuth.ensure();
      const health = await fetch(AGENT() + '/health', { mode: 'cors' });
      if (!health.ok) throw new Error('Probe offline — open the desktop app, then retry.');

      const path = profile === 'oracle' ? '/stress/oracle/start' : '/stress/run';
      const body =
        profile === 'oracle'
          ? { seconds, collect_samples: true }
          : {
              id: profile,
              seconds,
              percent: 100,
              collect_samples: true,
              gpu_mode: el('dx-stress-gpu-mode')?.value || 'fixed',
            };

      const res = await fetch(AGENT() + path, {
        method: 'POST',
        mode: 'cors',
        headers: (window.PcLabProbeAuth && window.PcLabProbeAuth.jsonHeaders()) || {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data.ok === false) {
        throw new Error(data.error || data.message || `HTTP ${res.status}`);
      }

      setStatus(`Running ${targetLabel() || profile} · ${formatDurationLabel(seconds)}`, false);
      window.dispatchEvent(new CustomEvent('dx:suite-stress-start'));

      const started = Date.now();
      clearInterval(pollTimer);
      pollTimer = setInterval(async () => {
        const elapsed = (Date.now() - started) / 1000;
        const pct = Math.min(99, (elapsed / seconds) * 100);
        setProgress(pct);
        try {
          const t = await fetch(AGENT() + '/telemetry', { mode: 'cors' });
          if (t.ok) {
            const tel = await t.json();
            const cpu = tel.cpu_temp ?? tel.thermal?.cpu?.package_c;
            const gpu = tel.gpu_temp ?? tel.thermal?.gpu?.core_c;
            const hs = tel.gpu_hotspot ?? tel.thermal?.gpu?.hot_spot_c;
            setStatus(
              `Running ${targetLabel() || profile} · ${Math.floor(elapsed)}/${seconds}s` +
                (cpu != null ? ` · CPU ${Math.round(cpu)}°` : '') +
                (gpu != null ? ` · GPU ${Math.round(gpu)}°` : '') +
                (hs != null ? ` · HS ${Math.round(hs)}°` : ''),
              false
            );
          }
        } catch (_) {}
        if (elapsed >= seconds) {
          clearInterval(pollTimer);
          pollTimer = null;
          finishOk(data);
        }
      }, 2000);

      if (data.stress || data.result || data.verdict || data.status === 'completed') {
        clearInterval(pollTimer);
        pollTimer = null;
        finishOk(data);
      }
    } catch (e) {
      running = false;
      updateRunLabel();
      el('dx-stress-stop') && (el('dx-stress-stop').hidden = true);
      setProgress(0);
      setStatus('Test failed: ' + (e.message || e), true);
    }
  }

  async function issueCertificate(data) {
    const run = data.stress || data.result || data;
    const samples = run.samples || data.samples || [];
    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
      const res = await fetch('/api/diagnostic/stress/certificate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
        body: JSON.stringify({ run, samples }),
      });
      const out = await res.json().catch(() => ({}));
      const cert = out.certificate || out;
      const verdict = cert.verdict || run.status || 'completed';
      const status = el('dx-ob-cert-status');
      const actions = el('dx-ob-cert-actions');
      if (status) {
        status.innerHTML = `Stress <strong>${esc(String(verdict))}</strong> · ready for shop handoff`;
      }
      let html = cert.html || null;
      if (!html && cert.document) {
        html = `<pre>${esc(JSON.stringify(cert.document, null, 2))}</pre>`;
      }
      if (actions) {
        actions.innerHTML = `<button type="button" class="dx-btn primary" id="dx-stress-open-cert">Open stress certificate</button>
          <button type="button" class="dx-btn ghost" data-dx-goto="command">Overview handoff</button>`;
        el('dx-stress-open-cert')?.addEventListener('click', () => {
          const frame = el('dx-ob-cert-frame');
          if (frame && html) {
            frame.hidden = false;
            frame.innerHTML = html;
          } else if (html) {
            const w = window.open('', '_blank');
            if (w) {
              w.document.write(html);
              w.document.close();
            }
          }
        });
      }
      try {
        sessionStorage.setItem(
          'pclab_last_stress_cert',
          JSON.stringify({
            verdict,
            id: run.id || resolveProfile(),
            summary: cert.summary || run.note || '',
            html: html || null,
          })
        );
      } catch (_) {}
      window.dispatchEvent(new CustomEvent('dx:stress-cert', { detail: cert }));
      if (window.PcLabOpenBook?.applySuiteCert) {
        window.PcLabOpenBook.applySuiteCert({
          result: { analysis: { stress_certificate: cert }, assembly_certificate_html: html },
        });
      }
    } catch (_) {
      /* certificate optional */
    }
  }

  function finishOk(data) {
    if (finished) return;
    finished = true;
    clearInterval(pollTimer);
    pollTimer = null;
    running = false;
    updateRunLabel();
    el('dx-stress-stop') && (el('dx-stress-stop').hidden = true);
    setProgress(100);
    const verdict = data.verdict || data.stress?.verdict || data.result?.verdict || data.status || 'completed';
    setStatus(`Test ${verdict}`, false);
    const live = el('dx-stress-live');
    if (live) {
      live.innerHTML = `<div class="dx-stress-result"><strong>Done — ${esc(String(verdict))}</strong>
        <pre class="dx-hwref__raw muted fs-xs">${esc(JSON.stringify(data.stress || data.result || data, null, 2).slice(0, 4000))}</pre>
        <p class="muted fs-sm">Issuing certificate for shop handoff…</p></div>`;
    }
    issueCertificate(data);
  }

  async function stopStress() {
    clearInterval(pollTimer);
    pollTimer = null;
    running = false;
    updateRunLabel();
    el('dx-stress-stop') && (el('dx-stress-stop').hidden = true);
    setProgress(0);
    setStatus('Stopped by user', false);
    try {
      if (window.PcLabProbeAuth) await window.PcLabProbeAuth.ensure();
      await fetch(AGENT() + '/suite/cancel', {
        method: 'POST',
        mode: 'cors',
        headers: (window.PcLabProbeAuth && window.PcLabProbeAuth.jsonHeaders()) || {
          'Content-Type': 'application/json',
        },
        body: '{}',
      });
    } catch (_) {}
  }

  function setPresetMinutes(mins) {
    const m = Math.max(0, Number(mins) || 0);
    if (el('dx-stress-hours')) el('dx-stress-hours').value = String(Math.floor(m / 60));
    if (el('dx-stress-minutes')) el('dx-stress-minutes').value = String(m % 60);
    document.querySelectorAll('.dx-test-preset').forEach((b) => {
      b.classList.toggle('is-active', Number(b.getAttribute('data-minutes')) === m);
    });
    updateRunLabel();
  }

  function bind() {
    el('dx-stress-run')?.addEventListener('click', startStress);
    el('dx-stress-stop')?.addEventListener('click', stopStress);
    document.querySelectorAll('input[name="dx-test-target"]').forEach((cb) => {
      cb.addEventListener('change', updateRunLabel);
    });
    el('dx-stress-oracle')?.addEventListener('change', () => {
      const on = !!el('dx-stress-oracle')?.checked;
      document.querySelectorAll('input[name="dx-test-target"]').forEach((cb) => {
        cb.disabled = on;
      });
      if (el('dx-stress-gpu-mode')) el('dx-stress-gpu-mode').disabled = on;
      updateRunLabel();
    });
    el('dx-stress-gpu-mode')?.addEventListener('change', updateRunLabel);
    el('dx-stress-hours')?.addEventListener('input', updateRunLabel);
    el('dx-stress-minutes')?.addEventListener('input', updateRunLabel);
    document.querySelectorAll('.dx-test-preset').forEach((btn) => {
      btn.addEventListener('click', () => setPresetMinutes(btn.getAttribute('data-minutes')));
    });
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'stress') {
        applyPreselect();
        updateRunLabel();
      }
    });
    window.addEventListener('dx:suite-complete', (ev) => {
      if (window.PcLabOpenBook?.applySuiteCert) {
        window.PcLabOpenBook.applySuiteCert(ev.detail);
      }
    });
    updateRunLabel();
  }

  window.PcLabStress = { start: startStress, stop: stopStress, durationSeconds, updateRunLabel };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
