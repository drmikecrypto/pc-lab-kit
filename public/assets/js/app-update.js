(function () {
  const DISMISS_KEY = 'pclab_update_dismiss';
  const banner = document.getElementById('pclab-update-banner');
  const navBtn = document.getElementById('pclab-update-btn');
  let lastData = null;

  function esc(s) {
    const d = document.createElement('div');
    d.textContent = s ?? '';
    return d.innerHTML;
  }

  function platformDownload(data) {
    const ua = navigator.userAgent || '';
    if (/linux/i.test(ua) && data.download_linux) return data.download_linux;
    if (/windows/i.test(ua) && data.download_windows) return data.download_windows;
    return data.release_url || 'https://github.com/drmikecrypto/pc-lab-kit/releases/latest';
  }

  function isDismissed(version) {
    return (localStorage.getItem(DISMISS_KEY) || '') === String(version || '');
  }

  function clearDismiss() {
    localStorage.removeItem(DISMISS_KEY);
  }

  function hideUpdateUi() {
    if (banner) {
      banner.hidden = true;
      banner.innerHTML = '';
    }
    if (navBtn) navBtn.hidden = true;
  }

  function showNavButton(show) {
    if (!navBtn) return;
    navBtn.hidden = !show;
  }

  /** Open download/release URLs outside the lab webview (Tauri blocks target=_blank). */
  async function openExternal(url) {
    const href = String(url || '').trim();
    if (!href) return false;
    try {
      const openUrl = window.__TAURI__?.opener?.openUrl;
      if (typeof openUrl === 'function') {
        await openUrl(href);
        return true;
      }
    } catch (err) {
      console.error('[PcLabUpdate] opener.openUrl failed', err);
    }
    try {
      const invoke =
        window.__TAURI__?.core?.invoke ||
        window.__TAURI_INTERNALS__?.invoke ||
        null;
      if (typeof invoke === 'function') {
        await invoke('plugin:opener|open_url', { url: href });
        return true;
      }
    } catch (err) {
      console.error('[PcLabUpdate] plugin:opener|open_url failed', err);
    }
    try {
      const w = window.open(href, '_blank', 'noopener,noreferrer');
      if (w) return true;
    } catch (_) {}
    try {
      const a = document.createElement('a');
      a.href = href;
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
      document.body.appendChild(a);
      a.click();
      a.remove();
      return true;
    } catch (err) {
      console.error('[PcLabUpdate] fallback open failed', err);
      return false;
    }
  }

  function wireExternalLinks(root) {
    root?.querySelectorAll('a[data-pclab-external]')?.forEach((a) => {
      a.addEventListener('click', (e) => {
        e.preventDefault();
        openExternal(a.getAttribute('href') || '');
      });
    });
  }

  function applyUpdateUi(data, opts) {
    opts = opts || {};
    lastData = data;
    const forceShow = !!opts.forceShow;
    const available = !!(data && data.update_available);
    const version = data?.latest_version || '';

    if (!available) {
      hideUpdateUi();
      return { shown: false, available: false };
    }

    const dismissed = isDismissed(version) && !forceShow;
    showNavButton(true);

    if (dismissed || !banner) {
      if (banner) {
        banner.hidden = true;
        banner.innerHTML = '';
      }
      return { shown: false, available: true, dismissed: true };
    }

    const href = platformDownload(data);
    banner.hidden = false;
    banner.innerHTML = `
      <div class="pclab-update-inner">
        <div>
          <strong>Update available</strong>
          <span class="muted fs-sm">PC Lab Kit ${esc(data.current_version)} → ${esc(data.latest_version)}</span>
          ${data.release_notes ? `<p class="fs-xs muted m-0 mt-1">${esc(data.release_notes.split('\n')[0])}</p>` : ''}
        </div>
        <div class="pclab-update-actions">
          <a href="${esc(href)}" class="dx-btn primary" data-pclab-external id="pclab-update-download">Download update</a>
          <a href="${esc(data.release_url || 'https://github.com/drmikecrypto/pc-lab-kit/releases')}" class="dx-btn ghost" data-pclab-external>Release notes</a>
          <button type="button" class="dx-btn ghost" id="pclab-update-dismiss">Not now</button>
        </div>
      </div>`;

    wireExternalLinks(banner);

    document.getElementById('pclab-update-dismiss')?.addEventListener('click', () => {
      localStorage.setItem(DISMISS_KEY, version);
      if (banner) {
        banner.hidden = true;
        banner.innerHTML = '';
      }
      showNavButton(true);
    });

    return { shown: true, available: true };
  }

  async function focusUpdateUi() {
    const data = await checkUpdate({ force: true });
    if (!data?.update_available) {
      if (banner) {
        banner.hidden = false;
        banner.innerHTML = `
          <div class="pclab-update-inner">
            <div>
              <strong>You are up to date</strong>
              <span class="muted fs-sm">PC Lab Kit ${esc(data?.current_version || '')}</span>
            </div>
            <div class="pclab-update-actions">
              <button type="button" class="dx-btn ghost" id="pclab-update-ok">OK</button>
            </div>
          </div>`;
        document.getElementById('pclab-update-ok')?.addEventListener('click', () => {
          banner.hidden = true;
          banner.innerHTML = '';
        });
      }
      return;
    }

    clearDismiss();
    applyUpdateUi(data, { forceShow: true });
    banner?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    const opened = await openExternal(platformDownload(data));
    if (!opened) {
      document.getElementById('pclab-update-download')?.focus();
    }
  }

  async function checkUpdate(options) {
    options = options || {};
    const force = !!options.force;
    const url = force ? '/api/app/update?refresh=1' : '/api/app/update';
    try {
      const res = await fetch(url);
      if (!res.ok) {
        return { ok: false, message: 'Update check failed (' + res.status + ').' };
      }
      const data = await res.json();
      if (force && data.update_available) {
        clearDismiss();
      }
      if (data.ok === false && !data.update_available) {
        hideUpdateUi();
        return data;
      }
      applyUpdateUi(data, { forceShow: force && !!data.update_available });
      return data;
    } catch (err) {
      hideUpdateUi();
      return { ok: false, message: 'Could not reach the update service.' };
    }
  }

  navBtn?.addEventListener('click', () => {
    focusUpdateUi().catch((err) => console.error('[PcLabUpdate]', err));
  });

  window.pclabCheckForUpdates = checkUpdate;
  window.pclabClearUpdateDismiss = clearDismiss;
  window.pclabOpenExternal = openExternal;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => checkUpdate({ force: true }));
  } else {
    checkUpdate({ force: true });
  }
})();
