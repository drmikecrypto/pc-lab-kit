#!/usr/bin/env node
/**
 * Minimal mock probe for Playwright E2E — serves fixture JSON on localhost.
 * Usage: node e2e/mock-probe-server.js [port]
 */
const http = require('http');
const fs = require('fs');
const path = require('path');

const port = Number(process.argv[2] || 18766);
const fixturesDir = path.join(__dirname, 'fixtures');
const AUTH = 'e2e-mock-token';

function load(name) {
  return JSON.parse(fs.readFileSync(path.join(fixturesDir, name), 'utf8'));
}

let suiteJob = {
  status: 'idle',
  progress: 0,
  step: 'idle',
  stress: null,
  benches: [],
  resumable: false,
  completed_steps: [],
};

const routes = {
  '/health': () => {
    const h = load('probe-health.json');
    return {
      ...h,
      ok: true,
      auth_required: true,
      auth_token: AUTH,
      uptime_s: 42,
      pid: 1,
      service_mode: false,
      ring0: !!h.elevated,
      last_error: null,
    };
  },
  '/openbook': () => load('probe-openbook.json'),
  '/drivers': () => load('probe-drivers.json'),
  '/telemetry/history': () => load('probe-topology-history.json'),
  '/telemetry': () => {
    const hist = load('probe-topology-history.json');
    const latest = hist[hist.length - 1] || {};
    return { _snapshot: latest, collected_at: latest.ts || new Date().toISOString() };
  },
  '/suite/status': () => ({
    ok: true,
    job: suiteJob,
    status: suiteJob.status,
    progress: suiteJob.progress,
    step: suiteJob.step,
    stress: suiteJob.stress,
    benches: suiteJob.benches,
    resume_token: suiteJob.id || suiteJob.resume_token,
    resumable: !!suiteJob.resumable,
    completed_steps: suiteJob.completed_steps || [],
  }),
};

function requireAuth(req, res) {
  const tok = req.headers['x-pclab-token'] || '';
  if (tok !== AUTH) {
    res.writeHead(401, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, error: 'unauthorized' }));
    return false;
  }
  return true;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', 'http://127.0.0.1');
  const p = url.pathname.toLowerCase();
  const origin = req.headers.origin || '';
  if (/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
  } else {
    res.setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-PcLab-Token, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (p === '/stress/oracle/start' && req.method === 'POST') {
    if (!requireAuth(req, res)) return;
    suiteJob = {
      id: 'mockoracle',
      resume_token: 'mockoracle',
      status: 'completed',
      progress: 100,
      step: 'oracle',
      resumable: false,
      completed_steps: ['probe', 'stress'],
      stress: {
        id: 'oracle',
        stability_margin_pct: 36.5,
        oracle_grade: 'B',
        breached: false,
        baseline: { duration_s: 30, cpu_temp_avg: 42, gpu_temp_avg: 48 },
        oracle_steps: [{ id: 'cpu', status: 'ok' }, { id: 'gpu', status: 'ok' }],
      },
      benches: [],
    };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, job: suiteJob }));
    return;
  }

  if (p === '/suite/start' && req.method === 'POST') {
    if (!requireAuth(req, res)) return;
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      let resume = false;
      try {
        const j = JSON.parse(body || '{}');
        resume = !!(j.resume || j.resume_token);
      } catch (_) {}
      if (resume && suiteJob.status === 'interrupted') {
        suiteJob = {
          ...suiteJob,
          status: 'completed',
          progress: 100,
          step: 'done',
          resumable: false,
          stress: { id: 'combined', status: 'ok' },
        };
      } else {
        suiteJob = {
          id: 'mocksuite1',
          resume_token: 'mocksuite1',
          status: 'completed',
          progress: 100,
          step: 'done',
          resumable: false,
          completed_steps: ['probe', 'bench:cpu', 'stress'],
          benches: [
            {
              id: 'storage',
              engine: 'diskspd_cdm',
              diskspd_available: true,
              score: 1500,
              profiles: {
                SEQ1M_Q8T1: { read_mbps: 3200, write_mbps: 3000, read_iops: 1000, write_iops: 900, read_latency_us: 50 },
              },
            },
          ],
          stress: { id: 'combined', status: 'ok', oracle_grade: 'A', stability_margin_pct: 40 },
          samples: [{ t: new Date().toISOString(), cpu_temp: 50, gpu_temp: 55 }],
          probe: { cpu: { name: 'Mock CPU' }, devices: { fingerprint: { id: 'mock' } } },
        };
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, job: suiteJob }));
    });
    return;
  }

  if (p === '/suite/discard' && req.method === 'POST') {
    if (!requireAuth(req, res)) return;
    suiteJob = { status: 'idle', progress: 0, step: 'idle', resumable: false, benches: [], completed_steps: [] };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, job: suiteJob }));
    return;
  }

  if (p === '/suite/cancel' && req.method === 'POST') {
    if (!requireAuth(req, res)) return;
    suiteJob = { ...suiteJob, status: 'interrupted', step: 'interrupted', resumable: true };
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, job: suiteJob }));
    return;
  }

  const handler = routes[p];
  if (!handler) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'not found', path: p }));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(handler()));
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Mock probe listening on http://127.0.0.1:${port}/`);
});
