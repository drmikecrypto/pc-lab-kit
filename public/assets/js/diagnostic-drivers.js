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
    if (status && text) status.textContent = isError ? 'Offline' : 'Ready';
  }

  function setHeading(count) {
    const h = el('dx-drivers-heading');
    const lead = el('dx-drivers-lead');
    if (count == null) return;
    if (h) {
      h.textContent =
        count === 0
          ? 'No driver actions required'
          : count === 1
            ? '1 device needs install or update'
            : `${count} devices need install or update`;
    }
    if (lead) {
      lead.textContent =
        count === 0
          ? 'Rescan after plugging new hardware. Install/Update appears on each problem row when needed.'
          : 'Install/Update on that exact row. Probe must be running (bundled in the desktop app).';
    }
  }

  function offlineEmpty(detail) {
    return `<div class="dx-panel-empty is-error">
      <strong>Probe offline</strong>
      <p class="muted fs-sm">Cannot read drivers. Open the PC Lab Kit desktop app so the bundled probe starts, then Rescan devices.</p>
      ${detail ? `<p class="muted fs-xs">${esc(detail)}</p>` : ''}
    </div>`;
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
    const links = (row.links || [])
      .slice(0, 2)
      .map((l) => `<a href="${esc(l.url)}" target="_blank" rel="noopener">${esc(l.label || 'Download')}</a>`)
      .join(' · ');
    const conf = driverConfBadge(row);
    const ids = hwId(row);
    const primaryBtn = primary
      ? `<a href="${esc(primary.url)}" class="dx-btn ghost dx-driver-primary" target="_blank" rel="noopener">${esc(primary.label || 'Open package')}</a>`
      : '';
    const installBtn = `<button type="button" class="dx-btn primary dx-driver-install" ${installAttrs}>Install driver</button>`;
    return `<article class="dx-driver-card ${esc(severity || '')}">
      <div class="dx-driver-card-head"><strong>${esc(title)}</strong>${conf}</div>
      <p class="muted fs-sm">${esc(detail || '')}</p>
      ${ids ? `<span class="muted fs-xs dx-driver-hwid">${esc(ids)}</span>` : ''}
      <div class="dx-driver-links">${installBtn}${primaryBtn}${links ? ' · ' + links : ''}</div>
    </article>`;
  }

  function countActions(drivers, devices) {
    const plan = drivers.action_plan || {};
    const planItems = Array.isArray(plan.items) ? plan.items : [];
    const actions = (drivers.actions || []).filter(
      (a) => a && (a.severity === 'critical' || a.severity === 'warn' || a.severity === 'info')
    );
    const driverless = devices.driverless || devices.problem || [];
    const problems = (devices.problem_devices || devices.problems || []).filter(Boolean);
    const queue = (drivers.install_queue || []).filter((s) => s && s.status !== 'ok');
    if (planItems.length) return planItems.length;
    return actions.length + driverless.length + problems.length + queue.length;
  }

  function renderDriverActions(drivers, devices) {
    const box = el('dx-driver-actions');
    if (!box) return;
    const plan = drivers.action_plan || {};
    const planItems = Array.isArray(plan.items) ? plan.items : [];
    const actions = (drivers.actions || []).filter(
      (a) => a && (a.severity === 'critical' || a.severity === 'warn' || a.severity === 'info')
    );
    const driverless = devices.driverless || devices.problem || [];
    const problems = (devices.problem_devices || devices.problems || []).filter(Boolean);
    const queue = (drivers.install_queue || []).filter((s) => s && s.status !== 'ok');
    const n = countActions(drivers, devices);
    setHeading(n);

    const missing = [].concat(driverless, problems);
    if (!planItems.length && !actions.length && !missing.length && !queue.length) {
      box.innerHTML = `<div class="dx-panel-empty">
        <strong>All clear</strong>
        <p class="muted fs-sm">Score ${esc(String(drivers.score ?? '—'))} / ${esc(drivers.grade || '—')}. Rescan after plugging new hardware.</p>
      </div>`;
      setNote('No critical driver actions.', false);
      return;
    }

    let planHtml = '';
    if (planItems.length) {
      planHtml = `<div class="dx-driver-action-plan">
        <h3 class="dx-driver-queue-title">Action plan <span class="muted fs-xs">${esc(plan.count ?? planItems.length)} · ${esc(plan.installable_count ?? 0)} installable</span></h3>
        <p class="muted fs-xs">${esc(plan.note || 'Install chipset / ME before GPU.')}</p>
        <ol class="dx-driver-checklist">
          ${planItems
            .map((it, idx) => {
              const conf =
                it.match_confidence_pct != null ? `${it.match_confidence_pct}%` : it.match_confidence || '';
              return `<li class="dx-driver-check ${esc(it.severity || '')}">
              <span class="dx-driver-check__ord">${idx + 1}</span>
              <div>
                <strong>${esc((it.action || 'update').toUpperCase())}</strong> ${esc(it.device || it.title || '')}
                <div class="muted fs-xs">${esc(it.category || '')}${conf ? ' · ' + esc(conf) + ' match' : ''} · ${esc(it.detail || '')}</div>
              </div>
              <button type="button" class="dx-btn primary dx-driver-install"
                data-instance="${esc(it.instance_id || '')}"
                data-category="${esc(it.category || '')}"
                data-queue="">Install driver</button>
            </li>`;
            })
            .join('')}
        </ol>
      </div>`;
    }

    const actionHtml = planItems.length
      ? ''
      : actions
          .map((a) =>
            rowHtml(
              a.title || a.name || 'Driver action',
              a.detail || a.why || '',
              a.severity || 'warn',
              a,
              `data-instance="${esc(a.instance_id || '')}" data-category="${esc(a.category || '')}" data-queue=""`
            )
          )
          .join('');

    const missingHtml = planItems.length
      ? ''
      : missing
          .map((d) =>
            rowHtml(
              `Needs driver: ${d.name || d.title || 'Unknown device'}`,
              d.problem_message || d.category || d.status || '',
              'critical',
              d,
              `data-instance="${esc(d.instance_id || '')}" data-category="${esc(d.category || '')}" data-queue=""`
            )
          )
          .join('');

    const queueHtml = queue.length
      ? `<div class="dx-driver-queue">
      <h3 class="dx-driver-queue-title">Install queue</h3>
      ${queue
        .map((s) =>
          rowHtml(
            s.label || s.id || 'Queued package',
            s.why || s.status || '',
            s.status === 'critical' || s.status === 'action_required' ? 'critical' : 'warn',
            s,
            `data-instance="" data-category="${esc(s.id || '')}" data-queue="${esc(s.id || '')}"`
          )
        )
        .join('')}
    </div>`
      : '';

    box.innerHTML = `<div class="dx-driver-summary muted fs-sm">Score <strong>${esc(String(drivers.score ?? '—'))}</strong> / ${esc(drivers.grade || '—')} — Install runs on that hardware row via bundled Probe.</div>
      ${planHtml}${queueHtml}${missingHtml}${actionHtml}`;

    box.querySelectorAll('.dx-driver-install').forEach((btn) => {
      btn.addEventListener('click', () => installDriver(btn));
    });
    setNote(
      planItems.length
        ? `Ordered action plan: ${planItems.length} device(s). Chipset/ME before GPU.`
        : `${actions.length + missing.length} device action(s) · ${queue.length} queued`,
      false
    );
  }

  async function installDriver(btn) {
    const instanceId = btn.getAttribute('data-instance') || '';
    const category = btn.getAttribute('data-category') || '';
    const queueId = btn.getAttribute('data-queue') || '';
    const label = category || instanceId || 'driver';
    if (
      !window.confirm(
        `Install the matched latest driver for ${label}? This may download a vendor package or open the GPU updater.`
      )
    ) {
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
        setNote(
          `Install ${data.status || 'done'}${data.package_version ? ' · ' + data.package_version : ''}. Rescanning…`,
          false
        );
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
    setNote(includeWu ? 'Scanning Windows Update for drivers (may take several minutes)…' : 'Rescanning devices…', false);
    try {
      const url = includeWu ? `${AGENT()}/drivers?wu=1` : `${AGENT()}/drivers`;
      const res = await fetch(url, { mode: 'cors' });
      if (!res.ok) throw new Error('drivers HTTP ' + res.status);
      const report = await res.json();
      const drivers = report.drivers || report;
      const devices = report.devices || {};
      window.__dxLastDrivers = drivers;
      window.__dxLastDevices = devices;
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
      if (box) box.innerHTML = offlineEmpty(e.message || e);
      setHeading(null);
      const h = el('dx-drivers-heading');
      if (h) h.textContent = 'Drivers unavailable';
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
  }

  window.PcLabDrivers = { rescan: rescanDrivers, render: renderDriverActions };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
