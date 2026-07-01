// @ts-check
// Role coverage — Main Agent (AGENT1). Logs in as a Main Agent and reaches every section
// of its console. Uses an E2E-created disposable Main Agent (not a real account).
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

const A1_PHONE = process.env.A1_PHONE || '07960226000';
const A1_PASS = process.env.A1_PASS || 'FMg557ory';

const ROUTES = [
  '/agent1/home', // dashboard
  '/agent1/entities', // hierarchy
  '/agent1/inventory', // his card pool
  '/agent1/transactions', // orders
  '/agent1/pricing', // per-agent pricing
  '/agent1/stores', // his POS points
];

test('Main Agent (AGENT1) logs in and reaches every section', async ({ page }) => {
  await F.login(page, A1_PHONE, A1_PASS);
  expect(page.url(), 'a Main Agent should land under /agent1').toContain('/agent1');
  for (const r of ROUTES) {
    await F.goRoute(page, '#' + r);
    expect(page.url(), `should be on ${r}`).toContain(r);
    const nodes = await page.locator('flt-semantics').count();
    expect(nodes, `${r} should render content`).toBeGreaterThan(2);
    console.log(`  ✓ ${r} (${nodes} nodes)`);
  }
});
