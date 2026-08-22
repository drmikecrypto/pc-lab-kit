/**
 * Command Center 2.0 — left nav sync + live canvas twin + advisor rail mirror.
 */
(function () {
  const NAV_MAP = {
    command: 'command',
    quick: 'quick',
    hardware: 'hardware',
    openbook: 'openbook',
    drivers: 'drivers',
    stress: 'stress',
    full: 'full',
    arena: 'arena',
    toolkit: 'toolkit',
    history: 'history',
    advanced: 'advanced',
  };

  function syncNav(tab) {
    document.querySelectorAll('[data-dx-nav]').forEach((btn) => {
      const on = btn.getAttribute('data-dx-nav') === tab;
      btn.classList.toggle('is-active', on);
      btn.setAttribute('aria-selected', on ? 'true' : 'false');
    });
  }

  function mirrorAdvisorCards() {
    const src = document.getElementById('dx-advisor-cards');
    const rail = document.getElementById('dx-rail-advisor');
    const empty = document.getElementById('dx-rail-empty');
    if (!src || !rail) return;

    function sync() {
      const hasCards = !src.hidden && src.innerHTML.trim() !== '';
      rail.innerHTML = src.innerHTML;
      rail.hidden = !hasCards;
      if (empty) empty.hidden = hasCards;
    }

    const obs = new MutationObserver(sync);
    obs.observe(src, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden'] });
    sync();
  }

  async function initTwinPreview() {
    const root = document.getElementById('dx-lab-twin-preview');
    if (!root || !window.PcLabTopology3d) return;
    try {
      const r = await fetch('/api/diagnostic/topology', {
        method: 'POST',
        headers: (window.PcLabCsrf && window.PcLabCsrf.headers()) || {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: '{}',
      });
      if (!r.ok) return;
      const data = await r.json();
      window.PcLabTopology3d.render(root, data);
    } catch (_) {}
  }

  window.addEventListener('dx:tab-change', (ev) => {
    const tab = ev.detail?.tab;
    if (tab) syncNav(tab);
  });

  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('[data-dx-nav]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const tab = btn.getAttribute('data-dx-nav');
        if (!tab) return;
        const legacy = document.querySelector(`[data-dx-tab="${tab}"]`);
        if (legacy) legacy.click();
        else if (window.dxActivateTab) window.dxActivateTab(tab);
      });
    });
    mirrorAdvisorCards();
    setTimeout(initTwinPreview, 800);
  });
})();
