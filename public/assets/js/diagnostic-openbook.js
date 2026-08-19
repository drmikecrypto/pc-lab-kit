/**
 * Open Book Lab tab — dossier, live recovered sensors, assembly certificate.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  let lastPayload = null;
  let lastCertHtml = null;
  let timer = null;

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

  function unwrapOpenBook(data) {
    const wrap = data && (data.open_book || data);
    return {
      sensors: Array.isArray(wrap?.sensors) ? wrap.sensors : [],
      count: wrap?.count ?? (wrap?.sensors ? wrap.sensors.length : 0),
      open_book_therm: !!(wrap?.open_book_therm),
      open_book_vram: !!(wrap?.open_book_vram),
      note: wrap?.note || data?.note || '',
      dossier: data?.dossier || null,
      thermal: data?.thermal || null,
      pcie: data?.pcie || null,
      provenance_total: data?.provenance_total ?? 0,
    };
  }

  function renderSensorTable(sensors, count, therm, vram, note) {
    if (!sensors.length) {
      return `<p class="muted fs-sm">${esc(note || 'No open-book sensors this sample. Run Probe as Administrator.')}</p>`;
    }
    let html = `<p class="muted fs-xs">${esc(count)} recovered · therm ${therm ? 'yes' : 'no'} · vram ${vram ? 'yes' : 'no'}</p>
      <table class="dx-hwref__ob-table"><thead><tr><th>Sensor</th><th>Value</th><th>Source</th><th>Raw</th><th>PCI</th></tr></thead><tbody>`;
    sensors.forEach((s) => {
      const val = s.value == null ? '—' : Number(s.value).toFixed(1);
      html += `<tr>
        <td>${esc(s.name)}${s.hardware ? `<div class="muted fs-xs">${esc(s.hardware)}</div>` : ''}</td>
        <td>${esc(val)} ${esc(s.unit || '°C')}</td>
        <td><code>${esc(s.source)}</code></td>
        <td><code>${esc(s.raw_hex || '—')}</code></td>
        <td>${esc(s.pci_bdf || '—')}</td>
      </tr>`;
    });
    html += '</tbody></table>';
    return html;
  }

  function renderDossierHtml(dossier) {
    if (!dossier || typeof dossier !== 'object') {
      return '<p class="muted fs-sm">Dossier unavailable.</p>';
    }
    const cpu = dossier.cpu || {};
    const gpu = dossier.gpu || {};
    const ram = dossier.ram || {};
    const board = dossier.board || {};
    const mods = Array.isArray(ram.modules) ? ram.modules : [];
    const storage = Array.isArray(dossier.storage) ? dossier.storage : [];
    const monitors = Array.isArray(dossier.monitors) ? dossier.monitors : [];
    const pci = Array.isArray(dossier.pci_config) ? dossier.pci_config : (Array.isArray(gpu.pci_config) ? gpu.pci_config : []);
    const ob = dossier.open_book || {};
    return `<dl class="dx-hwref__dl">
      <dt>CPU</dt><dd>${esc(cpu.model || '—')} · fam ${esc(cpu.family || '—')} / model ${esc(cpu.model_id || '—')} / step ${esc(cpu.stepping || '—')}</dd>
      <dt>GPU</dt><dd>${esc(gpu.name || '—')}<div class="muted fs-xs">${esc(gpu.vbios || '')} · ${esc(gpu.hotspot_source || '')}</div></dd>
      <dt>Board</dt><dd>${esc(board.manufacturer || '')} ${esc(board.product || '—')}<div class="muted fs-xs">SN ${esc(board.serial || '—')} · BIOS ${esc(board.bios || '—')}</div></dd>
      <dt>RAM</dt><dd>${esc(mods.length)} module(s) · ${esc(ram.source || 'smbios')}${ram.note ? `<div class="muted fs-xs">${esc(ram.note)}</div>` : ''}</dd>
      <dt>Storage</dt><dd>${esc(storage.map((d) => d.friendly_name || d.model).filter(Boolean).join(', ') || '—')}</dd>
      <dt>Monitors</dt><dd>${esc(monitors.map((m) => m.name).filter(Boolean).join(', ') || '—')}</dd>
      <dt>Open-book</dt><dd>${esc(ob.count ?? dossier.open_book_count ?? 0)} channels</dd>
    </dl>
    ${pci.length ? `<details><summary>PCI config (${pci.length})</summary><pre class="dx-hwref__raw muted fs-xs">${esc(JSON.stringify(pci, null, 2).slice(0, 6000))}</pre></details>` : ''}
    ${monitors.some((m) => m.edid_hex) ? `<details><summary>EDID hex</summary><pre class="dx-hwref__raw muted fs-xs">${esc(monitors.map((m) => (m.name || '') + '\n' + (m.edid_hex || '')).join('\n\n').slice(0, 8000))}</pre></details>` : ''}`;
  }

  function renderGauges(sensors, thermal) {
    const picks = [];
    const byName = (re) => sensors.find((s) => re.test(String(s.name || '')));
    const hs = byName(/hot\s*spot/i) || (thermal?.gpu && { value: thermal.gpu.hot_spot_c, name: 'Hotspot' });
    const vram = byName(/memory junction|vram/i);
    const s1 = byName(/therm s1/i);
    const core = thermal?.gpu?.core_c;
    if (core != null) picks.push({ label: 'GPU core', value: core });
    if (hs && hs.value != null) picks.push({ label: 'Hotspot', value: hs.value });
    if (vram && vram.value != null) picks.push({ label: 'VRAM', value: vram.value });
    if (s1 && s1.value != null) picks.push({ label: 'Therm S1', value: s1.value });
    if (thermal?.cpu?.package_c != null) picks.push({ label: 'CPU pkg', value: thermal.cpu.package_c });
    if (!picks.length) return '<p class="muted fs-sm">No live temperatures yet.</p>';
    return picks.map((p) => `<div class="dx-openbook-lab__gauge"><div class="dx-openbook-lab__val">${esc(Number(p.value).toFixed(1))}</div><div class="muted fs-xs">${esc(p.label)}</div></div>`).join('');
  }

  function downloadJson(obj, name) {
    if (!obj) return;
    const blob = new Blob([JSON.stringify(obj, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  async function refresh() {
    const status = el('dx-ob-status');
    if (status) status.textContent = 'Scanning…';
    try {
      const r = await fetch(`${AGENT()}/openbook`, { cache: 'no-store' });
      if (!r.ok) throw new Error('openbook ' + r.status);
      const data = await r.json();
      lastPayload = data;
      window.__dxLastOpenBook = data;
      const ob = unwrapOpenBook(data);
      const pcieWarn = ob.pcie?.warnings?.length
        ? `<p class="muted fs-xs warn">PCIe: ${esc(ob.pcie.warnings.join('; '))}</p>`
        : '';
      const table = pcieWarn + renderSensorTable(ob.sensors, ob.count, ob.open_book_therm, ob.open_book_vram, ob.note);
      const dossierHtml = renderDossierHtml(ob.dossier);
      const hwTable = el('dx-hwref-openbook-table');
      if (hwTable) hwTable.innerHTML = table;
      const hwDossier = el('dx-hwref-dossier-body');
      if (hwDossier) hwDossier.innerHTML = dossierHtml;
      const obTable = el('dx-ob-table');
      if (obTable) obTable.innerHTML = table;
      const obDossier = el('dx-ob-dossier-body');
      if (obDossier) obDossier.innerHTML = dossierHtml;
      const gauges = el('dx-ob-gauges');
      if (gauges) gauges.innerHTML = renderGauges(ob.sensors, ob.thermal);
      if (status) status.textContent = `${ob.count} open-book · ${ob.provenance_total || 0} tags · ${ob.dossier?.cpu?.model || 'Probe ok'}`;
      window.dispatchEvent(new CustomEvent('dx:openbook-updated', { detail: data }));
    } catch (e) {
      if (status) status.textContent = 'Probe offline';
      const msg = '<p class="muted fs-sm">Open Book unavailable — start elevated Probe.</p>';
      ['dx-ob-table', 'dx-hwref-openbook-table'].forEach((id) => {
        const n = el(id);
        if (n) n.innerHTML = msg;
      });
    }
  }

  function applySuiteCert(job) {
    const html = job?.result?.assembly_certificate_html;
    const doc = job?.result?.assembly_certificate;
    const analysis = job?.result?.analysis || {};
    const cert = analysis.stress_certificate || {};
    lastCertHtml = html || null;
    const status = el('dx-ob-cert-status');
    const actions = el('dx-ob-cert-actions');
    if (status) {
      status.innerHTML = `Stress <strong>${esc(cert.verdict || doc?.verdict || '—')}</strong>
        · open-book ${esc(doc?.open_book_count ?? analysis.silicon_dossier?.open_book?.count ?? '—')}`;
    }
    if (actions) {
      actions.innerHTML = html
        ? '<button type="button" class="dx-btn primary" id="dx-ob-open-cert">Open Assembly Certificate</button>'
        : '';
      el('dx-ob-open-cert')?.addEventListener('click', () => {
        const frame = el('dx-ob-cert-frame');
        if (!frame || !lastCertHtml) return;
        frame.hidden = false;
        frame.innerHTML = lastCertHtml;
      });
    }
  }

  function bind() {
    el('dx-ob-refresh')?.addEventListener('click', () => refresh());
    el('dx-ob-export-dossier')?.addEventListener('click', () => {
      downloadJson(lastPayload?.dossier || lastPayload, 'pc-lab-kit-silicon-dossier.json');
    });
    el('dx-hwref-dossier-export')?.addEventListener('click', () => {
      downloadJson(lastPayload?.dossier || window.__dxLastOpenBook?.dossier, 'pc-lab-kit-silicon-dossier.json');
    });
    document.querySelector('[data-dx-tab="openbook"]')?.addEventListener('click', () => {
      refresh();
      if (!timer) timer = setInterval(refresh, 8000);
    });
    window.addEventListener('dx:suite-complete', (ev) => applySuiteCert(ev.detail));
  }

  window.PcLabOpenBook = {
    refresh,
    unwrap: unwrapOpenBook,
    renderSensorTable,
    renderDossierHtml,
    applySuiteCert,
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bind);
  } else {
    bind();
  }
})();
