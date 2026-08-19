/**
 * Three.js digital twin — live telemetry history on hardware graph nodes during stress.
 */
(function () {
  const AGENT = () => (window.PCLAB_DIAGNOSTIC && window.PCLAB_DIAGNOSTIC.agentBase) || 'http://127.0.0.1:18765';

  let scene = null;
  let camera = null;
  let renderer = null;
  let nodeMeshes = {};
  let thermDots = [];
  let heatPlane = null;
  let animId = null;
  let stressActive = false;
  let lastTemps = { cpu: 45, gpu: 50, hotspot: 55 };
  let openBookSensors = [];

  function tempColor(c) {
    const t = Math.max(0, Math.min(1, (c - 35) / 70));
    const r = Math.round(40 + t * 215);
    const g = Math.round(120 - t * 90);
    const b = Math.round(220 - t * 180);
    return (r << 16) | (g << 8) | b;
  }

  function ensureThree(cb) {
    if (window.THREE) {
      cb();
      return;
    }
    const s = document.createElement('script');
    s.src = 'https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.min.js';
    s.onload = cb;
    document.head.appendChild(s);
  }

  function gpuMesh() {
    return Object.values(nodeMeshes).find((m) => m.userData.type === 'gpu') || null;
  }

  function syncThermDots() {
    if (!scene || !window.THREE) return;
    thermDots.forEach((d) => scene.remove(d));
    thermDots = [];
    const gpu = gpuMesh();
    if (!gpu) return;

    const sLabels = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6'];
    const offsets = [
      { x: -0.04, y: 0.02, z: -0.03 },
      { x: 0.04, y: 0.02, z: -0.03 },
      { x: -0.04, y: 0.04, z: 0.03 },
      { x: 0.04, y: 0.04, z: 0.03 },
      { x: 0, y: 0.06, z: 0 },
      { x: 0, y: 0.02, z: 0.05 },
    ];
    const names = openBookSensors.map((s) => String(s.name || '').toLowerCase());
    const hasTherm = sLabels.some((l) => names.some((n) => n.includes('therm ' + l.toLowerCase()) || n.includes(' ' + l.toLowerCase())));
    if (!hasTherm) return;

    sLabels.forEach((label, i) => {
      const sensor = openBookSensors.find((s) => {
        const n = String(s.name || '').toLowerCase();
        return n.includes('therm ' + label.toLowerCase()) || n.includes(' ' + label.toLowerCase());
      });
      const temp = sensor?.value != null ? Number(sensor.value) : lastTemps.hotspot || lastTemps.gpu;
      const geo = new THREE.SphereGeometry(0.012, 10, 10);
      const mat = new THREE.MeshStandardMaterial({
        color: tempColor(temp),
        emissive: tempColor(temp) >> 3,
        metalness: 0.1,
        roughness: 0.4,
      });
      const dot = new THREE.Mesh(geo, mat);
      const off = offsets[i];
      dot.position.copy(gpu.position).add(new THREE.Vector3(off.x, off.y + 0.03, off.z));
      dot.userData = { label, temp };
      scene.add(dot);
      thermDots.push(dot);
    });
  }

  function initScene(root, topology3d) {
    if (!root || !window.THREE) return;
    root.innerHTML = '';
    const w = root.clientWidth || 640;
    const h = root.clientHeight || 360;
    scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0b0f14);
    camera = new THREE.PerspectiveCamera(42, w / h, 0.1, 10);
    camera.position.set(0.2, 0.85, 1.35);
    camera.lookAt(0, 0, 0);
    renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setSize(w, h);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    root.appendChild(renderer.domElement);

    const light = new THREE.DirectionalLight(0xffffff, 1.1);
    light.position.set(1, 2, 1);
    scene.add(light);
    scene.add(new THREE.AmbientLight(0x446688, 0.45));

    const board = topology3d.board || { width: 1.4, depth: 1.0 };
    const boardGeo = new THREE.BoxGeometry(board.width, 0.02, board.depth);
    const boardMat = new THREE.MeshStandardMaterial({ color: 0x1a2332, metalness: 0.2, roughness: 0.85 });
    const boardMesh = new THREE.Mesh(boardGeo, boardMat);
    boardMesh.position.y = -0.02;
    scene.add(boardMesh);

    const heatGeo = new THREE.PlaneGeometry(board.width * 0.95, board.depth * 0.95);
    const heatMat = new THREE.MeshBasicMaterial({ color: 0x224466, transparent: true, opacity: 0.15, side: THREE.DoubleSide });
    heatPlane = new THREE.Mesh(heatGeo, heatMat);
    heatPlane.rotation.x = -Math.PI / 2;
    heatPlane.position.y = 0.01;
    scene.add(heatPlane);

    nodeMeshes = {};
    (topology3d.nodes || []).forEach((n) => {
      const sz = n.size || { w: 0.1, h: 0.03, d: 0.1 };
      const geo = new THREE.BoxGeometry(sz.w, sz.h, sz.d);
      const mat = new THREE.MeshStandardMaterial({ color: 0x58a6ff, emissive: 0x001122, metalness: 0.35, roughness: 0.5 });
      const mesh = new THREE.Mesh(geo, mat);
      const p = n.position || { x: 0, y: 0, z: 0 };
      mesh.position.set(p.x, p.y + sz.h / 2, p.z);
      mesh.userData = { id: n.id, type: n.type, label: n.label };
      scene.add(mesh);
      nodeMeshes[n.id] = mesh;
    });

    (topology3d.links || []).forEach((l) => {
      const a = nodeMeshes[l.source];
      const b = nodeMeshes[l.target];
      if (!a || !b) return;
      const pts = [a.position.clone(), b.position.clone()];
      const lineGeo = new THREE.BufferGeometry().setFromPoints(pts);
      const line = new THREE.Line(lineGeo, new THREE.LineBasicMaterial({ color: 0x30363d }));
      scene.add(line);
    });

    syncThermDots();

    function tick() {
      animId = requestAnimationFrame(tick);
      Object.values(nodeMeshes).forEach((m) => {
        const type = m.userData.type;
        let temp = lastTemps.gpu;
        if (type === 'cpu') temp = lastTemps.cpu;
        if (type === 'gpu') temp = lastTemps.hotspot || lastTemps.gpu;
        const col = tempColor(temp);
        m.material.color.setHex(col);
        m.material.emissive.setHex(col >> 2);
      });
      thermDots.forEach((d) => {
        const col = tempColor(d.userData.temp || lastTemps.hotspot || lastTemps.gpu);
        d.material.color.setHex(col);
        d.material.emissive.setHex(col >> 3);
      });
      if (heatPlane && stressActive) {
        heatPlane.material.opacity = 0.12 + 0.08 * Math.sin(Date.now() / 400);
        heatPlane.material.color.setHex(tempColor(lastTemps.hotspot || lastTemps.gpu));
      }
      renderer.render(scene, camera);
    }
    tick();
  }

  function applyHistorySample(snap) {
    if (!snap || typeof snap !== 'object') return;
    if (snap.cpu_temp != null) lastTemps.cpu = Number(snap.cpu_temp);
    if (snap.gpu_temp != null) lastTemps.gpu = Number(snap.gpu_temp);
    if (snap.gpu_hotspot != null) lastTemps.hotspot = Number(snap.gpu_hotspot);
  }

  async function pollTelemetryHistory() {
    try {
      const r = await fetch(`${AGENT()}/telemetry/history`, { cache: 'no-store' });
      if (!r.ok) return;
      const data = await r.json();
      const rows = Array.isArray(data) ? data : data.history || data.samples || [];
      const latest = rows.length ? rows[rows.length - 1] : null;
      applyHistorySample(latest);
    } catch (_) {}
  }

  async function refreshOpenBookSensors() {
    try {
      const r = await fetch(`${AGENT()}/openbook`, { cache: 'no-store' });
      if (!r.ok) return;
      const data = await r.json();
      const wrap = data.open_book || data;
      openBookSensors = wrap.sensors || [];
      syncThermDots();
    } catch (_) {}
  }

  function render(root, payload) {
    if (!root) return;
    const topology3d = payload?.topology_3d || payload;
    if (!topology3d?.nodes?.length) {
      root.innerHTML = '<p class="muted fs-sm">3D topology unavailable — run probe first.</p>';
      return;
    }
    ensureThree(() => {
      initScene(root, topology3d);
      refreshOpenBookSensors();
      if (!window.__dxTopo3dPoll) {
        window.__dxTopo3dPoll = setInterval(pollTelemetryHistory, 2000);
      }
    });
  }

  function setStressActive(on) {
    stressActive = !!on;
  }

  function destroy() {
    if (animId) cancelAnimationFrame(animId);
    animId = null;
    if (renderer) renderer.dispose();
    scene = null;
    nodeMeshes = {};
    thermDots = [];
  }

  window.PcLabTopology3d = { render, setStressActive, destroy, tempColor };
  window.addEventListener('dx:suite-stress-start', () => setStressActive(true));
  window.addEventListener('dx:suite-complete', () => setStressActive(false));
})();
