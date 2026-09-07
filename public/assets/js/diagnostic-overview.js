/**
 * Overview — Probe instrument + detected hardware (detect → decide).
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

  function setProbeUi(state, label, detail) {
    const dot = el('dx-overview-probe-dot');
    const lab = el('dx-overview-probe-label');
    const det = el('dx-overview-probe-detail');
    if (dot) dot.setAttribute('data-state', state || 'unknown');
    if (lab) lab.textContent = label || 'Probe';
    if (det) det.textContent = detail || '';
  }

  function renderTrustBanner(data) {
    const slot = el('dx-overview-trust');
    if (!slot) return;
    const trust = data.sensor_trust || {};
    const competing = trust.competing_tools || [];
    const parts = [];
    if (competing.length) {
      parts.push(
        `<div class="dx-trust-banner is-warn" role="status">
          <strong>Sensor conflict</strong>
          <p class="muted fs-sm">${esc(trust.message || `Close ${competing.join(', ')} or expect wrong temps (shared Ring0 / SMBus).`)}</p>
        </div>`
      );
    } else if (data.elevated === false) {
      parts.push(
        `<div class="dx-trust-banner is-info" role="status">
          <strong>Sensors-only / limited</strong>
          <p class="muted fs-sm">Probe is not elevated — die/board sensors limited. Restart via Start-PcLabProbe.bat for full Open Book coverage.</p>
        </div>`
      );
    }
    const mode = data.service_mode
      ? 'Windows Service (always-on)'
      : 'Tray / desktop sidecar';
    const backend = trust.backend || (data.hwmon ? 'pclab_hwmon_lhm' : 'os_counters');
    parts.push(
      `<p class="muted fs-xs dx-trust-meta">Sensor path: <code>${esc(backend)}</code> · ${esc(mode)} · WinRing0 not shipped${
        trust.operator_story ? ` · ${esc(trust.operator_story)}` : ''
      }</p>`
    );
    slot.innerHTML = parts.join('');
  }

  function renderCertHandoff() {
    const slot = el('dx-overview-cert-handoff');
    if (!slot) return;
    let last = null;
    try {
      last = JSON.parse(sessionStorage.getItem('pclab_last_stress_cert') || 'null');
    } catch (_) {}
    if (!last || !last.verdict) {
      slot.innerHTML = `<p class="muted fs-sm">After a Test finishes, export Assembly / Stress certificate here for shop handoff.</p>`;
      return;
    }
    slot.innerHTML = `<div class="dx-overview-cert-card">
      <strong>Last stress: ${esc(String(last.verdict))}</strong>
      <p class="muted fs-xs">${esc(last.summary || last.id || '')}</p>
      <div class="dx-overview-cert-actions">
        <button type="button" class="dx-btn primary" id="dx-overview-open-cert">Open certificate</button>
        <button type="button" class="dx-btn ghost" data-dx-goto="stress">Back to Test</button>
      </div>
    </div>`;
    el('dx-overview-open-cert')?.addEventListener('click', () => {
      if (last.html) {
        const w = window.open('', '_blank');
        if (w) {
          w.document.write(last.html);
          w.document.close();
        }
      } else {
        location.hash = 'dx-stress-lab';
        window.dispatchEvent(new CustomEvent('dx:tab-change', { detail: { tab: 'stress' } }));
      }
    });
  }

  async function checkProbe() {
    setProbeUi('unknown', 'Probe', 'Checking local Probe…');
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 4000);
      const res = await fetch(AGENT() + '/health', { mode: 'cors', signal: ctrl.signal });
      clearTimeout(timer);
      if (!res.ok) {
        setProbeUi('offline', 'Probe offline', `Health returned HTTP ${res.status}. Open the desktop app, then Recheck.`);
        renderTrustBanner({});
        return false;
      }
      const data = await res.json().catch(() => ({}));
      window.__dxLastHealth = data;
      const platform = data.platform || data.os || 'local';
      const elev = data.elevated ? 'elevated' : 'user';
      const svc = data.service_mode ? ' · service' : '';
      let dens = '';
      if (String(platform).toLowerCase() === 'linux' && data.sensor_density) {
        const d = data.sensor_density;
        dens = ` · ${d.temp_channels || 0}T/${d.fan_channels || 0}F/${d.voltage_channels || 0}V/${d.power_channels || 0}W`;
      }
      setProbeUi('online', 'Probe online', `${platform} · ${elev}${svc}${dens} · ${AGENT().replace(/^https?:\/\//, '')}`);
      renderTrustBanner(data);
      return true;
    } catch (_) {
      setProbeUi(
        'offline',
        'Probe offline',
        'Not reachable on this PC. Open PC Lab Kit desktop so the bundled probe starts, then Recheck.'
      );
      renderTrustBanner({});
      return false;
    }
  }

  function pickName(obj, keys) {
    if (!obj || typeof obj !== 'object') return '';
    for (const k of keys) {
      const v = obj[k];
      if (v != null && String(v).trim()) return String(v).trim();
    }
    return '';
  }

  function summarize(devices, drivers) {
    const cpu =
      pickName(devices?.cpu, ['name', 'model', 'brand_string']) ||
      pickName(devices?.processors?.[0], ['name', 'model']) ||
      'CPU';
    const gpu =
      pickName(devices?.gpu, ['name', 'model', 'adapter']) ||
      pickName(devices?.gpus?.[0], ['name', 'model']) ||
      pickName((devices?.display_adapters || [])[0], ['name', 'description']) ||
      'GPU';
    const ram =
      pickName(devices?.memory, ['summary', 'total', 'size']) ||
      (devices?.memory_gb != null ? `${devices.memory_gb} GB` : '') ||
      pickName(devices?.ram, ['summary', 'total']) ||
      'Memory';
    const storage =
      pickName((devices?.storage || devices?.disks || [])[0], ['name', 'model', 'caption']) ||
      (Array.isArray(devices?.storage) ? `${devices.storage.length} drive(s)` : '') ||
      'Storage';

    const plan = drivers?.action_plan?.items || [];
    const actions = (drivers?.actions || []).filter((a) => a && (a.severity === 'critical' || a.severity === 'warn'));
    const driverless = (devices?.driverless || devices?.problem || []).length;
    const problems = (devices?.problem_devices || devices?.problems || []).length;
    const driverIssues = plan.length || actions.length || driverless || problems;

    return [
      { id: 'cpu', label: 'CPU', value: cpu, testTarget: 'cpu' },
      { id: 'gpu', label: 'GPU', value: gpu, testTarget: 'gpu' },
      { id: 'memory', label: 'Memory', value: ram, testTarget: 'memory' },
      { id: 'storage', label: 'Storage', value: storage, testTarget: null },
      {
        id: 'drivers',
        label: 'Drivers',
        value: driverIssues ? `${driverIssues} need attention` : 'All clear',
        warn: !!driverIssues,
        testTarget: null,
        driversOnly: true,
      },
    ];
  }

  function renderGrid(rows) {
    const grid = el('dx-overview-grid');
    if (!grid) return;
    grid.innerHTML = rows
      .map((r) => {
        const actions = [];
        if (r.driversOnly || r.id === 'drivers') {
          actions.push(`<button type="button" class="dx-btn ghost" data-dx-goto="drivers">Drivers</button>`);
        } else {
          actions.push(`<button type="button" class="dx-btn ghost" data-dx-goto="drivers">Drivers</button>`);
          if (r.testTarget) {
            actions.push(
              `<button type="button" class="dx-btn ghost" data-dx-goto="stress" data-dx-test-target="${esc(r.testTarget)}">Test this</button>`
            );
          }
        }
        return `<article class="dx-overview-card${r.warn ? ' is-warn' : ''}">
          <span class="dx-overview-card__label">${esc(r.label)}</span>
          <strong class="dx-overview-card__value">${esc(r.value)}</strong>
          <div class="dx-overview-card__actions">${actions.join('')}</div>
        </article>`;
      })
      .join('');
  }

  async function refreshInventory() {
    const grid = el('dx-overview-grid');
    if (grid) grid.innerHTML = `<p class="muted fs-sm">Scanning inventory…</p>`;
    const online = await checkProbe();
    renderCertHandoff();
    if (!online) {
      if (grid) {
        grid.innerHTML = `<div class="dx-panel-empty">
          <strong>Cannot detect hardware</strong>
          <p class="muted fs-sm">Probe is offline. Open the desktop app, then Rescan.</p>
        </div>`;
      }
      return;
    }
    try {
      const [devRes, drvRes] = await Promise.all([
        fetch(AGENT() + '/devices', { mode: 'cors' }),
        fetch(AGENT() + '/drivers', { mode: 'cors' }),
      ]);
      const devices = devRes.ok ? await devRes.json() : {};
      const drvWrap = drvRes.ok ? await drvRes.json() : {};
      const drivers = drvWrap.drivers || drvWrap;
      window.__dxLastDevices = devices;
      window.__dxLastDrivers = drivers;
      renderGrid(summarize(devices, drivers));
    } catch (e) {
      if (grid) {
        grid.innerHTML = `<div class="dx-panel-empty is-error">
          <strong>Inventory failed</strong>
          <p class="muted fs-sm">${esc(e.message || e)}</p>
        </div>`;
      }
    }
  }

  function bind() {
    el('dx-overview-probe-retry')?.addEventListener('click', () => {
      checkProbe().then((ok) => {
        if (ok) refreshInventory();
      });
    });
    el('dx-overview-refresh')?.addEventListener('click', refreshInventory);
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'command') refreshInventory();
    });
    window.addEventListener('dx:stress-cert', () => renderCertHandoff());
    refreshInventory();
  }

  window.PcLabOverview = { refresh: refreshInventory, checkProbe };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
