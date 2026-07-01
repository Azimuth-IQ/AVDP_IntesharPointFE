// @ts-check
// Role coverage — Sub-Agent (AGENT2). Logs in as a Sub-Agent and reaches every section of
// its console. Uses an E2E-created disposable Sub-Agent (not a real account).
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

const A2_PHONE = process.env.A2_PHONE || '07959111000';
const A2_PASS = process.env.A2_PASS || 'FMg557ory';

const ROUTES = [
  '/agent2/home', // dashboard (withdrawal limit)
  '/agent2/entities', // hierarchy (its stores)
  '/agent2/inventory', // browse (holds no cards under the pool model)
  '/agent2/transactions', // orders
  '/agent2/stores', // its POS points
];

test('Sub-Agent (AGENT2) logs in and reaches every section', async ({ page }) => {
  await F.login(page, A2_PHONE, A2_PASS);
  expect(page.url(), 'a Sub-Agent should land under /agent2').toContain('/agent2');
  for (const r of ROUTES) {
    await F.goRoute(page, '#' + r);
    expect(page.url(), `should be on ${r}`).toContain(r);
    const nodes = await page.locator('flt-semantics').count();
    expect(nodes, `${r} should render content`).toBeGreaterThan(2);
    console.log(`  ✓ ${r} (${nodes} nodes)`);
  }
});
