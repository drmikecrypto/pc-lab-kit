/**
 * LCD Studio — universal AIO / case panel media (GIF + longer video).
 * Tauri-first display player when desktop shell is present; Edge/Chrome fallback in browser.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  let panels = [];
  let selectedId = null;
  let catalogTools = {};

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

  function isTauriShell() {
    return !!(window.__TAURI__?.core?.invoke || window.__TAURI_INTERNALS__?.invoke);
  }

  function tauriInvoke() {
    return window.__TAURI__?.core?.invoke || window.__TAURI_INTERNALS__?.invoke || null;
  }

  async function probeJsonHeaders() {
    if (window.PcLabProbeAuth) {
      await window.PcLabProbeAuth.ensure();
      return window.PcLabProbeAuth.jsonHeaders();
    }
    return { 'Content-Type': 'application/json' };
  }

  function selectedPanel() {
    return panels.find((p) => p.id === selectedId) || null;
  }

  function setStatus(html, cls) {
    const st = el('dx-lcd-studio-status');
    if (!st) return;
    st.className = 'dx-lcd-status fs-sm ' + (cls || 'muted');
    st.innerHTML = html;
  }

  function transportBadge(t) {
    const tone =
      t === 'windows_display' ? 'disp' : t === 'liquidctl' ? 'hid' : t === 'openrgb' ? 'og' : 'stage';
    return `<span class="dx-lcd-badge dx-lcd-badge--${tone}">${esc(t)}</span>`;
  }

  function shapeBadge(shape) {
    return `<span class="dx-lcd-badge dx-lcd-badge--shape">${esc(shape || 'rect')}</span>`;
  }

  function mediaBadge(p) {
    const caps = p.capabilities || {};
    if (p.transport === 'windows_display' && caps.video) {
      return '<span class="dx-lcd-badge">video</span>';
    }
    if (p.transport === 'stage_only') {
      return '<span class="dx-lcd-badge dx-lcd-badge--stage">gif / stage</span>';
    }
    return '<span class="dx-lcd-badge">gif</span>';
  }

  function renderToolsPanel() {
    const box = el('dx-lcd-tools');
    if (!box) return;
    const tools = catalogTools || {};
    const paths = tools.paths || {};
    const missing = [];
    if (!tools.ffmpeg) missing.push('ffmpeg');
    if (!tools.liquidctl) missing.push('liquidctl');
    if (!missing.length) {
      box.hidden = true;
      box.innerHTML = '';
      return;
    }
    const ffHint = (paths.ffmpeg && paths.ffmpeg[0]) || 'agent/pclab_probe/tools/ffmpeg/ffmpeg.exe';
    const liqHint = (paths.liquidctl && paths.liquidctl[0]) || 'agent/pclab_probe/tools/liquidctl/liquidctl.exe';
    box.hidden = false;
    box.innerHTML = `<div class="dx-lcd-tools-card">
      <strong>Install tools</strong>
      <p class="muted fs-xs">${esc(paths.note || 'Drop portable binaries under agent/pclab_probe/tools/ then Rescan.')}</p>
      <ul class="dx-lcd-tools-list fs-xs">
        ${!tools.ffmpeg ? `<li><code>ffmpeg</code> → <code>${esc(ffHint)}</code> (or run <code>scripts/fetch-lcd-tools.ps1</code>)</li>` : ''}
        ${!tools.liquidctl ? `<li><code>liquidctl</code> → <code>${esc(liqHint)}</code> or <code>pip install liquidctl</code> on PATH</li>` : ''}
      </ul>
      <button type="button" class="dx-btn ghost" id="dx-lcd-tools-rescan">Rescan after install</button>
    </div>`;
    el('dx-lcd-tools-rescan')?.addEventListener('click', refreshPanels);
  }

  function renderLiquidctlPicker() {
    const wrap = el('dx-lcd-liquidctl-wrap');
    const sel = el('dx-lcd-liquidctl-match');
    if (!wrap || !sel) return;
    const p = selectedPanel();
    const devs = Array.isArray(catalogTools.liquidctl_devices) ? catalogTools.liquidctl_devices : [];
    const show = !!(p && p.transport === 'liquidctl' && catalogTools.liquidctl && devs.length > 1);
    wrap.hidden = !show;
    if (!show) return;
    const prev = sel.value;
    sel.innerHTML = devs
      .map((d) => {
        const id = d.id || d.description || 'kraken';
        const label = d.description || d.id || id;
        return `<option value="${esc(id)}">${esc(label)}</option>`;
      })
      .join('');
    if (prev && [...sel.options].some((o) => o.value === prev)) sel.value = prev;
  }

  function renderList() {
    const box = el('dx-lcd-panels');
    if (!box) return;
    if (!panels.length) {
      box.innerHTML = `<p class="muted fs-sm">No panels yet — Rescan. Secondary Windows displays and USB AIO LCDs appear here.</p>`;
      return;
    }
    box.innerHTML = panels
      .map((p) => {
        const g = p.geometry || {};
        const active = p.id === selectedId ? ' is-active' : '';
        return `<button type="button" class="dx-lcd-panel-card${active}" data-panel="${esc(p.id)}">
          <strong>${esc(p.label)}</strong>
          <span class="dx-lcd-panel-meta">${esc(p.vendor)} · ${g.w || '?'}×${g.h || '?'}</span>
          <span class="dx-lcd-panel-badges">${transportBadge(p.transport)}${shapeBadge(g.shape)}
            ${mediaBadge(p)}
            ${p.capabilities?.live_dashboard ? '<span class="dx-lcd-badge dx-lcd-badge--disp">dashboard</span>' : ''}
          </span>
        </button>`;
      })
      .join('');
    box.querySelectorAll('[data-panel]').forEach((btn) => {
      btn.addEventListener('click', () => {
        selectedId = btn.getAttribute('data-panel');
        renderList();
        updatePreviewChrome();
      });
    });
  }

  function updatePreviewChrome() {
    const p = selectedPanel();
    const prev = el('dx-lcd-preview');
    if (!prev) return;
    const shape = p?.geometry?.shape || 'rect';
    prev.classList.toggle('is-round', shape === 'round');
    const fit = el('dx-lcd-fit');
    if (fit && p?.geometry?.fit_default && !fit.dataset.touched) {
      fit.value = p.geometry.fit_default;
    }
    const note = el('dx-lcd-honesty');
    if (note) {
      const n = p?.honesty?.note || '';
      const hidHint =
        p && p.transport !== 'windows_display'
          ? ' HID path is GIF-oriented; long video needs a Windows display panel.'
          : '';
      note.textContent = n ? n + hidHint : '';
    }
    const dashBtn = el('dx-lcd-dashboard');
    if (dashBtn) {
      const ok = !!(p && p.transport === 'windows_display' && p.capabilities?.live_dashboard);
      dashBtn.disabled = !ok;
      dashBtn.title = ok ? 'Live telemetry on this display' : 'Dashboard is Windows-display only';
    }
    const file = el('dx-lcd-file');
    if (file && p) {
      if (p.transport === 'windows_display') {
        file.setAttribute('accept', 'image/gif,video/mp4,video/webm,.gif,.mp4,.webm,.mov');
      } else {
        file.setAttribute('accept', 'image/gif,.gif,video/mp4,video/webm,.mp4,.webm');
      }
    }
    renderLiquidctlPicker();
  }

  async function refreshPanels() {
    setStatus('Scanning panels…', 'muted');
    try {
      const res = await fetch(AGENT() + '/lcd/panels', { mode: 'cors' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      panels = data.panels || [];
      catalogTools = data.tools || {};
      window.__dxLcdPanels = data;
      if (!selectedId && panels.length) {
        const secondary = panels.find((p) => p.transport === 'windows_display' && !p.primary);
        selectedId = (secondary || panels[0]).id;
      }
      renderList();
      updatePreviewChrome();
      renderToolsPanel();
      const tools = catalogTools;
      const liqN = Array.isArray(tools.liquidctl_devices) ? tools.liquidctl_devices.length : 0;
      setStatus(
        `${panels.length} panels · ffmpeg ${tools.ffmpeg ? 'yes' : 'no'} · liquidctl ${tools.liquidctl ? 'yes' : 'no'}${liqN ? ` (${liqN})` : ''} · OpenRGB ${tools.openrgb ? 'yes' : 'no'} · player ${isTauriShell() ? 'Tauri' : 'browser'}`,
        'muted'
      );
    } catch (e) {
      setStatus(esc(e.message || e), 'warn');
    }
  }

  async function fileToBase64(file) {
    const buf = await file.arrayBuffer();
    const bytes = new Uint8Array(buf);
    let binary = '';
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
  }

  function previewFile(file) {
    const prev = el('dx-lcd-preview');
    if (!prev || !file) return;
    prev.innerHTML = '';
    const url = URL.createObjectURL(file);
    if (file.type.startsWith('video/') || /\.(mp4|webm|mov)$/i.test(file.name)) {
      const v = document.createElement('video');
      v.src = url;
      v.autoplay = true;
      v.loop = true;
      v.muted = true;
      v.playsInline = true;
      prev.appendChild(v);
    } else {
      const img = document.createElement('img');
      img.src = url;
      img.alt = 'LCD preview';
      prev.appendChild(img);
    }
  }

  async function openTauriPlayer(data) {
    const invoke = tauriInvoke();
    if (!invoke) return false;
    const play = data.play || {};
    const url = data.player_url || play.player_url || data.player_html || play.player_html || play.html;
    if (!url) return false;
    const b = play.bounds || data.bounds || {};
    await invoke('lcd_open_player', {
      args: {
        url,
        label: 'lcd-player',
        x: b.x ?? 0,
        y: b.y ?? 0,
        width: b.width ?? 800,
        height: b.height ?? 600,
        title: 'PC Lab Kit LCD',
      },
    });
    return true;
  }

  async function applyMedia(opts = {}) {
    const p = selectedPanel();
    if (!p) {
      setStatus('Select a panel first.', 'warn');
      return;
    }
    const input = el('dx-lcd-file');
    const file = input?.files?.[0];
    const mode = opts.mode || 'media';
    if (mode === 'dashboard' && p.transport !== 'windows_display') {
      setStatus('Live dashboard is Windows-display only.', 'warn');
      return;
    }
    if (mode === 'media' && !file) {
      setStatus('Choose a GIF, MP4, or WebM file.', 'warn');
      return;
    }
    if (mode === 'media' && p.transport !== 'windows_display' && file && /\.(mp4|webm|mov)$/i.test(file.name) && !catalogTools.ffmpeg) {
      setStatus('HID panels need GIF (or install tools/ffmpeg for auto video→GIF).', 'warn');
      return;
    }
    const fit = el('dx-lcd-fit')?.value || 'fit';
    const preferTauri = isTauriShell() && (p.transport === 'windows_display' || mode === 'dashboard' || opts.forcePlay);
    setStatus(mode === 'dashboard' ? 'Opening live dashboard…' : 'Fitting & applying…', 'muted');
    try {
      const payload = {
        panel_id: p.id,
        fit_mode: fit,
        mode,
        play_display: p.transport === 'windows_display' || !!opts.forcePlay,
        display_index: p.display_index != null ? p.display_index : undefined,
        openrgb_index: p.openrgb_index != null ? p.openrgb_index : undefined,
        skip_browser: preferTauri,
        prefer_tauri: preferTauri,
      };
      const liqSel = el('dx-lcd-liquidctl-match');
      if (p.transport === 'liquidctl' && liqSel && !liqSel.closest('[hidden]') && liqSel.value) {
        payload.liquidctl_match = liqSel.value;
      } else if (p.transport === 'liquidctl') {
        payload.liquidctl_match = 'kraken';
      }
      if (file && mode === 'media') {
        payload.file_name = file.name;
        payload.media_base64 = await fileToBase64(file);
      }
      const res = await fetch(AGENT() + '/lcd/apply', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify(payload),
      });
      const data = await res.json().catch(() => ({}));
      if (!data.ok) {
        setStatus(esc(data.message || data.error || 'Apply failed'), 'warn');
        return;
      }
      let tauriOk = false;
      if (preferTauri && (data.player_ready || data.player_url || data.play?.html)) {
        try {
          tauriOk = await openTauriPlayer(data);
        } catch (err) {
          setStatus(esc('Tauri player failed: ' + (err.message || err)), 'warn');
        }
      }
      let cls = 'warn';
      if (data.pushed || data.played_on_display || tauriOk) cls = 'ok';
      const bits = [
        data.pushed ? 'HID pushed' : null,
        tauriOk ? 'playing on display (Tauri)' : data.played_on_display ? 'playing on display' : null,
        data.player_ready && !tauriOk && !data.played_on_display ? 'player HTML ready' : null,
        data.transcoded ? 'transcoded' : null,
        data.ffmpeg_missing ? 'ffmpeg missing' : null,
        data.circular_alpha ? 'circular alpha' : null,
        data.transport ? `transport=${data.transport}` : null,
      ].filter(Boolean);
      setStatus(`<strong>${esc(data.message || 'Done')}</strong><br>${esc(bits.join(' · '))}`, cls);
    } catch (e) {
      setStatus(esc(e.message || e), 'warn');
    }
  }

  async function stopPlayer() {
    try {
      await fetch(AGENT() + '/lcd/stop', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: '{}',
      });
      try {
        const invoke = tauriInvoke();
        if (invoke) await invoke('lcd_close_player', { label: 'lcd-player' });
      } catch (_) {}
      setStatus('LCD player stopped.', 'ok');
    } catch (e) {
      setStatus(esc(e.message || e), 'warn');
    }
  }

  function bind() {
    if (!el('dx-lcd-studio')) return;
    el('dx-lcd-refresh')?.addEventListener('click', refreshPanels);
    el('dx-lcd-apply')?.addEventListener('click', () => applyMedia({ mode: 'media' }));
    el('dx-lcd-dashboard')?.addEventListener('click', () => applyMedia({ mode: 'dashboard', forcePlay: true }));
    el('dx-lcd-stop')?.addEventListener('click', stopPlayer);
    el('dx-lcd-fit')?.addEventListener('change', (e) => {
      e.target.dataset.touched = '1';
    });
    el('dx-lcd-file')?.addEventListener('change', (e) => {
      const f = e.target.files?.[0];
      if (f) previewFile(f);
    });
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'advanced' || ev.detail?.tab === 'command') refreshPanels();
    });
    refreshPanels();
  }

  window.PcLabLcdStudio = { refresh: refreshPanels, apply: applyMedia, stop: stopPlayer };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind);
  else bind();
})();
