(function () {
  const cfg = window.PCVERSE_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';
  let scan = null;
  let catalog = null;
  const zoneState = {};

  const root = document.getElementById('dx-rgb-lab');
  if (!root) return;

  function jsonHeadersWithCsrf() {
    const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    return { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t };
  }

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  function parseGifDimensions(buffer) {
    const v = new Uint8Array(buffer);
    if (v.length < 10 || v[0] !== 0x47 || v[1] !== 0x49 || v[2] !== 0x46) return null;
    return { w: v[6] + (v[7] << 8), h: v[8] + (v[9] << 8) };
  }

  function getTelemetry() {
    return window.__dxLastProbe?.telemetry || window.__dxLastProbe || {};
  }

  function getContext() {
    const last = window.__dxLastScan || {};
    return {
      health_score: last.health_score,
      gpu_util_avg: last.metrics?.gpu_util_avg,
      cpu_core_max: last.metrics?.cpu_core_max,
    };
  }

  async function loadCatalog() {
    try {
      const res = await fetch('/api/diagnostic/rgb/catalog');
      catalog = await res.json();
    } catch (_) {
      catalog = { effects: [{ id: 'static', label: 'Static' }] };
    }
  }

  async function rgbScan() {
    const st = document.getElementById('dx-rgb-status');
    if (st) { st.textContent = 'Scanning…'; st.className = 'dx-rgb-status warn'; }
    try {
      const res = await fetch(`${AGENT}/rgb/scan`, { mode: 'cors' });
      if (!res.ok) throw new Error('scan fail');
      scan = await res.json();
      render();
    } catch (e) {
      if (st) { st.textContent = 'Probe offline — Start-PCVerseProbe.bat'; st.className = 'dx-rgb-status warn'; }
      document.getElementById('dx-rgb-devices').innerHTML = '<div class="dx-rgb-empty"><p><strong>Probe not available</strong></p><p>Run <code>Start-PCVerseProbe.bat</code>, then click Rescan RGB. Default: <code dir="ltr">127.0.0.1:18765</code></p></div>';
    }
  }

  function showEnablePopup(guide) {
    if (!guide) return;
    const existing = document.getElementById('dx-rgb-popup');
    if (existing) existing.remove();
    const ol = (guide.steps || guide.steps_fa || []).map((s) => `<li>${esc(s)}</li>`).join('');
    const wrap = document.createElement('div');
    wrap.id = 'dx-rgb-popup';
    wrap.className = 'dx-rgb-popup-overlay';
    wrap.innerHTML = `
      <div class="dx-rgb-popup">
        <button type="button" class="dx-rgb-popup-close">×</button>
        <div class="dx-rgb-brand">PCVerse · RGB</div>
        <h3>${esc(guide.title || guide.title_fa || 'Enable RGB')}</h3>
        <p class="muted fs-sm">${esc(guide.why || guide.why_fa || '')}</p>
        <ol>${ol}</ol>
        <button type="button" class="dx-btn primary mt-3" id="dx-rgb-popup-rescan">Rescan</button>
      </div>`;
    document.body.appendChild(wrap);
    wrap.querySelector('.dx-rgb-popup-close').addEventListener('click', () => wrap.remove());
    wrap.addEventListener('click', (e) => { if (e.target === wrap) wrap.remove(); });
    wrap.querySelector('#dx-rgb-popup-rescan').addEventListener('click', () => { wrap.remove(); rgbScan(); });
  }

  function showVakhshResult(narrative, apply) {
    const existing = document.getElementById('dx-vakhsh-result');
    if (existing) existing.remove();

    const did = (narrative.did || narrative.did_fa || []).map((d) => `<li>${esc(d)}</li>`).join('');
    const compare = narrative.compare || narrative.compare_fa || {};
    const cmpHtml = Object.entries(compare).map(([k, v]) =>
      `<div class="dx-vkh-cmp"><span class="dx-vkh-cmp-k">${esc(k)}</span><span>${esc(v)}</span></div>`
    ).join('');
    const steps = (narrative.next_steps || narrative.next_steps_fa || []).map((s) => `<li>${esc(s)}</li>`).join('');

    const paths = [];
    if (apply?.lcd_dashboard_path) paths.push(`LCD: ${apply.lcd_dashboard_path}`);
    if (apply?.fan_curve_path) paths.push(`Fan: ${apply.fan_curve_path}`);

    const wrap = document.createElement('div');
    wrap.id = 'dx-vakhsh-result';
    wrap.className = 'dx-rgb-popup-overlay';
    wrap.innerHTML = `
      <div class="dx-vkh-result">
        <button type="button" class="dx-rgb-popup-close">×</button>
        <div class="dx-rgb-brand">PCVerse · RGB setup</div>
        <h2>${esc(narrative.headline || narrative.headline_fa || 'Done.')}</h2>
        <p class="dx-vkh-why">${esc(narrative.why || narrative.why_fa || '')}</p>
        <div class="dx-vkh-section">
          <h4>What we did</h4>
          <ul>${did}</ul>
        </div>
        <div class="dx-vkh-section dx-vkh-benefit">
          <p>${esc(narrative.benefit || narrative.benefit_fa || '')}</p>
        </div>
        <div class="dx-vkh-compare">${cmpHtml}</div>
        ${paths.length ? `<p class="dx-vkh-paths muted fs-xs">${paths.map(esc).join('<br>')}</p>` : ''}
        ${steps ? `<div class="dx-vkh-section"><h4>Next steps</h4><ol>${steps}</ol></div>` : ''}
        <button type="button" class="dx-btn primary mt-3" id="dx-vkh-close">Got it</button>
      </div>`;
    document.body.appendChild(wrap);
    wrap.querySelector('.dx-rgb-popup-close').addEventListener('click', () => wrap.remove());
    wrap.querySelector('#dx-vkh-close').addEventListener('click', () => wrap.remove());
    wrap.addEventListener('click', (e) => { if (e.target === wrap) wrap.remove(); });
  }

  function effectOptions(cap) {
    const fx = cap?.effects || catalog?.effects?.map((e) => e.id) || ['static'];
    return (catalog?.effects || [])
      .filter((e) => fx.includes(e.id))
      .map((e) => `<option value="${esc(e.id)}">${esc(e.label || e.label_fa || e.id)}</option>`)
      .join('');
  }

  function renderDevice(dev) {
    const zones = (dev.zones || []).map((z) => {
      const zid = z.zone_id;
      if (!zoneState[zid]) {
        zoneState[zid] = { color: '#22d3ee', effect: 'static', speed: 50, openrgb_device: z.openrgb_device, openrgb_zone: z.openrgb_zone };
      }
      const st = zoneState[zid];
      return `<div class="dx-rgb-zone">
        <div class="dx-rgb-zone-lbl">${esc(z.label || z.label_fa || z.zone_type)}</div>
        <div class="dx-rgb-controls">
          <input type="color" value="${esc(st.color)}" data-z="${esc(zid)}" data-k="color">
          <select data-z="${esc(zid)}" data-k="effect">${effectOptions(z.capabilities)}</select>
          <input type="range" min="0" max="100" value="${st.speed}" data-z="${esc(zid)}" data-k="speed" style="width:80px">
        </div>
      </div>`;
    }).join('');

    let lcd = '';
    if (dev.lcd && dev.lcd.gif_supported) {
      const round = dev.lcd.width === dev.lcd.height;
      lcd = `<div class="dx-rgb-lcd">
        <div class="dx-rgb-zone-lbl">LCD ${dev.lcd.width}×${dev.lcd.height}</div>
        <div class="dx-rgb-lcd-preview${round ? '' : ' square'}" id="lcd-prev-${esc(dev.id)}"><span class="muted fs-xs">Preview</span></div>
        <input type="file" accept="image/gif" class="dx-file-input" data-lcd-dev="${esc(dev.id)}" data-lcd-w="${dev.lcd.width}" data-lcd-h="${dev.lcd.height}">
      </div>`;
    }

    return `<div class="dx-rgb-device"><div class="dx-rgb-device-head"><strong>${esc(dev.label)}</strong><span class="dx-rgb-type">${esc(dev.device_type || 'rgb')}</span></div>${zones}${lcd}</div>`;
  }

  function render() {
    const st = document.getElementById('dx-rgb-status');
    const list = document.getElementById('dx-rgb-devices');
    if (!scan || !list) return;
    const ready = scan.control?.ready;
    if (st) {
      st.textContent = ready ? `✓ ${scan.device_count} devices · unified control` : `${scan.device_count || 0} detected · ${scan.control?.backend || '—'}`;
      st.className = 'dx-rgb-status ' + (ready ? 'ok' : 'warn');
    }
    if (!scan.devices?.length) {
      list.innerHTML = '<div class="dx-rgb-empty">No RGB LED or controller found. Check USB cables, ARGB hub, or competing software (e.g. iCUE) blocking OpenRGB.</div>';
      return;
    }
    list.innerHTML = scan.devices.map(renderDevice).join('');
    list.querySelectorAll('input[data-z], select[data-z]').forEach((el) => {
      el.addEventListener('input', () => {
        const zid = el.dataset.z;
        if (!zoneState[zid]) return;
        zoneState[zid][el.dataset.k] = el.type === 'range' ? parseInt(el.value, 10) : el.value;
      });
    });
    list.querySelectorAll('input[type=file][data-lcd-dev]').forEach((inp) => {
      inp.addEventListener('change', () => uploadGif(inp));
    });
  }

  async function vakhshProSetup() {
    const btn = document.getElementById('dx-rgb-vakhsh');
    if (btn) { btn.disabled = true; btn.textContent = 'Working…'; }

    try {
      const orchRes = await fetch('/api/diagnostic/vakhsh/orchestrate', {
        method: 'POST',
        headers: jsonHeadersWithCsrf(),
        body: JSON.stringify({ telemetry: getTelemetry(), context: getContext() }),
      });
      const orch = await orchRes.json();
      const plan = orch.plan;

      const applyRes = await fetch(`${AGENT}/vakhsh/orchestrate`, {
        method: 'POST',
        mode: 'cors',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan }),
      });
      const apply = await applyRes.json();

      const narRes = await fetch('/api/diagnostic/vakhsh/narrate', {
        method: 'POST',
        headers: jsonHeadersWithCsrf(),
        body: JSON.stringify({ plan, apply }),
      });
      const nar = await narRes.json();

      if (!apply.ok && !apply.partial) {
        showEnablePopup(apply.enable_guide || scan?.enable_guide);
        return;
      }

      if (window.dxTrackLab) {
        window.dxTrackLab('vakhsh_rgb_setup', { device_count: scan?.device_count || 0, partial: !!apply.partial });
      }
      showVakhshResult(nar.narrative || orch.narrative, apply);
      rgbScan();
    } catch (e) {
      showEnablePopup(scan?.enable_guide);
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = 'Auto setup'; }
    }
  }

  async function applyZones() {
    if (!scan?.control?.ready) {
      showEnablePopup(scan?.enable_guide);
      return;
    }
    const zones = Object.entries(zoneState).map(([zone_id, s]) => ({
      zone_id, openrgb_device: s.openrgb_device, openrgb_zone: s.openrgb_zone,
      effect: s.effect, color: (s.color || '#22d3ee').replace('#', ''), speed: s.speed || 50,
    })).filter((z) => z.openrgb_device != null);

    const res = await fetch(`${AGENT}/rgb/apply`, {
      method: 'POST', mode: 'cors', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ zones }),
    });
    const data = await res.json();
    if (!data.ok) showEnablePopup(scan.enable_guide);
  }

  async function uploadGif(input) {
    const file = input.files?.[0];
    if (!file || file.size > 25 * 1024 * 1024) return;
    const buf = await file.arrayBuffer();
    const dim = parseGifDimensions(buf);
    const ew = parseInt(input.dataset.lcdW, 10);
    const eh = parseInt(input.dataset.lcdH, 10);
    if (dim && ew && eh && (dim.w !== ew || dim.h !== eh)) {
      alert(`GIF must be ${ew}×${eh} — got ${dim.w}×${dim.h}`);
      return;
    }
    const prev = document.getElementById(`lcd-prev-${input.dataset.lcdDev}`);
    if (prev) {
      prev.innerHTML = '';
      const img = document.createElement('img');
      img.src = URL.createObjectURL(file);
      prev.appendChild(img);
    }
    const bytes = new Uint8Array(buf);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    const res = await fetch(`${AGENT}/rgb/lcd`, {
      method: 'POST', mode: 'cors', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ device_id: input.dataset.lcdDev, expected_w: ew, expected_h: eh, gif_base64: btoa(binary) }),
    });
    const data = await res.json();
    if (!data.ok) alert(data.message_fa || data.error);
  }

  window.addEventListener('dx:scan-complete', (e) => { window.__dxLastScan = e.detail; });

  document.getElementById('dx-rgb-scan')?.addEventListener('click', rgbScan);
  document.getElementById('dx-rgb-apply')?.addEventListener('click', applyZones);
  document.getElementById('dx-rgb-vakhsh')?.addEventListener('click', vakhshProSetup);

  loadCatalog().then(rgbScan);
})();
