/**
 * Hardware Reference tab — full PnP inventory with confidence fields + topology.
 */
(function () {
  const AGENT = (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  let lastInventory = null;
  let lastDevicesRaw = null;
  let selectedId = null;

  function esc(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function el(id) {
    return document.getElementById(id);
  }

  function setStatus(msg, ok) {
    const s = el('dx-hwref-status');
    if (!s) return;
    s.textContent = msg;
    s.classList.toggle('ok', !!ok);
    s.classList.toggle('warn', !ok);
  }

  function activeFilters() {
    const out = { present: true, hidden: true, problem: true, driverless: true };
    document.querySelectorAll('#dx-hwref-filters [data-hw-filter]').forEach((cb) => {
      out[cb.getAttribute('data-hw-filter')] = cb.checked;
    });
    return out;
  }

  function matchesFilters(d, f, q) {
    const present = d.present !== false;
    const hidden = !!d.hidden || !present;
    const problem = !!d.has_problem || (d.problem_code && d.problem_code !== 22);
    const driverless = !!d.needs_driver;
    if (present && !f.present) return false;
    if (hidden && !f.hidden && !present) return false;
    if (!present && !f.hidden) return false;
    if (problem && !f.problem && !driverless) return false;
    if (driverless && !f.driverless) return false;
    if (!q) return true;
    const hay = [
      d.name, d.vendor_id, d.device_id, d.instance_id, d.category, d.bus, d.manufacturer, d.vendor_name,
    ].join(' ').toLowerCase();
    return hay.includes(q);
  }

  function renderTree() {
    const root = el('dx-hwref-tree');
    if (!root || !lastInventory) return;
    const f = activeFilters();
    const q = (el('dx-hwref-search')?.value || '').trim().toLowerCase();
    const devices = (lastInventory.all_devices || []).filter((d) => matchesFilters(d, f, q));
    const byBus = {};
    devices.forEach((d) => {
      const bus = d.bus || 'other';
      if (!byBus[bus]) byBus[bus] = [];
      byBus[bus].push(d);
    });
    const sum = lastInventory.summary || {};
    const fp = lastInventory.fingerprint || lastDevicesRaw?.fingerprint || {};
    const cov = sum.coverage_score ?? fp.coverage_score;
    const gaps = Array.isArray(fp.gaps) ? fp.gaps : [];
    let html = `<div class="dx-hwref__summary muted fs-xs">
      ${esc(sum.total_devices ?? devices.length)} total ·
      ${esc(sum.present_devices ?? '—')} present ·
      ${esc(sum.hidden_devices ?? '—')} hidden ·
      ${esc(sum.driverless ?? '—')} driverless ·
      ${esc(sum.problem_devices ?? '—')} problem
      ${cov != null ? ` · <strong>coverage ${esc(cov)}%</strong>` : ''}
      ${sum.form_factor || fp.form_factor ? ` · ${esc(sum.form_factor || fp.form_factor)}` : ''}
    </div>`;
    if (cov != null) {
      html += `<div class="dx-platform-coverage">
        <div class="dx-platform-coverage__bar" role="meter" aria-valuenow="${esc(cov)}" aria-valuemin="0" aria-valuemax="100">
          <span style="width:${esc(Math.min(100, Math.max(0, Number(cov))))}%"></span>
        </div>
        ${gaps.length ? `<ul class="dx-platform-coverage__gaps muted fs-xs">${gaps.slice(0, 5).map((g) => `<li><code>${esc(g.plane || '')}</code> — ${esc(g.detail || g.reason || '')}</li>`).join('')}</ul>` : ''}
      </div>`;
    }
    Object.keys(byBus).sort().forEach((bus) => {
      html += `<details class="dx-hwref__bus" open><summary>${esc(bus)} <span class="muted">(${byBus[bus].length})</span></summary><ul class="dx-hwref__list">`;
      byBus[bus].forEach((d) => {
        const flags = [];
        if (d.hidden || d.present === false) flags.push('hidden');
        if (d.needs_driver) flags.push('driverless');
        if (d.has_problem) flags.push('problem');
        const active = d.instance_id === selectedId ? ' is-active' : '';
        html += `<li class="dx-hwref__item${active}" data-instance="${esc(d.instance_id)}">
          <button type="button" class="dx-hwref__item-btn">
            <strong>${esc(d.name)}</strong>
            <span class="muted fs-xs">${esc(d.category)} · ${esc(d.status)}${flags.length ? ' · ' + flags.join(', ') : ''}</span>
            <span class="dx-hwref__conf">${esc(d.confidence || 'measured')}</span>
          </button>
        </li>`;
      });
      html += '</ul></details>';
    });
    root.innerHTML = html || '<p class="muted">No devices match filters.</p>';
    root.querySelectorAll('.dx-hwref__item').forEach((li) => {
      li.addEventListener('click', () => {
        selectedId = li.getAttribute('data-instance');
        const d = (lastInventory.all_devices || []).find((x) => x.instance_id === selectedId);
        renderDetail(d);
        renderTree();
      });
    });
  }

  function renderFieldTable(fields) {
    if (!fields || typeof fields !== 'object') return '';
    const rows = Object.keys(fields).map((k) => {
      const f = fields[k] || {};
      const val = f.value !== undefined ? f.value : f;
      let display = val;
      if (val && typeof val === 'object') display = JSON.stringify(val);
      return `<tr><th>${esc(k)}</th><td>${esc(display)}</td><td class="dx-hwref__conf">${esc(f.confidence || '')}</td><td class="muted fs-xs">${esc(f.source || '')}</td></tr>`;
    }).join('');
    return `<table class="dx-hwref__fields"><thead><tr><th>Field</th><th>Value</th><th>Confidence</th><th>Source</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  function renderDetail(d) {
    const box = el('dx-hwref-detail');
    if (!box) return;
    if (!d) {
      box.innerHTML = '<p class="muted fs-sm">Select a device for every field.</p>';
      return;
    }
    const ids = [];
    if (d.vendor_id) ids.push('VEN_' + String(d.vendor_id).toUpperCase());
    if (d.device_id) ids.push('DEV_' + String(d.device_id).toUpperCase());
    box.innerHTML = `
      <h3>${esc(d.name)}</h3>
      <p class="muted fs-xs">${esc(ids.join(' · '))}</p>
      <p class="fs-sm">${esc(d.problem_message || d.status || '')}</p>
      <dl class="dx-hwref__dl">
        <dt>Instance</dt><dd><code>${esc(d.instance_id)}</code></dd>
        <dt>Bus / class</dt><dd>${esc(d.bus)} / ${esc(d.class)}</dd>
        <dt>Parent</dt><dd><code>${esc(d.parent_instance_id || '—')}</code></dd>
        <dt>Present</dt><dd>${d.present === false ? 'no' : 'yes'} ${d.hidden ? '(hidden)' : ''} ${d.ghost ? '(ghost)' : ''}</dd>
        <dt>Service</dt><dd>${esc(d.service || '—')}</dd>
      </dl>
      ${renderFieldTable(d.fields)}
      <pre class="dx-hwref__raw muted fs-xs">${esc(JSON.stringify(d, null, 2).slice(0, 8000))}</pre>`;
  }

  async function loadTopology(probeBundle) {
    const topoRoot = el('dx-hwref-topology');
    const adv = el('dx-advanced-topo-svg');
    const adv3d = el('dx-advanced-topo-3d');
    try {
      const res = await fetch('/api/diagnostic/topology', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ probe: probeBundle }),
      });
      const data = await res.json();
      if (data.ok && window.PcLabTopology) {
        if (topoRoot) window.PcLabTopology.render(topoRoot, data.topology);
        if (adv) window.PcLabTopology.render(adv, data.topology);
      }
      if (data.ok && adv3d && window.PcLabTopology3d?.render && data.topology_3d && !adv3d.hidden) {
        window.PcLabTopology3d.render(adv3d, data);
      }
    } catch (_) {}
  }

  function bindTopo3dToggle() {
    const btn = el('dx-topo-3d-toggle');
    const svg = el('dx-advanced-topo-svg');
    const box = el('dx-advanced-topo-3d');
    if (!btn || !svg || !box) return;
    btn.addEventListener('click', async () => {
      const on = box.hidden;
      box.hidden = !on;
      svg.hidden = on;
      btn.setAttribute('aria-pressed', on ? 'true' : 'false');
      if (on && window.PcLabTopology3d?.render) {
        box.innerHTML = '<p class="muted">Building 3D topology…</p>';
        try {
          const res = await fetch('/api/diagnostic/topology', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ probe: { devices: lastDevicesRaw, probe_version: 2, agent: 'pclab-probe' } }),
          });
          const data = await res.json();
          if (data.topology_3d) {
            box.innerHTML = '';
            window.PcLabTopology3d.render(box, data);
          } else {
            box.innerHTML = '<p class="muted fs-sm">3D topology unavailable.</p>';
          }
        } catch (e) {
          box.innerHTML = `<p class="muted">3D failed: ${esc(e.message || e)}</p>`;
        }
      }
    });
  }

  async function refreshInventory() {
    setStatus('Scanning…', false);
    try {
      const [devRes, healthRes] = await Promise.all([
        fetch(`${AGENT}/devices`, { mode: 'cors' }),
        fetch(`${AGENT}/health`, { mode: 'cors' }).catch(() => null),
      ]);
      if (!devRes.ok) throw new Error('devices failed');
      const devices = await devRes.json();
      lastDevicesRaw = devices;
      let elevated = true;
      if (healthRes && healthRes.ok) {
        const h = await healthRes.json();
        elevated = h.elevated !== false;
      }
      const banner = el('dx-hwref-elevate');
      if (banner) {
        if (!elevated) {
          banner.hidden = false;
          banner.className = 'dx-hwref__banner warn';
          banner.textContent = 'Sensors degraded — Probe is not elevated. Restart Start-PcLabProbe.bat as Administrator for CPU die / SMBus sensors.';
        } else {
          banner.hidden = true;
        }
      }

      const presentRes = await fetch('/api/diagnostic/inventory/present', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ devices }),
      });
      lastInventory = await presentRes.json();
      window.__dxLastInventory = lastInventory;
      window.__dxLastDevices = devices;
      setStatus(`${lastInventory.summary?.total_devices ?? 0} devices`, true);
      renderTree();
      if ((lastInventory.all_devices || [])[0]) {
        selectedId = lastInventory.all_devices[0].instance_id;
        renderDetail(lastInventory.all_devices[0]);
      }
      await loadTopology({ devices, elevated, probe_version: 2, agent: 'pclab-probe' });
      await loadOpenBook();
      window.dispatchEvent(new CustomEvent('dx:inventory-updated', { detail: { inventory: lastInventory, devices } }));
    } catch (e) {
      setStatus('Probe offline — start PcLab Probe', false);
    }
  }

  function exportJson() {
    const payload = lastInventory || lastDevicesRaw;
    if (!payload) return;
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'pc-lab-kit-hardware-reference.json';
    a.click();
    URL.revokeObjectURL(a.href);
  }

  async function loadOpenBook() {
    if (window.PcLabOpenBook?.refresh) {
      await window.PcLabOpenBook.refresh();
      return;
    }
    const box = el('dx-hwref-openbook-table');
    if (!box) return;
    try {
      const r = await fetch(`${AGENT}/openbook`, { cache: 'no-store' });
      if (!r.ok) throw new Error('openbook ' + r.status);
      const data = await r.json();
      window.__dxLastOpenBook = data;
      const wrap = data.open_book || data;
      const sensors = wrap.sensors || [];
      const dossierBox = el('dx-hwref-dossier-body');
      if (dossierBox && data.dossier) {
        const cpu = data.dossier.cpu || {};
        const gpu = data.dossier.gpu || {};
        dossierBox.innerHTML = `<p class="fs-sm">${esc(cpu.model || '—')} · ${esc(gpu.name || '—')}</p>`;
      }
      if (!sensors.length) {
        box.innerHTML = `<p class="muted fs-sm">${esc(wrap.note || data.note || 'No open-book sensors this sample. Run Probe as Administrator.')}</p>`;
        return;
      }
      let html = `<p class="muted fs-xs">${esc(wrap.count)} recovered · therm ${wrap.open_book_therm ? 'yes' : 'no'} · vram ${wrap.open_book_vram ? 'yes' : 'no'}</p>
        <table class="dx-hwref__ob-table"><thead><tr><th>Sensor</th><th>°C</th><th>Source</th><th>Raw</th><th>PCI</th></tr></thead><tbody>`;
      sensors.forEach((s) => {
        const val = s.value == null ? '—' : Number(s.value).toFixed(1);
        html += `<tr>
          <td>${esc(s.name)}${s.hardware ? `<div class="muted fs-xs">${esc(s.hardware)}</div>` : ''}</td>
          <td>${esc(val)}</td>
          <td><code>${esc(s.source)}</code></td>
          <td><code>${esc(s.raw_hex || '—')}</code></td>
          <td>${esc(s.pci_bdf || '—')}</td>
        </tr>`;
      });
      html += '</tbody></table>';
      box.innerHTML = html;
    } catch (e) {
      box.innerHTML = '<p class="muted fs-sm">Open Book unavailable — start elevated Probe.</p>';
    }
  }

  function bind() {
    el('dx-hwref-refresh')?.addEventListener('click', () => refreshInventory());
    el('dx-hwref-export')?.addEventListener('click', exportJson);
    el('dx-topo-refresh')?.addEventListener('click', () => {
      if (lastDevicesRaw) loadTopology({ devices: lastDevicesRaw, probe_version: 2, agent: 'pclab-probe' });
      else refreshInventory();
    });
    bindTopo3dToggle();
    el('dx-hwref-search')?.addEventListener('input', () => renderTree());
    document.querySelectorAll('#dx-hwref-filters [data-hw-filter]').forEach((cb) => {
      cb.addEventListener('change', () => renderTree());
    });
    // Auto-scan when Hardware tab opens
    document.querySelector('[data-dx-tab="hardware"]')?.addEventListener('click', () => {
      if (!lastInventory) refreshInventory();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }

  window.PcLabHardwareRef = { refresh: refreshInventory, getInventory: () => lastInventory };
})();
