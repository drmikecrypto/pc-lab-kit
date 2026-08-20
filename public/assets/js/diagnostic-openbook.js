/**
 * Open Book Lab tab — dossier, truth cards, live recovered sensors.
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
      platform: data?.platform || data?.dossier?.platform || null,
      fingerprint: data?.fingerprint || data?.dossier?.fingerprint || null,
      thermal: data?.thermal || null,
      pcie: data?.pcie || null,
      provenance_total: data?.provenance_total ?? 0,
    };
  }

  function coverageMeterHtml(fp) {
    if (!fp) return '';
    const score = Number(fp.coverage_score ?? 0);
    const gaps = Array.isArray(fp.gaps) ? fp.gaps : [];
    const gapList = gaps.slice(0, 6).map((g) =>
      `<li><code>${esc(g.plane || g.reason || '')}</code> — ${esc(g.detail || '')}</li>`
    ).join('');
    return `<div class="dx-platform-coverage">
      <div class="dx-platform-coverage__bar" role="meter" aria-valuenow="${esc(score)}" aria-valuemin="0" aria-valuemax="100">
        <span style="width:${esc(Math.min(100, Math.max(0, score)))}%"></span>
      </div>
      <p class="fs-sm"><strong>${esc(score)}%</strong> platform coverage · ${esc(fp.planes_measured ?? '—')}/${esc(fp.planes_total ?? '—')} planes · ${esc(fp.form_factor || '—')} · fp <code>${esc((fp.id || '').slice(0, 12))}</code></p>
      ${gapList ? `<ul class="dx-platform-coverage__gaps muted fs-xs">${gapList}</ul>` : ''}
    </div>`;
  }

  function truthCardsHtml(dossier, platform, fingerprint) {
    if (!dossier && !platform) return '';
    const fw = (dossier && dossier.firmware_inventory) || {};
    const board = (dossier && dossier.board) || {};
    const cpu = (dossier && dossier.cpu) || {};
    const gpu = (dossier && dossier.gpu) || {};
    const plat = platform || (dossier && dossier.platform) || {};
    const uefi = plat.uefi || fw.uefi || {};
    const tpm = plat.tpm || fw.tpm || {};
    const me = plat.me_psp || fw.me_psp || {};
    const acpi = plat.acpi || {};
    const smbios = plat.smbios || {};
    const cards = [
      {
        title: 'UEFI / BIOS',
        body: `${board.bios_vendor || fw.bios_vendor || plat.bios?.vendor || '—'} · ${board.bios || fw.bios_version || plat.bios?.version || '—'}`,
        meta: `${uefi.firmware_type || 'firmware'} · Secure Boot ${uefi.secure_boot == null && fw.secure_boot == null ? '—' : (uefi.secure_boot ?? fw.secure_boot) ? 'on' : 'off'} · ${plat.bios?.source || fw.provenance || 'wmi'}`,
      },
      {
        title: 'SMBIOS',
        body: smbios.available
          ? `v${smbios.smbios_major ?? '—'}.${smbios.smbios_minor ?? '—'} · ${Object.keys(smbios.type_counts || {}).filter((k) => (smbios.type_counts || {})[k]).length} type groups`
          : 'Raw tables unavailable',
        meta: smbios.confidence || smbios.source || 'unavailable',
      },
      {
        title: 'CPU microcode',
        body: cpu.microcode || fw.cpu_microcode || plat.microcode?.revision || '—',
        meta: `${cpu.model || '—'} · ${cpu.source || plat.microcode?.source || 'registry'}`,
      },
      {
        title: 'GPU VBIOS',
        body: gpu.vbios || fw.gpu_vbios || '—',
        meta: gpu.vbios_sha256 || fw.gpu_vbios_sha256
          ? `SHA-256 ${(gpu.vbios_sha256 || fw.gpu_vbios_sha256).slice(0, 16)}…`
          : (gpu.hotspot_source || 'identity'),
      },
      {
        title: 'TPM · Secure Boot',
        body: tpm.present ? `TPM ${tpm.spec_version || tpm.version || 'present'} · ${tpm.manufacturer_id || ''}`.trim() : 'TPM not reported',
        meta: `FW ${tpm.manufacturer_version || '—'} · PCR ${(tpm.pcr_banks || []).join(',') || '—'} (${tpm.pcr_bank_source || '—'}) · ready ${tpm.ready == null ? '—' : tpm.ready ? 'yes' : 'no'}`,
      },
      {
        title: 'UEFI policy',
        body: `${uefi.firmware_type || 'firmware'} · Secure Boot ${uefi.secure_boot == null && fw.secure_boot == null ? '—' : (uefi.secure_boot ?? fw.secure_boot) ? 'on' : 'off'}`,
        meta: `SetupMode ${uefi.setup_mode == null ? '—' : uefi.setup_mode ? 'on' : 'off'} · BitLocker ${uefi.bitlocker?.system_drive_protection || '—'} · entries ${(uefi.boot_entries || []).length}`,
      },
      {
        title: 'ME / PSP',
        body: me.present ? `${(me.vendor || 'me/psp').toUpperCase()} · ${(me.devices || []).length} device(s)` : 'Not detected',
        meta: me.generic_driver ? 'generic driver — update recommended' : (me.confidence || me.source || '—'),
      },
      {
        title: 'ACPI',
        body: (acpi.signatures || fw.acpi_tables || []).slice(0, 10).join(', ') || '—',
        meta: `${acpi.signature_count ?? (fw.acpi_tables || []).length} sig · FADT ${acpi.has_fadt ? 'yes' : 'no'} · DSDT ${acpi.has_dsdt ? 'yes' : 'no'} · TZ ${acpi.thermal_zone_count ?? '—'}`,
      },
      {
        title: 'Storage firmware',
        body: (fw.storage_firmware || (plat.storage || []).map((d) => ({ name: d.friendly_name, firmware: d.firmware, source: d.source })))
          .map((d) => `${d.name || d.serial || 'disk'}: ${d.firmware || '—'}`)
          .slice(0, 4)
          .join(' · ') || '—',
        meta: (plat.storage && plat.storage[0] && plat.storage[0].source) || fw.provenance || 'storage_reliability',
      },
      {
        title: 'PCI config',
        body: `${fw.pci_config_count ?? (plat.pci_config || []).length || (gpu.pci_config || []).length || 0} dump(s)`,
        meta: (plat.pci_config || gpu.pci_config || [])[0]
          ? `${(plat.pci_config || gpu.pci_config)[0].role || 'fn'} @ ${(plat.pci_config || gpu.pci_config)[0].pci_bdf || '—'}`
          : 'elevate for Ring0 dumps',
      },
      {
        title: 'EC / board sensors',
        body: `${fw.ec_board_count ?? plat.ec_board?.count ?? 0} channel(s)`,
        meta: plat.ec_board?.board_match_confidence || plat.ec_board?.source || 'lhm',
      },
    ];
    const meter = coverageMeterHtml(fingerprint || dossier?.fingerprint);
    return meter + cards
      .map(
        (c) => `<article class="dx-truth-card">
        <h4>${esc(c.title)}</h4>
        <p>${esc(c.body)}</p>
        <span class="muted fs-xs">${esc(c.meta)}</span>
      </article>`
      )
      .join('');
  }

  function renderSensorTable(sensors, count, therm, vram, note) {
    if (!sensors.length) {
      return `<p class="muted fs-sm">${esc(note || 'No open-book sensors this sample. Run Probe as Administrator.')}</p>`;
    }
    let html = `<p class="muted fs-xs">${esc(count)} recovered · therm ${therm ? 'yes' : 'no'} · vram ${vram ? 'yes' : 'no'} · provenance on every row</p>
      <table class="dx-hwref__ob-table"><thead><tr><th>Sensor</th><th>Value</th><th>Source</th><th>Confidence</th><th>Raw</th><th>PCI</th></tr></thead><tbody>`;
    sensors.forEach((s) => {
      const val = s.value == null ? '—' : Number(s.value).toFixed(1);
      html += `<tr>
        <td>${esc(s.name)}${s.hardware ? `<div class="muted fs-xs">${esc(s.hardware)}</div>` : ''}</td>
        <td>${esc(val)} ${esc(s.unit || '°C')}</td>
        <td><code>${esc(s.source)}</code></td>
        <td>${esc(s.confidence || s.confidence_tag || '—')}</td>
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
    const fw = dossier.firmware_inventory || {};
    const mods = Array.isArray(ram.modules) ? ram.modules : [];
    const storage = Array.isArray(dossier.storage) ? dossier.storage : [];
    const monitors = Array.isArray(dossier.monitors) ? dossier.monitors : [];
    const pci = Array.isArray(dossier.pci_config) ? dossier.pci_config : (Array.isArray(gpu.pci_config) ? gpu.pci_config : []);
    const ob = dossier.open_book || {};
    return `<dl class="dx-hwref__dl">
      <dt>CPU</dt><dd>${esc(cpu.model || '—')} · fam ${esc(cpu.family || '—')} / model ${esc(cpu.model_id || '—')} / step ${esc(cpu.stepping || '—')}<div class="muted fs-xs">Microcode ${esc(cpu.microcode || '—')}</div></dd>
      <dt>GPU</dt><dd>${esc(gpu.name || '—')}<div class="muted fs-xs">VBIOS ${esc(gpu.vbios || '—')} · ${esc(gpu.hotspot_source || '')}${gpu.vbios_sha256 ? ' · sha ' + esc(String(gpu.vbios_sha256).slice(0, 12)) + '…' : ''}</div></dd>
      <dt>Board</dt><dd>${esc(board.manufacturer || '')} ${esc(board.product || '—')}<div class="muted fs-xs">SN ${esc(board.serial || '—')} · BIOS ${esc(board.bios_vendor || '')} ${esc(board.bios || '—')} (${esc(board.bios_date || '—')})</div></dd>
      <dt>Firmware</dt><dd>TPM ${esc(fw.tpm?.present ? 'yes' : 'no')} · Secure Boot ${esc(fw.secure_boot == null ? '—' : fw.secure_boot ? 'on' : 'off')}<div class="muted fs-xs">${esc(fw.note || '')}</div></dd>
      <dt>RAM</dt><dd>${esc(mods.length)} module(s) · ${esc(ram.source || 'smbios')}${ram.note ? `<div class="muted fs-xs">${esc(ram.note)}</div>` : ''}</dd>
      <dt>Storage</dt><dd>${esc(storage.map((d) => `${d.friendly_name || d.model || ''}${d.firmware ? ' fw ' + d.firmware : ''}`).filter(Boolean).join(', ') || '—')}</dd>
      <dt>Monitors</dt><dd>${esc(monitors.map((m) => m.name).filter(Boolean).join(', ') || '—')}</dd>
      <dt>Open-book</dt><dd>${esc(ob.count ?? dossier.open_book_count ?? 0)} channels</dd>
    </dl>
    ${pci.length ? `<details open><summary>PCI config (${pci.length})</summary><pre class="dx-hwref__raw muted fs-xs">${esc(JSON.stringify(pci, null, 2).slice(0, 8000))}</pre></details>` : ''}
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
      const truth = el('dx-ob-truth-cards');
      if (truth) truth.innerHTML = truthCardsHtml(ob.dossier, ob.platform, ob.fingerprint);
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
      if (status) status.textContent = `${ob.count} open-book · ${ob.fingerprint?.coverage_score ?? '—'}% coverage · ${ob.provenance_total || 0} tags · ${ob.dossier?.cpu?.model || 'Probe ok'}`;
      window.dispatchEvent(new CustomEvent('dx:openbook-updated', { detail: data }));
    } catch (e) {
      if (status) status.textContent = 'Probe offline';
      const msg = '<p class="muted fs-sm">Open Book unavailable — start elevated Probe (bundled in the desktop app).</p>';
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
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'openbook') {
        refresh();
        if (!timer) timer = setInterval(refresh, 8000);
      }
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
