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

function load(name) {
  return JSON.parse(fs.readFileSync(path.join(fixturesDir, name), 'utf8'));
}

let suiteJob = {
  status: 'idle',
  progress: 0,
  step: 'idle',
  stress: null,
  benches: [],
};

const routes = {
  '/health': () => load('probe-health.json'),
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
  }),
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', 'http://127.0.0.1');
  const p = url.pathname.toLowerCase();
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (p === '/stress/oracle/start' && req.method === 'POST') {
    suiteJob = {
      status: 'completed',
      progress: 100,
      step: 'oracle',
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
    suiteJob = {
      status: 'running',
      progress: 40,
      step: 'stress',
      benches: [{ id: 'cpu', score: 12000 }],
      stress: { id: 'combined', status: 'running' },
    };
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
