/** @type {import('@playwright/test').PlaywrightTestConfig} */
const config = {
  testDir: './e2e',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.PCLAB_BASE_URL || 'http://127.0.0.1:8080',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    channel: process.env.PCLAB_PLAYWRIGHT_CHANNEL || undefined,
  },
  webServer: process.env.PCLAB_SKIP_WEB_SERVER
    ? undefined
    : {
        command: process.platform === 'win32' ? 'powershell -File scripts/start.ps1' : './scripts/start.sh',
        url: 'http://127.0.0.1:8080/diagnostic',
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
      },
};

module.exports = config;
