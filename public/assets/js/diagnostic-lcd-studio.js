/**
 * LCD Studio — universal AIO / case panel media (GIF + longer video).
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  let panels = [];
  let selectedId = null;

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
        const caps = p.capabilities || {};
        return `<button type="button" class="dx-lcd-panel-card${active}" data-panel="${esc(p.id)}">
          <strong>${esc(p.label)}</strong>
          <span class="dx-lcd-panel-meta">${esc(p.vendor)} · ${g.w || '?'}×${g.h || '?'}</span>
          <span class="dx-lcd-panel-badges">${transportBadge(p.transport)}${shapeBadge(g.shape)}
            ${caps.video ? '<span class="dx-lcd-badge">video</span>' : '<span class="dx-lcd-badge">gif</span>'}
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
  }

  async function refreshPanels() {
    setStatus('Scanning panels…', 'muted');
    try {
      const res = await fetch(AGENT() + '/lcd/panels', { mode: 'cors' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      panels = data.panels || [];
      window.__dxLcdPanels = data;
      if (!selectedId && panels.length) {
        const secondary = panels.find((p) => p.transport === 'windows_display' && !p.primary);
        selectedId = (secondary || panels[0]).id;
      }
      renderList();
      updatePreviewChrome();
      const tools = data.tools || {};
      setStatus(
        `${panels.length} panels · ffmpeg ${tools.ffmpeg ? 'yes' : 'no'} · liquidctl ${tools.liquidctl ? 'yes' : 'no'} · OpenRGB ${tools.openrgb ? 'yes' : 'no'}`,
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

  async function tryTauriPlayer(play) {
    if (!play?.played_on_display) return;
    try {
      const invoke = window.__TAURI__?.core?.invoke || window.__TAURI_INTERNALS__?.invoke;
      if (!invoke) return;
      const b = play.bounds || {};
      const html = play.html || null;
      // Probe already launched Edge; Tauri can also open if we have local html path
      if (html) {
        await invoke('lcd_open_player', {
          args: {
            url: html,
            x: b.x,
            y: b.y,
            width: b.width,
            height: b.height,
            title: 'PC Lab Kit LCD',
          },
        });
      }
    } catch (_) {
      /* probe Edge player is primary */
    }
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
    if (mode === 'media' && !file) {
      setStatus('Choose a GIF, MP4, or WebM file.', 'warn');
      return;
    }
    const fit = el('dx-lcd-fit')?.value || 'fit';
    setStatus(mode === 'dashboard' ? 'Opening live dashboard…' : 'Fitting & applying…', 'muted');
    try {
      const payload = {
        panel_id: p.id,
        fit_mode: fit,
        mode,
        play_display: p.transport === 'windows_display' || !!opts.forcePlay,
        display_index: p.display_index != null ? p.display_index : undefined,
        openrgb_index: p.openrgb_index != null ? p.openrgb_index : undefined,
      };
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
      let cls = 'warn';
      if (data.pushed || data.played_on_display) cls = 'ok';
      const bits = [
        data.pushed ? 'HID pushed' : null,
        data.played_on_display ? 'playing on display' : null,
        data.transcoded ? 'transcoded' : null,
        data.transport ? `transport=${data.transport}` : null,
      ].filter(Boolean);
      setStatus(`<strong>${esc(data.message || 'Done')}</strong><br>${esc(bits.join(' · '))}`, cls);
      await tryTauriPlayer(data.play);
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
        const invoke = window.__TAURI__?.core?.invoke;
        if (invoke) await invoke('lcd_close_player', { label: null });
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
