const { test, expect } = require('@playwright/test');
const path = require('path');

function agentRoute(page, handler) {
  return page.route((url) => String(url).includes(':18765/'), handler);
}

test.describe('Driver confidence UI', () => {
  test.beforeEach(async ({ page }) => {
    await agentRoute(page, async (route) => {
      const url = route.request().url();
      const drivers = require(path.join(__dirname, 'fixtures', 'probe-drivers.json'));
      const health = require(path.join(__dirname, 'fixtures', 'probe-health.json'));
      if (url.includes('/drivers')) {
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(drivers) });
      } else if (url.includes('/probe')) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ elevated: true, drivers, devices: { driverless: [], summary: {} } }),
        });
      } else {
        await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(health) });
      }
    });
  });

  test('live tab shows match confidence percent', async ({ page }) => {
    await page.goto('/diagnostic');
    await page.locator('[data-dx-nav="history"]').click();
    await expect(page.locator('#dx-driver-actions')).toContainText('82%', { timeout: 20000 });
  });
});
