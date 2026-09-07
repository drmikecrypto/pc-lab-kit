const { test, expect } = require('@playwright/test');
const path = require('path');

/**
 * Phase 0 trust smoke: Session Forensics UI, LCD Studio anchor, Full Lab resume controls.
 */
test.describe('Phase 0 trust smoke', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/18765/**', async (route) => {
      const url = route.request().url();
      const u = new URL(url);
      const p = u.pathname.replace(/\/$/, '') || '/';
      if (p === '/health' || p.endsWith('/health')) {
        const body = require(path.join(__dirname, 'fixtures', 'probe-health.json'));
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            ...body,
            sensor_trust: {
              honesty_matrix: [{ id: 'presentmon', status: 'ok', needs: 'PresentMon.exe' }],
              elevated: true,
              conflict: false,
            },
            fans: true,
          }),
        });
      }
      if (p.includes('/presentmon/profiles')) {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            ok: true,
            profiles: [{ id: 'quick_10s', label: 'Quick 10s', seconds: 10 }],
          }),
        });
      }
      if (p.includes('/presentmon/sessions')) {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ ok: true, sessions: [] }),
        });
      }
      if (p.includes('/fans')) {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            ok: true,
            inventory: { fan_count: 0, control_count: 0, fans: [], apply_capability: { write_pwm: false } },
            evaluated: [],
            temps: { ref_c: 40 },
          }),
        });
      }
      if (p.includes('/lcd')) {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ ok: true, panels: [] }),
        });
      }
      const fixture = url.includes('/openbook') ? 'probe-openbook.json' : 'probe-health.json';
      const body = require(path.join(__dirname, 'fixtures', fixture));
      return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
    });
  });

  test('Session Forensics + LCD Studio + Full Lab controls visible', async ({ page }) => {
    await page.goto('/diagnostic');
    await expect(page.locator('#dx-command-center')).toBeVisible();
    await expect(page.locator('#dx-identity-strip')).toBeVisible();

    await page.locator('#dx-programmed-suite').evaluate((el) => {
      el.open = true;
    });
    await expect(page.locator('#dx-suite-run')).toBeVisible();
    await expect(page.locator('#dx-suite-import-file')).toBeAttached();

    // Advanced modules host SMART / PresentMon / LCD
    const adv = page.locator('[data-dx-panel="advanced"]');
    if (await adv.count()) {
      await page.evaluate(() => {
        document.querySelector('[data-dx-tab="advanced"]')?.click();
      });
    }
    await expect(page.locator('#dx-pm-review')).toBeVisible();
    await expect(page.locator('#dx-pm-profile')).toBeVisible();
    await expect(page.locator('#dx-lcd-studio')).toBeVisible();
    await expect(page.locator('#dx-fans-panel')).toBeVisible();
  });
});
