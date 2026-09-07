/**
 * Fan curves v1 — discover RPM, stage curves, preview duty (no SuperIO write yet).
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';

  function el(id) {
    return document.getElementById(id);
  }

  function esc(s) {
    return String(s ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  async function probeJsonHeaders() {
    if (window.PcLabProbeAuth) {
      await window.PcLabProbeAuth.ensure();
      return window.PcLabProbeAuth.jsonHeaders();
    }
    return { 'Content-Type': 'application/json' };
  }

  async function refreshFans() {
    const body = el('dx-fans-body');
    const status = el('dx-fans-status');
    if (!body) return;
    body.innerHTML = `<p class="muted fs-sm">Loading fans…</p>`;
    try {
      const res = await fetch(AGENT() + '/fans', { mode: 'cors' });
      const data = await res.json();
      window.__dxLastFans = data;
      if (!res.ok || data.ok === false) throw new Error(data.error || data.note || `HTTP ${res.status}`);
      const fans = data.inventory?.fans || [];
      const evaled = data.evaluated || [];
      const apply = data.inventory?.apply_capability || data.apply || {};
      const honesty = apply.honesty || data.apply?.note || '';
      if (status) {
        status.textContent = `${data.inventory?.fan_count ?? 0} fans · ${data.inventory?.control_count ?? 0} controls · ref ${data.temps?.ref_c ?? '—'}°C`;
      }
      body.innerHTML = `
        <p class="muted fs-xs dx-fans-honesty">${esc(honesty)}</p>
        <div class="dx-fans-grid">
          <div>
            <h4 class="dx-fans-sub">RPM / headers</h4>
            ${
              fans.length
                ? `<table class="dx-smart-table"><thead><tr><th>Hardware</th><th>Name</th><th>RPM</th></tr></thead><tbody>${fans
                    .map(
                      (f) =>
                        `<tr><td>${esc(f.hardware)}</td><td>${esc(f.name)}</td><td>${f.value != null ? esc(f.value) : '—'}</td></tr>`
                    )
                    .join('')}</tbody></table>`
                : `<p class="muted fs-sm">No Fan sensors — elevate Probe / build PcLabHwMon.</p>`
            }
          </div>
          <div>
            <h4 class="dx-fans-sub">Preview duty</h4>
            ${
              evaled.length
                ? `<table class="dx-smart-table"><thead><tr><th>Curve</th><th>Sensor °C</th><th>Duty %</th></tr></thead><tbody>${evaled
                    .map(
                      (e) =>
                        `<tr><td>${esc(e.name || e.id)}</td><td>${esc(e.sensor_c)}</td><td><strong>${esc(e.target_duty_pct)}</strong></td></tr>`
                    )
                    .join('')}</tbody></table>`
                : `<p class="muted fs-sm">No curves evaluated.</p>`
            }
          </div>
        </div>
        <p class="muted fs-xs mt-1">Write PWM: not enabled in v1. Curves stage to %LOCALAPPDATA%\\PcLabKit\\Probe\\fan-curves.json (Fan Control import).</p>`;
    } catch (e) {
      body.innerHTML = `<div class="dx-panel-empty is-error"><strong>Fans failed</strong><p class="muted fs-sm">${esc(e.message || e)}</p></div>`;
      if (status) status.textContent = 'Offline';
    }
  }

  async function loadCurvesForm() {
    try {
      const res = await fetch(AGENT() + '/fans/curves', { mode: 'cors' });
      const data = await res.json();
      const c = data.curves || {};
      const first = (c.curves || [])[0];
      const pts = first?.points || [];
      const ta = el('dx-fans-points');
      if (ta) {
        ta.value = pts
          .map((p) => {
            if (Array.isArray(p)) return `${p[0]},${p[1]}`;
            return `${p.t},${p.duty}`;
          })
          .join('\n');
      }
      const name = el('dx-fans-curve-name');
      if (name) name.value = first?.name || 'Case fans';
    } catch (_) {}
  }

  async function saveCurves() {
    const st = el('dx-fans-save-status');
    const raw = (el('dx-fans-points')?.value || '').trim();
    const points = raw
      .split(/\n+/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const [t, duty] = line.split(/[,;\s]+/).map(Number);
        return { t, duty };
      })
      .filter((p) => Number.isFinite(p.t) && Number.isFinite(p.duty));
    if (!points.length) {
      if (st) st.textContent = 'Add points as temp,duty per line (e.g. 55,40)';
      return;
    }
    if (st) st.textContent = 'Saving…';
    try {
      const res = await fetch(AGENT() + '/fans/curves', {
        method: 'POST',
        mode: 'cors',
        headers: await probeJsonHeaders(),
        body: JSON.stringify({
          confirm: true,
          curves: [
            {
              id: 'case',
              name: el('dx-fans-curve-name')?.value || 'Case fans',
              sensor: 'max',
              points,
            },
          ],
        }),
      });
      const data = await res.json();
      if (!res.ok || data.ok === false) throw new Error(data.error || data.honesty || `HTTP ${res.status}`);
      if (st) st.textContent = data.honesty || data.saved?.note || 'Staged locally (preview only)';
      await refreshFans();
    } catch (e) {
      if (st) st.textContent = e.message || String(e);
    }
  }

  function bind() {
    if (!el('dx-fans-panel')) return;
    el('dx-fans-refresh')?.addEventListener('click', () => {
      refreshFans();
      loadCurvesForm();
    });
    el('dx-fans-save')?.addEventListener('click', saveCurves);
    refreshFans();
    loadCurvesForm();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind);
  else bind();
})();
