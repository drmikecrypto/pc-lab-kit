/**
 * Stress tab — custom duration (minutes/hours) + certificate strip.
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

  function durationSeconds() {
    const hours = Math.max(0, Math.min(24, Number(el('dx-stress-hours')?.value || 0)));
    const minutes = Math.max(0, Math.min(1440, Number(el('dx-stress-minutes')?.value || 0)));
    let sec = Math.round(hours * 3600 + minutes * 60);
    if (sec < 5) sec = 5;
    if (sec > MAX_SECONDS) sec = MAX_SECONDS;
    return sec;
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

  async function startStress() {
    if (running) return;
    const profile = el('dx-stress-profile')?.value || 'combined';
    const seconds = durationSeconds();
    if (seconds > 1800) {
      const mins = Math.round(seconds / 60);
      if (!window.confirm(`Run ${profile} stress for ${mins} minutes (${(seconds / 3600).toFixed(2)} h)? Long soaks heat the system — stay nearby.`)) {
        return;
      }
    }

    running = true;
    finished = false;
    el('dx-stress-run') && (el('dx-stress-run').disabled = true);
    const stop = el('dx-stress-stop');
    if (stop) stop.hidden = false;
    setProgress(3);
    setStatus(`Starting ${profile} for ${seconds}s…`, false);

    try {
      const health = await fetch(AGENT() + '/health', { mode: 'cors' });
      if (!health.ok) throw new Error('Probe offline');

      const path = profile === 'oracle' ? '/stress/oracle/start' : '/stress/run';
      const body = profile === 'oracle'
        ? { seconds, collect_samples: true }
        : { id: profile, seconds, percent: 100, collect_samples: true };

      const res = await fetch(AGENT() + path, {
        method: 'POST',
        mode: 'cors',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data.ok === false) {
        throw new Error(data.error || data.message || `HTTP ${res.status}`);
      }

      setStatus(`Running ${profile} · ${seconds}s`, false);
      window.dispatchEvent(new CustomEvent('dx:suite-stress-start'));

      // Many probe stress endpoints are synchronous for short runs; for long runs poll thermal.
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
              `Running ${profile} · ${Math.floor(elapsed)}/${seconds}s` +
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

      // If response already includes a finished stress payload, finish immediately.
      if (data.stress || data.result || data.verdict || data.status === 'completed') {
        clearInterval(pollTimer);
        pollTimer = null;
        finishOk(data);
      }
    } catch (e) {
      running = false;
      el('dx-stress-run') && (el('dx-stress-run').disabled = false);
      el('dx-stress-stop') && (el('dx-stress-stop').hidden = true);
      setProgress(0);
      setStatus('Stress failed: ' + (e.message || e), true);
    }
  }

  function finishOk(data) {
    if (finished) return;
    finished = true;
    clearInterval(pollTimer);
    pollTimer = null;
    running = false;
    el('dx-stress-run') && (el('dx-stress-run').disabled = false);
    el('dx-stress-stop') && (el('dx-stress-stop').hidden = true);
    setProgress(100);
    const verdict = data.verdict || data.stress?.verdict || data.result?.verdict || 'completed';
    setStatus(`Stress ${verdict}`, false);
    const live = el('dx-stress-live');
    if (live) {
      live.innerHTML = `<div class="dx-stress-result"><strong>Done — ${esc(String(verdict))}</strong>
        <pre class="dx-hwref__raw muted fs-xs">${esc(JSON.stringify(data.stress || data.result || data, null, 2).slice(0, 4000))}</pre>
        <p class="muted fs-sm">Export a full Assembly Certificate from Command Center Full Lab, or keep soaking with a longer custom duration.</p></div>`;
    }
  }

  async function stopStress() {
    clearInterval(pollTimer);
    pollTimer = null;
    running = false;
    el('dx-stress-run') && (el('dx-stress-run').disabled = false);
    el('dx-stress-stop') && (el('dx-stress-stop').hidden = true);
    setProgress(0);
    setStatus('Stopped by user', false);
    try {
      await fetch(AGENT() + '/suite/cancel', { method: 'POST', mode: 'cors' });
    } catch (_) {}
  }

  function bind() {
    el('dx-stress-run')?.addEventListener('click', startStress);
    el('dx-stress-stop')?.addEventListener('click', stopStress);
    document.addEventListener('click', (ev) => {
      const t = ev.target;
      if (t instanceof Element && t.closest('[data-dx-goto="stress"]')) {
        if (window.dxActivateTab) window.dxActivateTab('stress');
      }
    });
    window.addEventListener('dx:suite-complete', (ev) => {
      if (window.PcLabOpenBook?.applySuiteCert) {
        window.PcLabOpenBook.applySuiteCert(ev.detail);
      }
    });
  }

  window.PcLabStress = { start: startStress, stop: stopStress, durationSeconds };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
