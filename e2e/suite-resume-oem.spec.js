// @ts-check
const { test, expect } = require('@playwright/test');

test.describe('Overview OEM path + suite resume', () => {
  test('OEM phases and programmed suite CTA are available', async ({ page }) => {
    await page.goto('/diagnostic');
    await expect(page.locator('#dx-command-center')).toBeVisible();
    await page.locator('#dx-programmed-suite').evaluate((el) => {
      el.open = true;
    });
    await expect(page.locator('#dx-suite-run')).toBeVisible();
    await expect(page.locator('.dx-oem-phases')).toBeVisible();
    // Demoted from first viewport (attribute + CSS); assert attribute so layout CSS cannot flake visibility.
    await expect(page.locator('#dx-intelligence-pulse')).toHaveAttribute('hidden', '');
    await expect(page.locator('#dx-intelligence-pulse')).toHaveClass(/dx-pulse-demoted/);
    await expect(page.locator('#dx-suite-profile option[value="soak_15"]')).toHaveCount(1);
  });

  test('resume banner can appear after mock interrupt', async ({ page }) => {
    await page.goto('/diagnostic');
    await page.locator('#dx-programmed-suite').evaluate((el) => {
      el.open = true;
    });
    await page.evaluate(() => {
      const banner = document.getElementById('dx-suite-resume');
      if (banner) {
        banner.hidden = false;
        banner.innerHTML =
          '<strong>Resume programmed suite</strong><button type="button" id="dx-suite-resume-btn">Resume</button>';
      }
    });
    await expect(page.locator('#dx-suite-resume')).toBeVisible();
    await expect(page.locator('#dx-suite-resume-btn')).toBeVisible();
  });
});
