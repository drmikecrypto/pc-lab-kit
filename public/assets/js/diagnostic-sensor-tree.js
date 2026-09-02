/**
 * HWiNFO-class Sensor Tree — searchable hierarchy, favorites, live min/max.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  const FAV_KEY = 'pclab_sensor_tree_favorites';
  let timer = null;
  let favorites = loadFavs();
  let stats = {}; // id -> { min, max, last }

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

  function loadFavs() {
    try {
      const raw = JSON.parse(localStorage.getItem(FAV_KEY) || '[]');
      return new Set(Array.isArray(raw) ? raw.map(String) : []);
    } catch (_) {
      return new Set();
    }
  }

  function saveFavs() {
    try {
      localStorage.setItem(FAV_KEY, JSON.stringify([...favorites]));
    } catch (_) {}
  }

  function sensorId(row) {
    return [row.hardware || 'hw', row.name || row.id || '', row.unit || ''].join('|');
  }

  function track(row) {
    const id = sensorId(row);
    const v = Number(row.value);
    if (!Number.isFinite(v)) return;
    if (!stats[id]) stats[id] = { min: v, max: v, last: v };
    else {
      stats[id].min = Math.min(stats[id].min, v);
      stats[id].max = Math.max(stats[id].max, v);
      stats[id].last = v;
    }
  }

  function groupRows(rows) {
    const groups = {};
    for (const r of rows) {
      const hw = r.hardware || r.hardware_type || 'Other';
      if (!groups[hw]) groups[hw] = [];
      groups[hw].push(r);
    }
    return groups;
  }

  function render(rows) {
    const tree = el('dx-sensor-tree-body');
    const favBox = el('dx-sensor-tree-favs');
    if (!tree) return;
    const q = (el('dx-sensor-tree-search')?.value || '').trim().toLowerCase();
    const filtered = (rows || []).filter((r) => {
      if (!q) return true;
      const hay = `${r.hardware || ''} ${r.name || ''} ${r.type || ''} ${r.unit || ''}`.toLowerCase();
      return hay.includes(q);
    });
    filtered.forEach(track);
    const groups = groupRows(filtered);
    const keys = Object.keys(groups).sort((a, b) => a.localeCompare(b));

    if (!keys.length) {
      tree.innerHTML = `<p class="muted fs-sm">No sensors yet — wait for Probe telemetry (elevate for full HwMon tree).</p>`;
    } else {
      tree.innerHTML = keys
        .map((hw) => {
          const kids = groups[hw]
            .map((r) => {
              const id = sensorId(r);
              const st = stats[id] || {};
              const fav = favorites.has(id);
              const val = r.value != null ? esc(r.value) : '—';
              const unit = esc(r.unit || '');
              const min = st.min != null ? esc(Math.round(st.min * 100) / 100) : '—';
              const max = st.max != null ? esc(Math.round(st.max * 100) / 100) : '—';
              return `<div class="dx-st-row${fav ? ' is-fav' : ''}" data-id="${esc(id)}">
                <button type="button" class="dx-st-star" data-fav="${esc(id)}" aria-label="Favorite" title="Favorite">${fav ? '★' : '☆'}</button>
                <span class="dx-st-name">${esc(r.name || 'sensor')}${r.open_book ? ' <span class="dx-st-ob">OB</span>' : ''}</span>
                <span class="dx-st-val">${val} ${unit}</span>
                <span class="dx-st-minmax muted fs-xs">${min} … ${max}</span>
              </div>`;
            })
            .join('');
          return `<details class="dx-st-group" open>
            <summary>${esc(hw)} <span class="muted fs-xs">(${groups[hw].length})</span></summary>
            ${kids}
          </details>`;
        })
        .join('');
    }

    if (favBox) {
      const favRows = filtered.filter((r) => favorites.has(sensorId(r)));
      favBox.innerHTML = favRows.length
        ? favRows
            .map((r) => {
              const id = sensorId(r);
              const st = stats[id] || {};
              return `<div class="dx-st-row is-fav"><span class="dx-st-name">${esc(r.name)}</span>
                <span class="dx-st-val">${esc(r.value)} ${esc(r.unit || '')}</span>
                <span class="muted fs-xs">${st.min ?? '—'} … ${st.max ?? '—'}</span></div>`;
            })
            .join('')
        : `<p class="muted fs-xs">Star sensors to pin favorites here.</p>`;
    }

    tree.querySelectorAll('[data-fav]').forEach((btn) => {
      btn.addEventListener('click', (ev) => {
        ev.preventDefault();
        const id = btn.getAttribute('data-fav');
        if (favorites.has(id)) favorites.delete(id);
        else favorites.add(id);
        saveFavs();
        tick();
      });
    });

    const st = el('dx-sensor-tree-status');
    if (st) st.textContent = `${filtered.length} channels · ${favorites.size} favorites`;
  }

  async function tick() {
    try {
      const res = await fetch(AGENT() + '/telemetry', { mode: 'cors' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const tel = await res.json();
      const snap = tel._snapshot || tel;
      let rows = snap.sensors_flat || tel.sensors_flat || snap.hwmon?.sensors_flat || [];
      if (!Array.isArray(rows)) rows = [];
      if (!rows.length && snap.open_book?.sensors) {
        rows = (snap.open_book.sensors || []).map((s) => ({
          name: s.name,
          value: s.value,
          unit: s.unit || '°C',
          hardware: s.hardware || 'Open Book',
          open_book: true,
        }));
      }
      render(rows);
    } catch (e) {
      const tree = el('dx-sensor-tree-body');
      if (tree) tree.innerHTML = `<p class="muted fs-sm">Probe offline — ${esc(e.message || e)}</p>`;
    }
  }

  function bind() {
    if (!el('dx-sensor-tree')) return;
    el('dx-sensor-tree-search')?.addEventListener('input', () => tick());
    el('dx-sensor-tree-refresh')?.addEventListener('click', () => tick());
    window.addEventListener('dx:tab-change', (ev) => {
      if (ev.detail?.tab === 'advanced') {
        tick();
        if (!timer) timer = setInterval(tick, 2000);
      }
    });
    tick();
    timer = setInterval(tick, 2000);
  }

  window.PcLabSensorTree = { refresh: tick };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind);
  else bind();
})();
