(function () {
  const DISMISS_KEY = 'pcverse_update_dismiss';
  const banner = document.getElementById('pcverse-update-banner');

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

  async function checkUpdate() {
    if (!banner) return;
    try {
      const dismissed = localStorage.getItem(DISMISS_KEY) || '';
      const res = await fetch('/api/app/update');
      if (!res.ok) return;
      const data = await res.json();
      if (!data.update_available) return;
      if (dismissed === data.latest_version) return;

      const href = platformDownload(data);
      banner.hidden = false;
      banner.innerHTML = `
        <div class="pcverse-update-inner">
          <div>
            <strong>Update available</strong>
            <span class="muted fs-sm">PCVerse ${esc(data.current_version)} → ${esc(data.latest_version)}</span>
            ${data.release_notes ? `<p class="fs-xs muted m-0 mt-1">${esc(data.release_notes.split('\n')[0])}</p>` : ''}
          </div>
          <div class="pcverse-update-actions">
            <a href="${esc(href)}" class="dx-btn primary" target="_blank" rel="noopener">Download update</a>
            <a href="${esc(data.release_url || 'https://github.com/drmikecrypto')}" class="dx-btn ghost" target="_blank" rel="noopener">Release notes</a>
            <button type="button" class="dx-btn ghost" id="pcverse-update-dismiss">Not now</button>
          </div>
        </div>`;

      document.getElementById('pcverse-update-dismiss')?.addEventListener('click', () => {
        localStorage.setItem(DISMISS_KEY, data.latest_version);
        banner.hidden = true;
      });
    } catch (_) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', checkUpdate);
  } else {
    checkUpdate();
  }
})();
