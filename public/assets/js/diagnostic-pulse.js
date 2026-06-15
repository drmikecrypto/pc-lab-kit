(function () {
  const FP_KEY = '_pcverse_fp';
  let whisperIdx = 0;
  let whispers = [];
  let whisperTimer = null;
  let canvasAnim = null;

  function el(id) { return document.getElementById(id); }

  function ensureFp() {
    let fp = localStorage.getItem(FP_KEY);
    if (!fp) {
      try { fp = crypto.randomUUID(); } catch (_) {
        fp = Date.now().toString(16) + '-' + Math.random().toString(16).slice(2);
      }
      fp = fp.slice(0, 64);
      localStorage.setItem(FP_KEY, fp);
      document.cookie = FP_KEY + '=' + fp + '; path=/; max-age=31536000; SameSite=Lax';
    }
    return fp;
  }

  function delay(ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  }

  function retryAfterMsFrom429(res, jsonBody) {
    var sec = null;
    if (jsonBody && jsonBody.retry_after_sec != null) {
      sec = parseInt(String(jsonBody.retry_after_sec), 10);
    }
    if (sec == null || isNaN(sec)) {
      var h = res.headers && res.headers.get ? res.headers.get('Retry-After') : null;
      if (h) sec = parseInt(h, 10);
    }
    if (sec == null || isNaN(sec)) sec = 3;
    sec = Math.max(1, Math.min(120, sec));
    return sec * 1000;
  }

  /** Lab telemetry → intelligence network (non-PII metadata only). */
  function trackLab(eventType, metadata) {
    if (!eventType) return;
    const body = {
      fingerprint: ensureFp(),
      event_type: eventType,
      metadata: metadata || {},
    };
    const bodyStr = JSON.stringify(body);
    (async function () {
      for (var a = 0; a < 3; a++) {
        var res = await fetch('/api/track/event', {
          method: 'POST',
          keepalive: true,
          headers: { 'Content-Type': 'application/json' },
          body: bodyStr,
        });
        if (res.status !== 429 || a === 2) return;
        var j = null;
        try { j = await res.json(); } catch (_) {}
        await delay(retryAfterMsFrom429(res, j));
      }
    })().catch(function () {});
  }

  function gpuScoreBucket(score) {
    var s = parseInt(String(score || 0), 10);
    if (!s) return 'unknown';
    if (s < 4000) return 'entry';
    if (s < 9000) return 'mid';
    if (s < 15000) return 'upper_mid';
    if (s < 22000) return 'high';
    return 'enthusiast';
  }

  function thermalBand(gpuT, cpuT) {
    var g = parseFloat(String(gpuT || 0));
    var c = parseFloat(String(cpuT || 0));
    if (g <= 0 && c <= 0) return 'unknown';
    var mx = Math.max(g, c);
    if (mx >= 95) return 'hot';
    if (mx >= 85) return 'warm';
    return 'cool';
  }

  function metaFromScan(data) {
    if (!data || typeof data !== 'object') return {};
    var m = data.metrics || {};
    var consultant = data.consultant || {};
    var picks = consultant.catalog_picks || [];
    var pickIds = [];
    var up0 = (data.upgrade_suggestions && data.upgrade_suggestions[0]) || {};
    return {
      health_grade: data.health_grade || '',
      health_score: data.health_score != null ? data.health_score : null,
      bottleneck: (data.bottleneck && data.bottleneck.type) || data.bottleneck_type || '',
      bottleneck_component: (data.bottleneck && data.bottleneck.component) || '',
      profile: data.vakhsh_oc && data.vakhsh_oc.profile ? data.vakhsh_oc.profile : '',
      ram_gb: m.ram_gb != null ? m.ram_gb : null,
      vram_gb: m.vram_gb != null ? m.vram_gb : null,
      form_factor: data.form_factor || '',
      mode: data.mode || '',
      consultant_stance: consultant.stance || '',
      catalog_pick_ids: pickIds,
      gpu_score_bucket: gpuScoreBucket(m.gpu_score),
      thermal_band: thermalBand(m.gpu_temp_max, m.cpu_temp_max),
      upgrade_top_category: up0.category_slug || '',
    };
  }

  window.dxTrackLab = trackLab;
  window.dxLabMetaFromScan = metaFromScan;

  function animateNum(node, target) {
    if (!node) return;
    var cur = parseInt(node.dataset.val || '0', 10);
    var next = parseInt(target, 10) || 0;
    if (cur === next) return;
    node.dataset.val = String(next);
    var steps = 14;
    var step = 0;
    function tick() {
      step++;
      var v = Math.round(cur + (next - cur) * (step / steps));
      node.textContent = v.toLocaleString('en-US');
      if (step < steps) requestAnimationFrame(tick);
      else node.textContent = next.toLocaleString('en-US');
    }
    tick();
  }

  function renderPulse(pulse) {
    if (!pulse) return;
    var engine = pulse.engine || pulse.vakhsh || {};
    var advisor = pulse.advisor || pulse.amin || {};
    var neural = pulse.neural || {};

    animateNum(el('dx-pulse-v-deep'), engine.deep_scans);
    animateNum(el('dx-pulse-v-orch'), engine.orchestrations);
    animateNum(el('dx-pulse-v-layers'), engine.sensor_layers || engine.telemetry_layers || 11);
    animateNum(el('dx-pulse-v-tools'), engine.tools_unified);

    animateNum(el('dx-pulse-a-insights'), advisor.insights_total);
    animateNum(el('dx-pulse-a-today'), advisor.insights_today);
    animateNum(el('dx-pulse-a-bn'), advisor.bottlenecks_mapped);
    var avgEl = el('dx-pulse-a-health');
    if (avgEl) {
      var avg = advisor.avg_health_24h != null ? advisor.avg_health_24h : advisor.avg_health;
      avgEl.textContent = avg > 0 ? Number(avg).toLocaleString('en-US') : '—';
    }

    var vLive = el('dx-pulse-v-live');
    if (vLive) vLive.textContent = engine.live_line || engine.live_line_fa || '';
    var aLive = el('dx-pulse-a-live');
    if (aLive) aLive.textContent = advisor.live_line || advisor.live_line_fa || '';

    var tag = el('dx-pulse-tagline');
    if (tag) tag.textContent = pulse.tagline || pulse.tagline_fa || 'Tools — not a store. Everything in one lab.';

    var sync = el('dx-pulse-sync');
    if (sync) sync.textContent = '● ' + (neural.sync_label || neural.sync_label_fa || 'PCVerse local network');

    whispers = neural.whispers || neural.whispers_fa || [];
    rotateWhisper(true);

    var feed = el('dx-pulse-feed');
    if (feed) {
      var items = neural.feed || [];
      feed.innerHTML = items.slice(0, 5).map(function (f) {
        return '<span class="dx-pulse-feed-chip">' + esc(f.line || f.line_fa) + ' · <em>' + esc(f.ago) + '</em></span>';
      }).join('');
    }
  }

  function rotateWhisper(immediate) {
    var node = el('dx-pulse-whisper-text');
    if (!node || !whispers.length) return;
    function show() {
      node.classList.add('fade-out');
      setTimeout(function () {
        whisperIdx = (whisperIdx + 1) % whispers.length;
        node.textContent = whispers[whisperIdx];
        node.classList.remove('fade-out');
      }, immediate ? 0 : 320);
    }
    if (immediate) {
      node.textContent = whispers[0];
    } else {
      show();
    }
    clearInterval(whisperTimer);
    whisperTimer = setInterval(show, 6800);
  }

  function esc(s) {
    var d = document.createElement('div');
    d.textContent = s == null ? '' : s;
    return d.innerHTML;
  }

  function initSynapseCanvas() {
    var canvas = el('dx-pulse-canvas');
    if (!canvas) return;
    var ctx = canvas.getContext('2d');
    var t = 0;

    function resize() {
      var rect = canvas.parentElement.getBoundingClientRect();
      canvas.width = rect.width * 2;
      canvas.height = rect.height * 2;
      canvas.style.width = rect.width + 'px';
      canvas.style.height = rect.height + 'px';
      ctx.setTransform(2, 0, 0, 2, 0, 0);
    }

    function draw() {
      var w = canvas.width / 2;
      var h = canvas.height / 2;
      ctx.clearRect(0, 0, w, h);
      t += 0.012;

      var midY = h * 0.5;
      ctx.strokeStyle = 'rgba(34, 211, 238, 0.25)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      for (var x = 0; x <= w; x += 2) {
        var y = midY + Math.sin(x * 0.04 + t) * 8 + Math.sin(x * 0.08 - t * 1.3) * 4;
        if (x === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();

      for (var i = 0; i < 3; i++) {
        var px = ((t * 40 + i * (w / 3)) % w);
        var py = midY + Math.sin(px * 0.04 + t) * 8;
        var g = ctx.createRadialGradient(px, py, 0, px, py, 6);
        g.addColorStop(0, i === 1 ? 'rgba(242,159,5,0.9)' : 'rgba(34,211,238,0.9)');
        g.addColorStop(1, 'transparent');
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(px, py, 6, 0, Math.PI * 2);
        ctx.fill();
      }

      canvasAnim = requestAnimationFrame(draw);
    }

    resize();
    draw();
    window.addEventListener('resize', resize);
  }

  window.dxRenderPulse = renderPulse;

  document.addEventListener('DOMContentLoaded', function () {
    initSynapseCanvas();
    trackLab('diagnostic_lab_view', { section: 'pulse' });
  });
})();
