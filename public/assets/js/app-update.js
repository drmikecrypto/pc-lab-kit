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
    return data.release_url || '/download';
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
          <a href="${esc(href)}" class="dx-btn primary" target="_blank" rel="noopener" id="pclab-update-download">Download update</a>
          <a href="${esc(data.release_url || 'https://github.com/drmikecrypto/pc-lab-kit/releases')}" class="dx-btn ghost" target="_blank" rel="noopener">Release notes</a>
          <button type="button" class="dx-btn ghost" id="pclab-update-dismiss">Not now</button>
        </div>
      </div>`;

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

  function focusUpdateUi() {
    if (!lastData?.update_available) return;
    if (banner && !banner.hidden) {
      banner.scrollIntoView({ behavior: 'smooth', block: 'start' });
      document.getElementById('pclab-update-download')?.focus();
      return;
    }
    // Banner was dismissed — re-show it and offer download.
    clearDismiss();
    applyUpdateUi(lastData, { forceShow: true });
    banner?.scrollIntoView({ behavior: 'smooth', block: 'start' });
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

  navBtn?.addEventListener('click', focusUpdateUi);

  window.pclabCheckForUpdates = checkUpdate;
  window.pclabClearUpdateDismiss = clearDismiss;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => checkUpdate());
  } else {
    checkUpdate();
  }
})();
