const { test, expect } = require('@playwright/test');

test.describe('Stability Oracle interpret API', () => {
  test('returns grade and certificate fields', async ({ request }) => {
    const res = await request.post('/api/diagnostic/stability-oracle/interpret', {
      data: {
        run: {
          stability_margin_pct: 36.5,
          breached: false,
          baseline: { duration_s: 30, cpu_temp_avg: 42 },
          oracle_steps: [
            { id: 'cpu', status: 'ok', stability_margin_pct: 40 },
            { id: 'gpu', status: 'ok', stability_margin_pct: 36.5 },
          ],
        },
        samples: [],
      },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.interpretation.grade).toBeTruthy();
    expect(body.certificate.stability_margin_pct).toBe(36.5);
    expect(body.certificate.oracle_grade).toBeTruthy();
  });

  test('profiles endpoint lists deep oracle profile', async ({ request }) => {
    const res = await request.get('/api/diagnostic/stability-oracle/profiles');
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(Array.isArray(body.profiles)).toBe(true);
  });
});
