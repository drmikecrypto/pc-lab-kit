(function () {
  const buttons = document.querySelectorAll('[data-dx-tab]');
  const panels = document.querySelectorAll('[data-dx-panel]');

  function activate(tab) {
    buttons.forEach((btn) => {
      const on = btn.getAttribute('data-dx-tab') === tab;
      btn.classList.toggle('is-active', on);
      btn.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    panels.forEach((panel) => {
      const on = panel.getAttribute('data-dx-panel') === tab;
      panel.classList.toggle('is-active', on);
      panel.hidden = !on;
    });
    document.querySelectorAll('[data-dx-nav]').forEach((btn) => {
      const on = btn.getAttribute('data-dx-nav') === tab;
      btn.classList.toggle('is-active', on);
      btn.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    const hashByTab = {
      command: 'dx-command-center',
      quick: 'dx-wizard',
      full: 'dx-full-scan',
      arena: 'dx-arena',
      toolkit: 'dx-toolkit',
      history: 'dx-live-lab',
      advanced: 'dx-telemetry',
      hardware: 'dx-hardware-ref',
      openbook: 'dx-openbook-lab',
    };
    if (history.replaceState && hashByTab[tab]) {
      history.replaceState(null, '', '#' + hashByTab[tab]);
    }
    window.dispatchEvent(new CustomEvent('dx:tab-change', { detail: { tab } }));
  }

  window.dxActivateTab = activate;

  buttons.forEach((btn) => {
    btn.addEventListener('click', () => activate(btn.getAttribute('data-dx-tab')));
  });

  document.querySelectorAll('[data-dx-nav]').forEach((btn) => {
    btn.addEventListener('click', () => activate(btn.getAttribute('data-dx-nav')));
  });

  const hash = (location.hash || '').replace('#', '');
  const map = {
    'dx-command-center': 'command',
    'dx-quick': 'quick',
    'dx-wizard': 'quick',
    'dx-full-scan': 'full',
    'dx-arena': 'arena',
    'dx-toolkit': 'toolkit',
    'dx-live-lab': 'history',
    'dx-history': 'history',
    'dx-telemetry': 'advanced',
    'dx-rgb-lab': 'advanced',
    'dx-hardware-ref': 'hardware',
    'dx-openbook-lab': 'openbook',
  };
  activate(map[hash] || 'command');

  window.addEventListener('hashchange', () => {
    const h = (location.hash || '').replace('#', '');
    if (map[h]) activate(map[h]);
  });
})();
