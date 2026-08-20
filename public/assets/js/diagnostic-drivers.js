/**
 * Drivers tab — per-device install/update from Probe /drivers.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';

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

  function setNote(text, isError) {
    const note = el('dx-drivers-note');
    const status = el('dx-drivers-status');
    if (note) {
      note.textContent = text || '';
      note.classList.toggle('is-error', !!isError);
    }
    if (status && text) status.textContent = isError ? 'Error' : 'Ready';
  }

  function driverConfBadge(row) {
    const parts = [];
    const pct = row.match_confidence_pct;
    if (pct != null && pct !== '') parts.push(`${pct}% match`);
    else if (row.match_confidence) parts.push(String(row.match_confidence));
    if (row.success_rate != null && row.success_rate !== '') {
      parts.push(`${Math.round(Number(row.success_rate))}% local success`);
    }
    return parts.length ? `<span class="dx-driver-conf">${esc(parts.join(' · '))}</span>` : '';
  }

  function hwId(a) {
    const bits = [];
    if (a.vendor_id) bits.push('VEN_' + String(a.vendor_id).toUpperCase());
    if (a.device_id) bits.push('DEV_' + String(a.device_id).toUpperCase());
    if (a.instance_id && !bits.length) bits.push(String(a.instance_id).slice(0, 64));
    return bits.length ? bits.join(' · ') : '';
  }

  function rowHtml(title, detail, severity, row, installAttrs) {
    const primary = row.primary_link && row.primary_link.url ? row.primary_link : null;
    const links = (row.links || []).slice(0, 2).map((l) =>
      `<a href="${esc(l.url)}" target="_blank" rel="noopener">${esc(l.label || 'Download')}</a>`
    ).join(' · ');
    const conf = driverConfBadge(row);
    const ids = hwId(row);
    const primaryBtn = primary
      ? `<a href="${esc(primary.url)}" class="dx-btn primary dx-driver-primary" target="_blank" rel="noopener">${esc(primary.label || 'Open package')}</a>`
      : '';
    const installBtn = `<button type="button" class="dx-btn primary dx-driver-install" ${installAttrs}>Install / Update</button>`;
    return `<article class="dx-driver-card ${esc(severity || '')}">
      <div class="dx-driver-card-head"><strong>${esc(title)}</strong>${conf}</div>
      <p class="muted fs-sm">${esc(detail || '')}</p>
      ${ids ? `<span class="muted fs-xs dx-driver-hwid">${esc(ids)}</span>` : ''}
      <div class="dx-driver-links">${installBtn}${primaryBtn}${links ? ' · ' + links : ''}</div>
    </article>`;
  }

  function renderDriverActions(drivers, devices) {
    const box = el('dx-driver-actions');
    if (!box) return;
    const actions = (drivers.actions || []).filter((a) => a && (a.severity === 'critical' || a.severity === 'warn' || a.severity === 'info'));
    const driverless = devices.driverless || devices.problem || [];
    const problems = (devices.problem_devices || devices.problems || []).filter(Boolean);
    const queue = (drivers.install_queue || []).filter((s) => s && s.status !== 'ok');

    const missing = ([]).concat(driverless, problems);
    if (!actions.length && !missing.length && !queue.length) {
      box.innerHTML = `<div class="dx-empty-hint">No driver installs needed right now. Score ${esc(String(drivers.score ?? '—'))} / ${esc(drivers.grade || '—')}. Rescan after plugging new hardware.</div>`;
      setNote('All clear — no critical driver actions.', false);
      return;
    }

    const actionHtml = actions.map((a) => rowHtml(
      a.title || a.name || 'Driver action',
      a.detail || a.why || '',
      a.severity || 'warn',
      a,
      `data-instance="${esc(a.instance_id || '')}" data-category="${esc(a.category || '')}" data-queue=""`
    )).join('');

    const missingHtml = missing.map((d) => rowHtml(
      `Needs driver: ${d.name || d.title || 'Unknown device'}`,
      d.problem_message || d.category || d.status || '',
      'critical',
      d,
      `data-instance="${esc(d.instance_id || '')}" data-category="${esc(d.category || '')}" data-queue=""`
    )).join('');

    const queueHtml = queue.length ? `<div class="dx-driver-queue">
      <h3 class="dx-driver-queue-title">Install queue</h3>
      ${queue.map((s) => rowHtml(
        s.label || s.id || 'Queued package',
        s.why || s.status || '',
        s.status === 'critical' ? 'critical' : 'warn',
        s,
        `data-instance="" data-category="${esc(s.id || '')}" data-queue="${esc(s.id || '')}"`
      )).join('')}
    </div>` : '';

    box.innerHTML = `<div class="dx-driver-summary muted fs-sm">Score <strong>${esc(String(drivers.score ?? '—'))}</strong> / ${esc(drivers.grade || '—')} — Install runs on that hardware row via bundled Probe.</div>
      ${queueHtml}${missingHtml}${actionHtml}`;

    box.querySelectorAll('.dx-driver-install').forEach((btn) => {
      btn.addEventListener('click', () => installDriver(btn));
    });
    setNote(`${actions.length + missing.length} device action(s) · ${queue.length} queued`, false);
  }

  async function installDriver(btn) {
    const instanceId = btn.getAttribute('data-instance') || '';
    const category = btn.getAttribute('data-category') || '';
    const queueId = btn.getAttribute('data-queue') || '';
    const label = category || instanceId || 'driver';
    if (!window.confirm(`Install the matched latest driver for ${label}? This may download a vendor package or open the GPU updater.`)) {
      return;
    }
    btn.disabled = true;
    setNote('Installing driver package…', false);
    try {
      const res = await fetch(`${AGENT()}/drivers/install`, {
        method: 'POST',
        mode: 'cors',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          confirm: true,
          instance_id: instanceId,
          category,
          queue_id: queueId,
        }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data.ok === false) {
        setNote(`Install failed: ${data.error || data.status || res.status}`, true);
      } else {
        setNote(`Install ${data.status || 'done'}${data.package_version ? ' · ' + data.package_version : ''}. Rescanning…`, false);
      }
      await rescanDrivers(false);
    } catch (_) {
      setNote('Install request failed — is the bundled Probe running and elevated?', true);
    } finally {
      btn.disabled = false;
    }
  }

  async function rescanDrivers(includeWu) {
    const status = el('dx-drivers-status');
    if (status) status.textContent = includeWu ? 'WU scan…' : 'Scanning…';
    setNote(includeWu ? 'Scanning Windows Update for drivers (may take several minutes)…' : 'Rescanning drivers…', false);
    try {
      const url = includeWu ? `${AGENT()}/drivers?wu=1` : `${AGENT()}/drivers`;
      const res = await fetch(url, { mode: 'cors' });
      if (!res.ok) throw new Error('drivers HTTP ' + res.status);
      const report = await res.json();
      const drivers = report.drivers || report;
      const devices = report.devices || {};
      if (window.__dxLastProbe) {
        window.__dxLastProbe.drivers = drivers;
        window.__dxLastProbe.devices = devices;
      } else {
        window.__dxLastProbe = { drivers, devices };
      }
      window.dispatchEvent(new CustomEvent('dx:drivers-updated', { detail: { drivers, devices } }));
      renderDriverActions(drivers, devices);
      if (status) status.textContent = 'Ready';
    } catch (e) {
      const box = el('dx-driver-actions');
      if (box) {
        box.innerHTML = `<div class="dx-empty-hint is-error">Could not reach Probe /drivers. ${esc(e.message || e)}</div>`;
      }
      setNote('Probe offline — open the desktop app so the bundled probe starts.', true);
      if (status) status.textContent = 'Offline';
    }
  }

  function bind() {
    el('dx-drivers-rescan')?.addEventListener('click', () => rescanDrivers(false));
    el('dx-drivers-wu')?.addEventListener('click', () => rescanDrivers(true));
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'drivers') rescanDrivers(false);
    });
    window.addEventListener('dx:drivers-updated', (ev) => {
      if (ev.detail?.drivers) renderDriverActions(ev.detail.drivers, ev.detail.devices || {});
    });
    document.addEventListener('click', (ev) => {
      const t = ev.target;
      if (t instanceof Element && t.closest('[data-dx-goto="drivers"]')) {
        if (window.dxActivateTab) window.dxActivateTab('drivers');
      }
    });
  }

  window.PcLabDrivers = { rescan: rescanDrivers, render: renderDriverActions };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
