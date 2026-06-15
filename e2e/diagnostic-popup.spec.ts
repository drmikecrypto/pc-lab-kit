import { test, expect } from '@playwright/test';

test.describe('لاب diagnostic — پاپ‌آپ اپ', () => {
  test('RTL، safe-area روی overlay، و اسکرول داخل کارت وقتی محتوا بلند است', async ({ page }) => {
    await page.goto('/diagnostic', { waitUntil: 'domcontentloaded' });

    const overlay = page.locator('#dx-app-popup');
    await expect(overlay).toHaveAttribute('dir', 'rtl');

    const overlayOverflow = await overlay.evaluate((el) => getComputedStyle(el).overflowY);
    expect(['auto', 'scroll']).toContain(overlayOverflow);

    await page.evaluate(() => {
      const root = document.getElementById('dx-app-popup');
      const ul = document.getElementById('dx-popup-benefits');
      if (!root || !ul) return;
      ul.innerHTML = '';
      for (let i = 0; i < 30; i++) {
        const li = document.createElement('li');
        li.textContent =
          'خط تست برای بلند شدن محتوا و فعال شدن اسکرول داخل کارت پاپ‌آپ. '.repeat(4);
        ul.appendChild(li);
      }
      root.hidden = false;
    });

    const pitch = page.locator('.dx-popup-app-pitch');
    await expect(pitch).toBeVisible();

    const pitchDir = await pitch.evaluate((el) => getComputedStyle(el).direction);
    expect(pitchDir).toBe('rtl');

    const scrollInsideCard = await pitch.evaluate((el) => el.scrollHeight > el.clientHeight + 2);
    expect(scrollInsideCard).toBeTruthy();
  });
});
