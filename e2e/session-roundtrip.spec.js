const { test, expect } = require('@playwright/test');
const path = require('path');
const fs = require('fs');

test.describe('.pclab session import', () => {
  test('API accepts fixture session json', async ({ request }) => {
    const fixture = JSON.parse(
      fs.readFileSync(path.join(__dirname, 'fixtures', 'pclab-session.json'), 'utf8')
    );
    const res = await request.post('/api/diagnostic/session/import', {
      data: { json: JSON.stringify(fixture) },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.session.format).toBe('pclab-session-v1');
  });

  test('command center shows Import .pclab control', async ({ page }) => {
    await page.goto('/diagnostic');
    await expect(page.locator('label[for="dx-suite-import-file"]')).toContainText('Import .pclab');
  });
});
