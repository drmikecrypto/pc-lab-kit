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
    const hashByTab = {
      quick: 'dx-wizard',
      full: 'dx-full-scan',
      toolkit: 'dx-toolkit',
      history: 'dx-live-lab',
      advanced: 'dx-telemetry',
    };
    if (history.replaceState && hashByTab[tab]) {
      history.replaceState(null, '', '#' + hashByTab[tab]);
    }
  }

  buttons.forEach((btn) => {
    btn.addEventListener('click', () => activate(btn.getAttribute('data-dx-tab')));
  });

  const hash = (location.hash || '').replace('#', '');
  const map = {
    'dx-quick': 'quick',
    'dx-wizard': 'quick',
    'dx-full-scan': 'full',
    'dx-toolkit': 'toolkit',
    'dx-live-lab': 'history',
    'dx-history': 'history',
    'dx-telemetry': 'advanced',
    'dx-rgb-lab': 'advanced',
  };
  activate(map[hash] || 'quick');

  window.addEventListener('hashchange', () => {
    const h = (location.hash || '').replace('#', '');
    if (map[h]) activate(map[h]);
  });
})();
