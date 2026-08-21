const { test, expect } = require('@playwright/test');

test.describe('Programmed suite error UX', () => {
  test('shows calm probe guidance when Probe is offline', async ({ page }) => {
    await page.route((url) => String(url).includes(':18765/'), async (route) => {
      await route.abort('failed');
    });

    await page.goto('/diagnostic', { waitUntil: 'domcontentloaded' });
    await page.locator('#dx-programmed-suite').evaluate((el) => {
      el.open = true;
    });
    await expect(page.locator('#dx-suite-run')).toBeVisible();
    await page.locator('#dx-suite-run').click();
    await expect(page.locator('#dx-suite-error')).toBeVisible({ timeout: 15000 });
    await expect(page.locator('#dx-suite-error')).toContainText(/Probe|not reachable|not ready/i);
  });
});

test.describe('Drivers and Test tabs', () => {
  test('nav opens Drivers and Test panels exclusively', async ({ page }) => {
    await page.goto('/diagnostic', { waitUntil: 'domcontentloaded' });

    await page.locator('[data-dx-nav="drivers"]').click();
    await expect(page.locator('#dx-drivers-lab')).toBeVisible();
    await expect(page.locator('#dx-driver-actions')).toBeVisible();
    await expect(page.locator('#dx-command-center')).toBeHidden();
    await expect(page.locator('#dx-stress-lab')).toBeHidden();

    await page.locator('[data-dx-nav="stress"]').click();
    await expect(page.locator('#dx-stress-lab')).toBeVisible();
    await expect(page.locator('#dx-stress-run')).toBeVisible();
    await expect(page.locator('#dx-stress-hours')).toBeVisible();
    await expect(page.locator('#dx-stress-minutes')).toBeVisible();
    await expect(page.locator('input[name="dx-test-target"]')).toHaveCount(3);
    await expect(page.locator('#dx-command-center')).toBeHidden();
    await expect(page.locator('#dx-drivers-lab')).toBeHidden();
  });
});
