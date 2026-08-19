const { test, expect } = require('@playwright/test');
const path = require('path');

function agentRoute(page, handler) {
  return page.route((url) => String(url).includes(':18765/'), handler);
}

test.describe('Open Book PCIe warnings', () => {
  test.beforeEach(async ({ page }) => {
    await agentRoute(page, async (route) => {
      const url = route.request().url();
      const fixture = url.includes('/openbook')
        ? 'probe-openbook.json'
        : 'probe-health.json';
      const body = require(path.join(__dirname, 'fixtures', fixture));
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    });
  });

  test('hardware reference open book shows PCIe warning text', async ({ page }) => {
    await page.goto('/diagnostic');
    await page.locator('[data-dx-nav="openbook"]').click();
    await page.locator('#dx-ob-refresh').click();
    await expect(page.locator('#dx-ob-table')).toContainText('blackwell_therm_mmio', {
      timeout: 15000,
    });
  });
});
