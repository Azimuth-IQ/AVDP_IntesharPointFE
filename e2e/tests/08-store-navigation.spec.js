// @ts-check
// Role coverage — Store admin (STORE, ADMIN role → /store, not the /pos POS session).
// Logs in as a store's ADMIN user and reaches every section. Disposable E2E account.
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

const ST_PHONE = process.env.ST_PHONE || '07959222000';
const ST_PASS = process.env.ST_PASS || 'FMg557ory';

const ROUTES = [
  '/store/home', // dashboard
  '/store/inventory', // its stock view
  '/store/transactions', // orders
];

test('Store admin (STORE) logs in and reaches every section', async ({ page }) => {
  await F.login(page, ST_PHONE, ST_PASS);
  expect(page.url(), 'a store ADMIN should land under /store (not /pos)').toContain('/store');
  for (const r of ROUTES) {
    await F.goRoute(page, '#' + r);
    expect(page.url(), `should be on ${r}`).toContain(r);
    const nodes = await page.locator('flt-semantics').count();
    expect(nodes, `${r} should render content`).toBeGreaterThan(2);
    console.log(`  ✓ ${r} (${nodes} nodes)`);
  }
});
