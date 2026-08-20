/**
 * Sensor Deck — gauges from probe telemetry + save/export layouts.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';
  let layout = null;
  let timer = null;

  function csrfHeaders() {
    const t = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || '';
    return { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': t };
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
      fan_rpm: sample.fan_rpm ?? sample?.fans?.[0]?.rpm ?? sample?.cooling?.fan_rpm ?? sample?.cpu?.fans?.rpm,
      ram_used_pct: sample.ram_used_pct ?? sample?.ram?.used_pct,
    };
    const v = map[source] ?? sample[source];
    return v == null || v === '' ? null : Number(v);
  }

  function render(widgets, sample) {
    const grid = document.getElementById('dx-deck-grid');
    if (!grid) return;
    grid.innerHTML = (widgets || [])
      .filter((w) => w.type !== 'sparkline')
      .map((w) => {
        const val = pick(sample, w.source);
        const shown = val == null || Number.isNaN(val) ? '—' : Math.round(val * 10) / 10;
        return `<div class="dx-sensor-deck__gauge" data-id="${w.id}">
          <div class="dx-sensor-deck__val">${shown}</div>
          <div class="dx-sensor-deck__lbl">${w.label || w.source}</div>
        </div>`;
      })
      .join('');
  }

  async function loadLayout() {
    const res = await fetch('/api/diagnostic/sensor-deck');
    const data = await res.json();
    layout = data.layout || null;
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
    await fetch('/api/diagnostic/sensor-deck', {
      method: 'POST',
      headers: csrfHeaders(),
      body: JSON.stringify(layout),
    });
    const note = document.getElementById('dx-deck-status');
    if (note) note.textContent = 'Layout saved';
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
    timer = setInterval(tick, 2000);
    tick();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();

  window.PcLabSensorDeck = { reload: loadLayout };
})();
