// @ts-check
// Fail scenarios — the system must REJECT bad input, not silently accept it. These are
// non-destructive (they assert rejections) and exercise the error-handling paths.
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

test('wrong password is rejected at login', async ({ page }) => {
  await page.goto('/');
  await F.boot(page);
  await F.fillNth(page, 0, '07705371953');
  await F.fillNth(page, 1, 'definitely-the-wrong-password');
  await F.tap(page, 'دخول'); // Login
  await page.waitForTimeout(4000);
  await F.enableSemantics(page);
  expect(page.url(), 'a wrong password must NOT log in').toContain('/login');
  await F.expectText(page, 'فشل تسجيل الدخول'); // "Login failed"
});

test('wrong POS PIN does not unlock the counter', async ({ page }) => {
  await F.login(page, '07703333333', 'FMg557ory');
  expect(page.url(), 'POS should be at the PIN gate').toContain('/pos/pin-lock');
  await F.fillNth(page, 0, '9999'); // wrong PIN (real is different)
  await F.tap(page, 'فتح الجلسة'); // Open session
  await page.waitForTimeout(3000);
  await F.enableSemantics(page);
  expect(page.url(), 'a wrong PIN must NOT reach the POS counter').toContain('/pos/pin-lock');
});

test('Main Agent wizard will not advance without a name', async ({ page }) => {
  await F.login(page, process.env.HQ_PHONE || '07705371953', process.env.HQ_PASS || 'root');
  await F.goRoute(page, '#/hq/main-agents');
  await F.tap(page, 'وكيل رئيسي جديد'); // New Main Agent
  await page.waitForTimeout(1500);
  await F.enableSemantics(page);
  // Leave the commercial name empty; pick a governorate; try to advance.
  await F.tap(page, 'بغداد'); // Baghdad
  await F.tap(page, 'التالي'); // Next
  await page.waitForTimeout(1500);
  await F.enableSemantics(page);
  // The Users step (with the "إنشاء"/Create button) must NOT appear — validation blocks it.
  const reachedCreate = await F.node(page, 'إنشاء').count();
  expect(reachedCreate, 'an empty name must block advancing to the Users step').toBe(0);
});
