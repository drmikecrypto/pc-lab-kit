/**
 * SSE telemetry river — subscribes to probe stream via PHP proxy.
 */
(function () {
  let es = null;

  function applySample(data) {
    if (!data || typeof data !== 'object') return;
    window.__dxLastTelemetry = data;
    window.dispatchEvent(new CustomEvent('dx:telemetry-sample', { detail: data }));
    const map = [
      ['dx-s-cpu', data.cpu_temp],
      ['dx-s-gpu', data.gpu_temp],
      ['dx-s-gpu-hs', data.gpu_hotspot],
    ];
    map.forEach(([id, val]) => {
      const el = document.getElementById(id);
      if (el && val != null) el.textContent = `${Math.round(Number(val))}°`;
    });
    if (window.PcLabTopology3d?.setStressActive && data.stress_active) {
      window.PcLabTopology3d.setStressActive(!!data.stress_active);
    }
  }

  function connect() {
    if (es) return;
    if (!window.EventSource) return;
    es = new EventSource('/api/diagnostic/telemetry/stream');
    es.onmessage = (ev) => {
      try {
        applySample(JSON.parse(ev.data));
      } catch (_) {}
    };
    es.onerror = () => {
      es.close();
      es = null;
      setTimeout(connect, 5000);
    };
  }

  document.addEventListener('DOMContentLoaded', connect);
  window.PcLabTelemetryStream = { connect, disconnect: () => { if (es) es.close(); es = null; } };
})();
