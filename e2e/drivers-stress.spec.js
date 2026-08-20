const { test, expect } = require('@playwright/test');

test.describe('Full Lab error UX', () => {
  test('shows visible error when Probe is offline', async ({ page }) => {
    await page.route((url) => String(url).includes(':18765/'), async (route) => {
      await route.abort('failed');
    });

    await page.goto('/diagnostic', { waitUntil: 'domcontentloaded' });
    await expect(page.locator('#dx-suite-run')).toBeVisible();
    await page.locator('#dx-suite-run').click();
    await expect(page.locator('#dx-suite-error')).toBeVisible({ timeout: 15000 });
    await expect(page.locator('#dx-suite-error')).toContainText(/could not start|not reachable|Probe/i);
  });
});

test.describe('Drivers and Stress tabs', () => {
  test('nav opens Drivers and Stress panels', async ({ page }) => {
    await page.goto('/diagnostic', { waitUntil: 'domcontentloaded' });
    await page.locator('[data-dx-nav="drivers"]').click();
    await expect(page.locator('#dx-drivers-lab')).toBeVisible();
    await expect(page.locator('#dx-driver-actions')).toBeVisible();

    await page.locator('[data-dx-nav="stress"]').click();
    await expect(page.locator('#dx-stress-lab')).toBeVisible();
    await expect(page.locator('#dx-stress-run')).toBeVisible();
    await expect(page.locator('#dx-stress-hours')).toBeVisible();
    await expect(page.locator('#dx-stress-minutes')).toBeVisible();
  });
});
