(function () {
  const overlay = document.getElementById('dx-settings');
  const form = document.getElementById('dx-settings-form');
  if (!overlay || !form) return;

  const openBtn = document.getElementById('dx-settings-open');
  const closeBtn = document.getElementById('dx-settings-close');
  const clearBtn = document.getElementById('dx-settings-clear-key');
  const keyInput = document.getElementById('dx-settings-key');
  const baseInput = document.getElementById('dx-settings-base');
  const modelInput = document.getElementById('dx-settings-model');
  const hintEl = document.getElementById('dx-settings-key-hint');
  const statusEl = document.getElementById('dx-settings-status');

  function csrfHeaders() {
    const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    return { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t };
  }

  function open() {
    overlay.hidden = false;
    overlay.removeAttribute('aria-hidden');
    load();
    keyInput?.focus();
  }

  function close() {
    overlay.hidden = true;
    overlay.setAttribute('aria-hidden', 'true');
    if (statusEl) statusEl.textContent = '';
  }

  async function load() {
    try {
      const res = await fetch('/api/settings');
      if (!res.ok) throw new Error('load failed');
      const data = await res.json();
      if (baseInput) baseInput.value = data.llm_base_url || '';
      if (modelInput) modelInput.value = data.llm_model || '';
      if (hintEl) {
        if (data.api_key_hint) {
          hintEl.textContent = 'Saved key: ' + data.api_key_hint + (data.source === 'env' ? ' (from .env — overrides local file)' : '');
        } else {
          hintEl.textContent = 'No API key saved yet.';
        }
      }
      window.PCVERSE_SETTINGS = data;
    } catch (_) {
      if (statusEl) statusEl.textContent = 'Could not load settings.';
    }
  }

  async function save(clearKey) {
    if (statusEl) statusEl.textContent = 'Saving…';
    const body = {
      llm_base_url: baseInput?.value.trim() || '',
      llm_model: modelInput?.value.trim() || '',
    };
    if (clearKey) {
      body.clear_api_key = true;
    } else if (keyInput?.value.trim()) {
      body.llm_api_key = keyInput.value.trim();
    }
    try {
      const res = await fetch('/api/settings', {
        method: 'POST',
        headers: csrfHeaders(),
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok || data.ok === false) throw new Error('save failed');
      if (keyInput) keyInput.value = '';
      if (statusEl) statusEl.textContent = data.ai_configured ? 'Saved — AI advisor enabled.' : 'Saved — rule-based analysis only.';
      if (hintEl) {
        hintEl.textContent = data.api_key_hint
          ? 'Saved key: ' + data.api_key_hint + (data.source === 'env' ? ' (from .env)' : '')
          : 'No API key saved.';
      }
      window.PCVERSE_SETTINGS = data;
      window.dispatchEvent(new CustomEvent('pcverse:settings-updated', { detail: data }));
    } catch (_) {
      if (statusEl) statusEl.textContent = 'Could not save settings. Try again.';
    }
  }

  openBtn?.addEventListener('click', open);
  document.getElementById('dx-settings-open-inline')?.addEventListener('click', open);
  closeBtn?.addEventListener('click', close);
  overlay.addEventListener('click', (e) => { if (e.target === overlay) close(); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !overlay.hidden) close();
  });
  form.addEventListener('submit', (e) => {
    e.preventDefault();
    save(false);
  });
  clearBtn?.addEventListener('click', () => save(true));

  load();
})();
