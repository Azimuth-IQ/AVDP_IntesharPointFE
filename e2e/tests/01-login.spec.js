// @ts-check
// Foundational UI E2E: the HQ admin logs in through the real login screen and lands on
// the HQ dashboard. Requires AUTH_TOTP_ENABLED=false on the target backend (otherwise
// login returns the TOTP enroll/verify step instead of a token).
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

const HQ_PHONE = process.env.HQ_PHONE || '07705371953';
const HQ_PASS = process.env.HQ_PASS || 'root';

test('HQ logs in via the UI and reaches the dashboard', async ({ page }) => {
  await page.goto('/');
  await F.boot(page);

  // The login screen exposes two text fields: [0] phone, [1] password.
  const fields = await F.inputCount(page);
  expect(fields, 'login screen should expose phone + password inputs').toBeGreaterThanOrEqual(2);
  await F.fillNth(page, 0, HQ_PHONE);
  await F.fillNth(page, 1, HQ_PASS);

  // Tap the login button (Arabic "دخول").
  await F.tap(page, 'دخول');

  // After login the HQ user is routed to /hq/home (System Activity). Wait for the route to
  // leave /login, then re-assert semantics on the new screen.
  await page.waitForURL((u) => !/\/login\b/.test(u.toString()), { timeout: 30_000 }).catch(() => {});
  await page.waitForTimeout(3000);
  await F.enableSemantics(page);

  const url = page.url();
  expect(url, `expected to be off the login route, got ${url}`).not.toMatch(/\/login\b/);
});
