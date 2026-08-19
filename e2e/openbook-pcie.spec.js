const { test, expect } = require('@playwright/test');
const path = require('path');

test.describe('Open Book PCIe warnings', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/18765/openbook**', async (route) => {
      const body = require(path.join(__dirname, 'fixtures', 'probe-openbook.json'));
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    });
    await page.route('**/18765/health**', async (route) => {
      const body = require(path.join(__dirname, 'fixtures', 'probe-health.json'));
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    });
  });

  test('hardware reference open book shows PCIe warning text', async ({ page }) => {
    await page.goto('/diagnostic');
    await page.locator('[data-dx-tab="hardware"]').click();
    await page.locator('#dx-hwref-refresh').click();
    await expect(page.locator('#dx-hwref-openbook-table')).toContainText('blackwell_therm_mmio', {
      timeout: 15000,
    });
  });
});
