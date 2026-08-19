// Playwright-style suite smoke (mocked probe). Run when e2e deps are installed.
// npx playwright test e2e/suite-smoke.spec.js

const { test, expect } = require('@playwright/test');

test.describe('Command Center Full Lab UI', () => {
  test('shows Run Full Lab CTA', async ({ page }) => {
    await page.route('**/api/diagnostic/suite/profiles', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          ok: true,
          profiles: [{ id: 'standard', label: 'Full Lab', duration_hint_min: 12 }],
        }),
      });
    });

    await page.goto('/diagnostic');
    await expect(page.locator('#dx-command-center')).toBeVisible();
    await expect(page.locator('#dx-suite-run')).toContainText('Run Full Lab');
  });
});
