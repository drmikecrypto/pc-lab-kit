// Playwright E2E — Programmed suite UI with mocked probe fixtures.

const { test, expect } = require('@playwright/test');
const path = require('path');

test.describe('Full Lab with mock probe', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/18765/**', async (route) => {
      const url = route.request().url();
      const fixture = url.includes('/openbook')
        ? 'probe-openbook.json'
        : 'probe-health.json';
      const body = require(path.join(__dirname, 'fixtures', fixture));
      await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    });

    await page.route('**/api/diagnostic/suite/profiles', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          ok: true,
          profiles: [
            { id: 'standard', label: 'Full Lab', duration_hint_min: 14 },
            { id: 'deep', label: 'Deep Lab', duration_hint_min: 22, stress_id: 'oracle' },
          ],
        }),
      });
    });
  });

  test('overview shows programmed suite with dynamic start label', async ({ page }) => {
    await page.goto('/diagnostic');
    await expect(page.locator('#dx-command-center')).toBeVisible();
    await page.locator('#dx-programmed-suite').evaluate((el) => {
      el.open = true;
    });
    await expect(page.locator('#dx-suite-run')).toBeVisible();
    await expect(page.locator('#dx-suite-run')).toContainText(/Start Adaptive Lab|Start /i);
    await expect(page.locator('#dx-suite-profile')).toBeVisible();
    await expect(page.locator('label[for="dx-suite-import-file"]')).toBeVisible();
  });

  test('deep profile includes oracle stress id in profiles API', async ({ request }) => {
    const res = await request.get('/api/diagnostic/suite/profiles');
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    const deep = (body.profiles || []).find((p) => p.id === 'deep');
    expect(deep).toBeTruthy();
    expect(deep.stress_id || deep.oracle).toBeTruthy();
  });
});
