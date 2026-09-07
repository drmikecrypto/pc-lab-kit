const { test, expect } = require('@playwright/test');

test.describe('Topology 3D API', () => {
  test('topology endpoint returns topology_3d nodes', async ({ request }) => {
    const res = await request.post('/api/diagnostic/topology', {
      data: {
        probe: {
          devices: {
            summary: { total_devices: 4 },
            pci: [{ name: 'GPU', class: 'Display' }],
          },
          cpu: { model: 'Ryzen 7' },
          gpu: { model: 'RTX 4070' },
        },
      },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.topology_3d).toBeTruthy();
    expect(Array.isArray(body.topology_3d.nodes)).toBe(true);
    expect(body.topology_3d.nodes.length).toBeGreaterThan(0);
  });

  test('advanced panel exposes 3D view toggle', async ({ page }) => {
    await page.goto('/diagnostic');
    await page.locator('[data-dx-nav="advanced"]').click();
    await expect(page.locator('#dx-topo-3d-toggle')).toContainText('3D view');
  });
});
