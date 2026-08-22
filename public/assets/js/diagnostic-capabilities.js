/**
 * Soft-degrade lab UI from probe /health capabilities (Windows vs Linux).
 */
(function () {
  const cfg = window.PCLAB_DIAGNOSTIC || {};
  const AGENT = (cfg.agentBase || '').replace(/\/+$/, '') || 'http://127.0.0.1:18765';

  const DEFAULTS = {
    ok: false,
    platform: 'unknown',
    elevated: false,
    devices: true,
    drivers: true,
    suite: true,
    open_book: true,
    audit: true,
    oc: true,
    rgb: true,
    launchers: true,
    vkbench: true,
  };

  window.PCLAB_PROBE_CAPS = Object.assign({}, DEFAULTS);

  function applyCaps(health) {
    const caps = Object.assign({}, DEFAULTS, health || {});
    caps.ok = !!(health && (health.ok !== false));
    window.PCLAB_PROBE_CAPS = caps;
    window.dispatchEvent(new CustomEvent('pclab:probe-caps', { detail: caps }));

    const isLinux = String(caps.platform || '').toLowerCase() === 'linux';
    document.documentElement.dataset.probePlatform = caps.platform || 'unknown';
    document.documentElement.dataset.probeOk = caps.ok ? '1' : '0';

    // Soft-hide Windows-only surfaces when Linux probe reports them unavailable
    const winOnly = [
      { sel: '#dx-rgb-lab, [data-dx-goto="rgb"], [href="#dx-rgb-lab"], [data-dx-panel="rgb"]', on: caps.rgb !== false },
      { sel: '[data-dx-panel="oc"], #dx-oc-lab, [href="#dx-oc-lab"], [data-dx-goto="oc"]', on: caps.oc !== false },
      { sel: '#dx-launchers, [data-dx-goto="launchers"], [data-dx-panel="launchers"]', on: caps.launchers !== false },
    ];
    winOnly.forEach(({ sel, on }) => {
      document.querySelectorAll(sel).forEach((node) => {
        if (!(node instanceof HTMLElement)) return;
        if (!on) {
          node.setAttribute('hidden', '');
          node.setAttribute('aria-disabled', 'true');
          if ('disabled' in node) node.disabled = true;
        } else {
          node.removeAttribute('hidden');
          node.removeAttribute('aria-disabled');
          if ('disabled' in node) node.disabled = false;
        }
      });
    });

    if (!caps.ok && !caps.platform) {
      document.documentElement.dataset.probePlatform = 'offline';
    }

    // Prefer Linux probe download when health says linux
    if (isLinux && cfg.appDownload && cfg.appDownload.linux) {
      document.querySelectorAll('a.dx-full-dl-main, a.dx-full-dl').forEach((a) => {
        if (a instanceof HTMLAnchorElement) {
          a.href = cfg.appDownload.linux;
          if (a.textContent && /probe/i.test(a.textContent)) {
            a.textContent = a.textContent.replace(/PcLab Probe/i, 'PcLab Probe Linux');
          }
        }
      });
    }

    // Drivers: note manual install on Linux
    const note = document.getElementById('dx-driver-linux-note');
    if (isLinux) {
      let el = note;
      if (!el) {
        const host = document.getElementById('dx-drivers-lab') || document.querySelector('[data-dx-panel="drivers"]');
        if (host) {
          el = document.createElement('p');
          el.id = 'dx-driver-linux-note';
          el.className = 'muted fs-sm';
          el.style.margin = '0.75rem 0';
          host.prepend(el);
        }
      }
      if (el) {
        el.hidden = false;
        el.textContent =
          'Linux probe: driver action plan lists distro packages — install via apt/dnf/pacman. One-click install is Windows-only.';
      }
    } else if (note) {
      note.hidden = true;
    }

    // Open Book honesty banner
    let ob = document.getElementById('dx-openbook-linux-note');
    if (isLinux) {
      if (!ob) {
        const host = document.getElementById('dx-openbook-lab') || document.querySelector('[data-dx-panel="openbook"]');
        if (host) {
          ob = document.createElement('p');
          ob.id = 'dx-openbook-linux-note';
          ob.className = 'muted fs-sm';
          host.prepend(ob);
        }
      }
      if (ob) {
        ob.hidden = false;
        ob.textContent =
          'Linux Open Book uses hwmon/sysfs (no Ring0 BAR0 MMIO). Coverage and adaptive plan still match the Windows audit shape.';
      }
    } else if (ob) {
      ob.hidden = true;
    }
  }

  async function poll() {
    try {
      const ctrl = new AbortController();
      const t = setTimeout(() => ctrl.abort(), 3500);
      const res = await fetch(AGENT + '/health', { mode: 'cors', signal: ctrl.signal });
      clearTimeout(t);
      if (!res.ok) {
        applyCaps({ ok: false });
        return;
      }
      const data = await res.json().catch(() => ({}));
      applyCaps(Object.assign({ ok: true }, data));
    } catch (_) {
      applyCaps({ ok: false });
    }
  }

  window.PcLabProbeCaps = { poll, apply: applyCaps, get: () => window.PCLAB_PROBE_CAPS };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      poll();
      setInterval(poll, 15000);
    });
  } else {
    poll();
    setInterval(poll, 15000);
  }
})();
