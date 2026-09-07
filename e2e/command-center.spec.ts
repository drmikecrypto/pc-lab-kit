import { test, expect } from '@playwright/test';

test.describe('Lab workspace navigation', () => {
  test('left nav, Overview pulse mount, and Benchmark Arena under Advanced', async ({ page }) => {
    await page.goto('/diagnostic', { waitUntil: 'domcontentloaded' });

    await expect(page.locator('.dx-lab-nav')).toBeVisible();
    await expect(page.locator('[data-dx-nav="command"]')).toContainText('Overview');
    await expect(page.locator('#dx-intelligence-pulse')).toHaveCount(1);
    await expect(page.locator('#dx-intelligence-pulse')).not.toHaveClass(/dx-pulse-hidden/);

    await page.locator('.dx-lab-nav__more').evaluate((el) => {
      el.open = true;
    });
    await page.locator('[data-dx-nav="arena"]').click();
    await expect(page.locator('#dx-arena')).toBeVisible();
    await expect(page.locator('#dx-arena-grid')).toBeVisible();
    await expect(page.locator('#dx-command-center')).toBeHidden();
  });
});
