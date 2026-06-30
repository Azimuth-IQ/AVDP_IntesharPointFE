// @ts-check
const { defineConfig } = require('@playwright/test');

// The Flutter web app is CanvasKit (paints to <canvas>) — there is no normal DOM to
// click. We drive it through Flutter's accessibility/semantics tree (see helpers/flutter.js),
// using the locally-installed system Chrome with software GL (swiftshader) so it renders
// headless without a GPU. No Playwright-managed browser download is needed.
const CHROME =
  process.env.CHROME_PATH ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

module.exports = defineConfig({
  testDir: './tests',
  // The suite is one stateful storyline (HQ builds the hierarchy, then a POS sells from it),
  // so it runs sequentially in file order, single worker.
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 180_000,
  expect: { timeout: 25_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.BASE_URL || 'http://34.185.153.95',
    viewport: { width: 1440, height: 960 },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    launchOptions: {
      executablePath: CHROME,
      args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--no-sandbox'],
    },
  },
});
