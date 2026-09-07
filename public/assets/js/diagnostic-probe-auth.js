/**
 * Same-origin probe token bootstrap (PHP session). Never from /health.
 * In-memory only — no localStorage (XSS / shared-profile residual).
 */
(function () {
  const LEGACY_LS = 'pclab_probe_auth_token';
  let cached = '';
  let fetchedAt = 0;
  let inflight = null;
  const TTL_MS = 30 * 60 * 1000;

  // Drop any legacy persisted token from earlier builds
  try {
    localStorage.removeItem(LEGACY_LS);
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

  function isFresh() {
    return !!cached && Date.now() - fetchedAt < TTL_MS;
  }

  async function ensure(force) {
    if (!force && isFresh()) return cached;
    if (inflight) return inflight;
    inflight = (async () => {
      try {
        const res = await fetch('/api/diagnostic/probe-auth', {
          credentials: 'same-origin',
          headers: { Accept: 'application/json' },
        });
        if (!res.ok) return cached || '';
        const data = await res.json().catch(() => ({}));
        if (data && data.token) {
          cached = String(data.token);
          fetchedAt = Date.now();
        }
      } catch (_) {
        /* probe auth optional until lab is up */
      } finally {
        inflight = null;
      }
      return cached;
    })();
    return inflight;
  }

  function clear() {
    cached = '';
    fetchedAt = 0;
    try {
      localStorage.removeItem(LEGACY_LS);
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
