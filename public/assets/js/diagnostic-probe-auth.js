/**
 * Same-origin probe token bootstrap (PHP session). Never from /health.
 */
(function () {
  const LS_AUTH = 'pclab_probe_auth_token';
  let cached = '';
  let inflight = null;

  try {
    cached = localStorage.getItem(LS_AUTH) || '';
  } catch (_) {}

  function token() {
    return cached || '';
  }

  function headers(extra) {
    const h = Object.assign({}, extra || {});
    if (cached) h['X-PcLab-Token'] = cached;
    return h;
  }

  function jsonHeaders() {
    return headers({ 'Content-Type': 'application/json' });
  }

  async function ensure() {
    if (cached) return cached;
    if (inflight) return inflight;
    inflight = (async () => {
      try {
        const res = await fetch('/api/diagnostic/probe-auth', {
          credentials: 'same-origin',
          headers: { Accept: 'application/json' },
        });
        if (!res.ok) return '';
        const data = await res.json().catch(() => ({}));
        if (data && data.token) {
          cached = String(data.token);
          try {
            localStorage.setItem(LS_AUTH, cached);
          } catch (_) {}
        }
      } catch (_) {
        /* probe auth optional until probe is up */
      } finally {
        inflight = null;
      }
      return cached;
    })();
    return inflight;
  }

  function clear() {
    cached = '';
    try {
      localStorage.removeItem(LS_AUTH);
    } catch (_) {}
  }

  window.PcLabProbeAuth = { ensure, token, headers, jsonHeaders, clear };

  window.PcLabCsrf = {
    headers(extra) {
      const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
      return Object.assign({ 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t }, extra || {});
    },
  };
})();
