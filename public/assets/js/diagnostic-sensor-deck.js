/**
 * Sensor Deck — gauges from probe telemetry + save/export layouts + live alerts.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  let layout = null;
  let timer = null;

  const SOURCE_TO_THRESHOLD = {
    cpu_temp: 'cpu_temp_c',
    gpu_temp: 'gpu_temp_c',
    gpu_hotspot: 'gpu_hotspot_c',
    package_power_w: 'package_power_w',
  };

  function csrfHeaders() {
    const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    return { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t };
  }

  function thresholds() {
    return (
      layout?.alert_thresholds || {
        cpu_temp_c: 90,
        gpu_temp_c: 85,
        gpu_hotspot_c: 95,
        package_power_w: 200,
        gpu_power_w: 400,
      }
    );
  }

  function pick(sample, source) {
    if (!sample || typeof sample !== 'object') return null;
    const map = {
      cpu_temp: sample.cpu_temp ?? sample.cpu_temp_max ?? sample?.cpu?.thermal?.package_c,
      gpu_temp: sample.gpu_temp ?? sample.gpu_temp_max ?? sample?.gpu?.thermal?.core_c,
      gpu_hotspot: sample.gpu_hotspot ?? sample?.gpu?.thermal?.hot_spot_c ?? sample?.gpu?.thermal?.hotspot_c,
      gpu_therm_spread: sample.gpu_therm_spread ?? sample?.gpu?.thermal?.therm_spread_c,
      gpu_vram_temp: sample.gpu_vram_temp ?? sample?.gpu?.thermal?.memory_c,
      gpu_therm_s1: sample.gpu_therm_s1 ?? sample?.open_book?.sensors?.find?.((x) => x.name === 'GPU Therm S1')?.value,
      cpu_load: sample.cpu_load ?? sample.cpu_util ?? sample?.cpu?.util ?? sample?.cpu?.render?.util_pct,
      gpu_load: sample.gpu_load ?? sample.gpu_util ?? sample?.gpu?.util ?? sample?.gpu?.render?.gpu_util_pct,
      vram_used_pct: sample.vram_used_pct ?? sample?.gpu?.memory?.used_pct ?? sample?.gpu?.vram?.used_pct,
      package_power_w: sample.package_power_w ?? sample?.cpu?.power?.package_w ?? sample?.power?.package_w ?? sample?.cpu?.power?.package,
      gpu_power_w: sample.gpu_power_w ?? sample?.gpu?.power?.board_w ?? sample?.gpu?.power?.draw_w,
      fan_rpm: sample.fan_rpm ?? sample?.fans?.[0]?.rpm ?? sample?.cooling?.fan_rpm ?? sample?.cpu?.fans?.rpm,
      ram_used_pct: sample.ram_used_pct ?? sample?.ram?.used_pct,
    };
    const v = map[source] ?? sample[source];
    return v == null || v === '' ? null : Number(v);
  }

  function evaluateAlerts(sample) {
    const th = thresholds();
    const checks = [
      { key: 'cpu_temp_c', label: 'CPU', unit: '°C', value: pick(sample, 'cpu_temp') },
      { key: 'gpu_temp_c', label: 'GPU', unit: '°C', value: pick(sample, 'gpu_temp') },
      { key: 'gpu_hotspot_c', label: 'Hotspot', unit: '°C', value: pick(sample, 'gpu_hotspot') },
      { key: 'package_power_w', label: 'CPU power', unit: 'W', value: pick(sample, 'package_power_w') },
      { key: 'gpu_power_w', label: 'GPU power', unit: 'W', value: pick(sample, 'gpu_power_w') },
    ];
    const fired = [];
    for (const c of checks) {
      const limit = Number(th[c.key]);
      if (c.value == null || Number.isNaN(c.value) || !Number.isFinite(limit)) continue;
      if (c.value >= limit) {
        fired.push(`${c.label} ${Math.round(c.value * 10) / 10}${c.unit} ≥ ${limit}${c.unit} alert`);
      }
    }
    return fired;
  }

  function syncThresholdInputs() {
    const th = thresholds();
    const map = {
      'dx-deck-th-cpu': 'cpu_temp_c',
      'dx-deck-th-gpu': 'gpu_temp_c',
      'dx-deck-th-hs': 'gpu_hotspot_c',
      'dx-deck-th-cpupwr': 'package_power_w',
      'dx-deck-th-gpupwr': 'gpu_power_w',
    };
    Object.entries(map).forEach(([id, key]) => {
      const el = document.getElementById(id);
      if (el && th[key] != null) el.value = String(th[key]);
    });
  }

  function readThresholdInputs() {
    if (!layout) layout = { widgets: [] };
    layout.alert_thresholds = {
      cpu_temp_c: Number(document.getElementById('dx-deck-th-cpu')?.value || 90),
      gpu_temp_c: Number(document.getElementById('dx-deck-th-gpu')?.value || 85),
      gpu_hotspot_c: Number(document.getElementById('dx-deck-th-hs')?.value || 95),
      package_power_w: Number(document.getElementById('dx-deck-th-cpupwr')?.value || 200),
      gpu_power_w: Number(document.getElementById('dx-deck-th-gpupwr')?.value || 400),
    };
  }

  function render(widgets, sample) {
    const grid = document.getElementById('dx-deck-grid');
    if (!grid) return;
    const th = thresholds();
    grid.innerHTML = (widgets || [])
      .filter((w) => w.type !== 'sparkline')
      .map((w) => {
        const val = pick(sample, w.source);
        const shown = val == null || Number.isNaN(val) ? '—' : Math.round(val * 10) / 10;
        const thKey = SOURCE_TO_THRESHOLD[w.source];
        const limit = thKey != null ? Number(th[thKey]) : null;
        const warn = thKey && val != null && Number.isFinite(limit) && val >= limit;
        return `<div class="dx-sensor-deck__gauge${warn ? ' is-warn' : ''}" data-id="${w.id}">
          <div class="dx-sensor-deck__val">${shown}</div>
          <div class="dx-sensor-deck__lbl">${w.label || w.source}</div>
        </div>`;
      })
      .join('');

    const strip = document.getElementById('dx-deck-alerts');
    if (strip) {
      const fired = evaluateAlerts(sample);
      strip.hidden = fired.length === 0;
      strip.textContent = fired.join(' · ');
      strip.classList.toggle('is-warn', fired.length > 0);
    }
  }

  async function loadLayout() {
    const res = await fetch('/api/diagnostic/sensor-deck');
    const data = await res.json();
    layout = data.layout || null;
    syncThresholdInputs();
    return layout;
  }

  async function tick() {
    try {
      const res = await fetch(AGENT() + '/telemetry');
      const tel = await res.json();
      const snap = tel._snapshot || tel;
      render(layout?.widgets || [], snap);
      const note = document.getElementById('dx-deck-status');
      if (note) note.textContent = 'Live · Probe telemetry';
    } catch (_) {
      const note = document.getElementById('dx-deck-status');
      if (note) note.textContent = 'Probe offline';
    }
  }

  async function saveLayout() {
    if (!layout) return;
    readThresholdInputs();
    await fetch('/api/diagnostic/sensor-deck', {
      method: 'POST',
      headers: csrfHeaders(),
      body: JSON.stringify(layout),
    });
    const note = document.getElementById('dx-deck-status');
    if (note) note.textContent = 'Layout + alert thresholds saved';
  }

  function exportLayout(format) {
    window.open('/api/diagnostic/sensor-deck/export?format=' + encodeURIComponent(format), '_blank');
  }

  async function boot() {
    if (!document.getElementById('dx-sensor-deck')) return;
    try {
      await loadLayout();
      render(layout?.widgets || [], {});
    } catch (_) {}
    document.getElementById('dx-deck-save')?.addEventListener('click', saveLayout);
    document.getElementById('dx-deck-export-json')?.addEventListener('click', () => exportLayout('json'));
    document.getElementById('dx-deck-export-csv')?.addEventListener('click', () => exportLayout('csv'));
    document.getElementById('dx-deck-export-rain')?.addEventListener('click', () => exportLayout('rainmeter'));
    ['dx-deck-th-cpu', 'dx-deck-th-gpu', 'dx-deck-th-hs', 'dx-deck-th-cpupwr', 'dx-deck-th-gpupwr'].forEach((id) => {
      document.getElementById(id)?.addEventListener('change', () => {
        readThresholdInputs();
        tick();
      });
    });
    timer = setInterval(tick, 2000);
    tick();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();

  window.PcLabSensorDeck = { reload: loadLayout };
})();
