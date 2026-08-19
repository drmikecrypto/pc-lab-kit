const { test, expect } = require('@playwright/test');
const path = require('path');

test.describe('Driver confidence UI', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/18765/drivers**', async (route) => {
      const body = require(path.join(__dirname, 'fixtures', 'probe-drivers.json'));
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    });
    await page.route('**/18765/health**', async (route) => {
      const body = require(path.join(__dirname, 'fixtures', 'probe-health.json'));
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    });
    await page.route('**/18765/devices**', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ summary: { total_devices: 1, driverless: 0 }, devices: [] }),
      });
    });
    await page.route('**/api/diagnostic/live/present**', async (route) => {
      const drivers = require(path.join(__dirname, 'fixtures', 'probe-drivers.json'));
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ ok: true, drivers, devices: { driverless: [], summary: {} } }),
      });
    });
  });

  test('live tab shows match confidence percent', async ({ page }) => {
    await page.goto('/diagnostic');
    await page.locator('[data-dx-tab="quick"]').click();
    await expect(page.locator('#dx-driver-actions')).toContainText('82%', { timeout: 15000 });
  });
});
