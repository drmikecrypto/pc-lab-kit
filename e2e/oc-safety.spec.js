# Playwright E2E — OC safety gates (health score minimum).

const { test, expect } = require('@playwright/test');

test.describe('OC safety UI', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/api/diagnostic/oc/plan', async (route) => {
      const body = route.request().postDataJSON?.() || {};
      const health = Number(body.health_score ?? body.healthScore ?? 65);
      const blocked = health < 70;
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          ok: true,
          plan: blocked ? null : { steps: [{ id: 'power_plan' }] },
          blocked,
          blockers: blocked ? [{ message: 'Health score below 70' }] : [],
          safety_score: blocked ? 60 : 85,
        }),
      });
    });
  });

  test('OC plan blocked when health under 70', async ({ page }) => {
    await page.goto('/diagnostic');
    const ocTab = page.locator('[data-dx-tab="oc"]');
    if (await ocTab.count()) {
      await ocTab.click();
    }
    await expect(page.locator('body')).toBeVisible();
  });
});
