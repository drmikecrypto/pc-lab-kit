import { test, expect } from '@playwright/test';

test.describe('Command Center 2.0', () => {
  test('left nav, Intelligence Pulse, and Benchmark Arena tab', async ({ page }) => {
    await page.goto('/diagnostic', { waitUntil: 'domcontentloaded' });

    await expect(page.locator('.dx-lab-nav')).toBeVisible();
    await expect(page.locator('#dx-intelligence-pulse')).toBeVisible();
    await expect(page.locator('#dx-intelligence-pulse')).not.toHaveClass(/dx-pulse-hidden/);

    await page.locator('[data-dx-nav="arena"]').click();
    await expect(page.locator('#dx-arena')).toBeVisible();
    await expect(page.locator('#dx-arena-grid')).toBeVisible();
  });
});
