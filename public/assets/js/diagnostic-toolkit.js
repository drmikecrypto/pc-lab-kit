(function () {
  const cfg = window.PCLAB_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  let catalog = null;
  let filter = 'all';
  let probeOk = false;
  let overlayTimer = null;

  const el = (id) => document.getElementById(id);

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  async function probeHealth() {
    try {
      const res = await fetch(AGENT + '/health');
      probeOk = res.ok;
    } catch (_) {
      probeOk = false;
    }
    const st = el('dx-toolkit-run-status');
    if (st) {
      st.textContent = probeOk
        ? 'Probe connected — run a benchmark here, or open the Stress tab for soaks.'
        : 'Start PcLab Probe (bundled in the desktop app) for native benchmarks.';
    }
    document.querySelectorAll('.dx-toolkit-run-btn').forEach((btn) => {
      btn.disabled = !probeOk || btn.dataset.busy === '1';
    });
  }

  async function loadCatalog() {
    try {
      const res = await fetch('/api/diagnostic/toolkit');
      if (!res.ok) return;
      catalog = await res.json();
      renderCatalog(catalog);
      renderRunButtons(catalog.runnable || {});
    } catch (_) {}
  }

  function renderSummary(summary) {
    const head = el('dx-toolkit-headline');
    if (head && summary?.headline) head.textContent = summary.headline;

    const stats = el('dx-toolkit-stats');
    if (!stats || !summary?.coverage) return;
    const labels = { live: 'Live', beta: 'Beta native', import: 'Import', orchestrate: 'Orchestrate', planned: 'Roadmap' };
    stats.innerHTML = Object.entries(summary.coverage)
      .filter(([, n]) => n > 0)
      .map(([k, n]) => `<span class="dx-toolkit-stat dx-toolkit-stat--${k}">${labels[k] || k}: ${n}</span>`)
      .join('');
  }

  function renderFilters(categories) {
    const wrap = el('dx-toolkit-filters');
    if (!wrap) return;
    const buttons = [{ id: 'all', label: 'All' }];
    Object.entries(categories || {}).forEach(([id, label]) => buttons.push({ id, label }));
    wrap.innerHTML = buttons.map((b) =>
      `<button type="button" class="dx-toolkit-filter${filter === b.id ? ' is-active' : ''}" data-filter="${esc(b.id)}">${esc(b.label)}</button>`
    ).join('');
    wrap.querySelectorAll('.dx-toolkit-filter').forEach((btn) => {
      btn.addEventListener('click', () => {
        filter = btn.getAttribute('data-filter') || 'all';
        renderFilters(categories);
        renderGrid(catalog?.tools || []);
      });
    });
  }

  function renderGrid(tools) {
    const grid = el('dx-toolkit-grid');
    if (!grid) return;
    const list = (tools || []).filter((t) => filter === 'all' || t.category === filter);
    grid.innerHTML = list.map((t) => {
      const cov = t.coverage || 'planned';
      return `<article class="dx-toolkit-card">
        <div class="dx-toolkit-card-head">
          <strong>${esc(t.name)}</strong>
          <span class="dx-toolkit-badge dx-toolkit-badge--${esc(cov)}">${esc(cov)}</span>
        </div>
        <p>${esc(t.coverage_note || '')}</p>
      </article>`;
    }).join('');
  }

  function renderCatalog(data) {
    renderSummary(data.summary || {});
    renderFilters(data.categories || {});
    renderGrid(data.tools || []);
  }

  function renderRunButtons(runnable) {
    const wrap = el('dx-toolkit-run');
    if (!wrap) return;
    const items = [];
    (runnable.bench || []).forEach((b) => {
      items.push({ kind: 'bench', id: b.id, label: b.label, desc: b.desc, seconds: 8 });
    });
    const stressHint = (runnable.stress || []).length
      ? `<p class="muted fs-sm mt-2">Stress profiles (CPU/GPU/memory/combined/oracle) and custom duration live in the
          <button type="button" class="dx-btn ghost" data-dx-goto="stress">Stress</button> tab.</p>`
      : '';
    wrap.innerHTML = items.map((item) =>
      `<button type="button" class="dx-toolkit-run-btn" data-kind="${esc(item.kind)}" data-id="${esc(item.id)}" data-seconds="${item.seconds || 15}" disabled>
        <strong>${esc(item.label)}</strong>
        <span>${esc(item.desc)}</span>
      </button>`
    ).join('') + stressHint + `<div id="dx-toolkit-overlay" class="dx-toolkit-overlay muted fs-sm mt-2" hidden></div>
      <div id="dx-toolkit-cert" class="dx-toolkit-cert mt-2" hidden></div>`;
    wrap.querySelectorAll('.dx-toolkit-run-btn').forEach((btn) => {
      btn.addEventListener('click', () => runTest(btn));
    });
    probeHealth();
  }

  function startOverlay(label) {
    const ov = el('dx-toolkit-overlay');
    if (!ov) return;
    ov.hidden = false;
    ov.textContent = `Live overlay: ${label} — sampling Probe telemetry…`;
    if (overlayTimer) clearInterval(overlayTimer);
    overlayTimer = setInterval(async () => {
      try {
        const res = await fetch(AGENT + '/telemetry', { mode: 'cors' });
        if (!res.ok) return;
        const t = await res.json();
        const cpu = t.cpu_temp ?? t.sensors?.cpu_temp_max ?? t.thermal?.cpu ?? '—';
        const gpu = t.gpu_temp ?? t.sensors?.gpu_temp_max ?? t.thermal?.gpu ?? '—';
        ov.textContent = `Live overlay · CPU ${cpu}°C · GPU ${gpu}°C · ${label}`;
      } catch (_) {}
    }, 1500);
  }

  function stopOverlay() {
    if (overlayTimer) {
      clearInterval(overlayTimer);
      overlayTimer = null;
    }
  }

  function renderCertificate(cert) {
    const box = el('dx-toolkit-cert');
    if (!box || !cert) return;
    box.hidden = false;
    const tone = cert.passed ? 'ok' : 'fail';
    box.innerHTML = `<div class="dx-cert dx-cert--${tone}">
      <strong>${esc(cert.verdict || '')}</strong>
      <p class="m-0 mt-1">${esc(cert.summary || '')}</p>
      ${cert.peaks ? `<p class="muted fs-xs m-0 mt-1">Peaks: ${esc(JSON.stringify(cert.peaks))}</p>` : ''}
    </div>`;
  }

  async function issueCertificate(run) {
    try {
      const res = await fetch('/api/diagnostic/stress/certificate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ run, samples: run.samples || [] }),
      });
      const data = await res.json();
      renderCertificate(data.certificate);
      return data.certificate;
    } catch (_) {
      return null;
    }
  }

  function prettyResult(kind, data, cert) {
    if (kind === 'bench') {
      const lines = [
        `${data.label || data.id || 'Benchmark'}`,
        data.score != null ? `Score: ${data.score} ${data.unit || ''}`.trim() : null,
        data.method ? `Method: ${data.method}` : null,
        data.seq_read_mbps != null ? `Seq read: ${data.seq_read_mbps} MB/s` : null,
        data.seq_write_mbps != null ? `Seq write: ${data.seq_write_mbps} MB/s` : null,
        data.rand_4k_read_mbps != null ? `4K read: ${data.rand_4k_read_mbps} MB/s` : null,
        data.note || null,
      ].filter(Boolean);
      return lines.join('\n');
    }
    const lines = [
      `${data.label || data.id || 'Stress'} — ${data.status || ''}`,
      data.duration_s != null ? `Duration: ${data.duration_s}s` : null,
      data.cpu_temp_max != null ? `CPU peak: ${data.cpu_temp_max}°C` : null,
      data.gpu_temp_max != null ? `GPU peak: ${data.gpu_temp_max}°C` : null,
      cert ? `Certificate: ${cert.verdict} — ${cert.summary}` : null,
    ].filter(Boolean);
    return lines.join('\n') + '\n\n' + JSON.stringify(data, null, 2);
  }

  async function runTest(btn) {
    if (!probeOk) return;
    const kind = btn.getAttribute('data-kind');
    const id = btn.getAttribute('data-id');
    const seconds = parseInt(btn.getAttribute('data-seconds') || '15', 10);
    const out = el('dx-toolkit-result');
    const st = el('dx-toolkit-run-status');
    const certBox = el('dx-toolkit-cert');
    if (certBox) { certBox.hidden = true; certBox.innerHTML = ''; }
    btn.dataset.busy = '1';
    btn.disabled = true;
    if (st) st.textContent = 'Running ' + btn.querySelector('strong')?.textContent + '…';
    if (out) { out.hidden = false; out.textContent = 'Working…'; }
    startOverlay(btn.querySelector('strong')?.textContent || id);
    try {
      const path = kind === 'stress' ? '/stress/run' : '/bench/run';
      const body = kind === 'stress'
        ? { id, seconds, collect_samples: true }
        : { id, seconds };
      const res = await fetch(AGENT + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      let cert = null;
      if (kind === 'stress') {
        cert = await issueCertificate(data);
      }
      if (out) out.textContent = prettyResult(kind, data, cert);
      if (st) st.textContent = cert
        ? `Completed — ${cert.verdict}`
        : 'Completed — result below.';
    } catch (e) {
      if (out) out.textContent = String(e);
      if (st) st.textContent = 'Run failed — is Probe running?';
    } finally {
      stopOverlay();
      const ov = el('dx-toolkit-overlay');
      if (ov) ov.hidden = true;
      btn.dataset.busy = '0';
      btn.disabled = !probeOk;
    }
  }

  loadCatalog();
  setInterval(probeHealth, 12000);
})();
