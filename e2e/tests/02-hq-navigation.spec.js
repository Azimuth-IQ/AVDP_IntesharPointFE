// @ts-check
// Breadth smoke: the HQ user can reach every section and each renders. The nav RAIL is
// custom-painted (not in the semantics tree), so routing is by URL hash; the screen content
// is fully semantic. This verifies every feature screen exists + loads after auth.
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

const ROUTES = [
  '/hq/main-agents', // Main Agents
  '/hq/sub-agents', // Sub Agents
  '/hq/stores', // Stores / POS points
  '/hq/inventory', // Inventory
  '/hq/batch', // Batch import
  '/hq/transactions', // Transactions
  '/hq/entities', // Hierarchy
  '/hq/print-operations', // Print operations
  '/hq/points-transfer', // Reallocation
  '/hq/definitions', // Catalog / SKUs
  '/hq/templates', // Voucher templates
  '/hq/companies', // Companies
];

test('HQ reaches every section and it renders', async ({ page }) => {
  await F.login(page, process.env.HQ_PHONE || '07705371953', process.env.HQ_PASS || 'root');
  for (const r of ROUTES) {
    await F.goRoute(page, '#' + r);
    expect(page.url(), `should be on ${r}`).toContain(r);
    const nodes = await page.locator('flt-semantics').count();
    expect(nodes, `${r} should render content`).toBeGreaterThan(2);
    // first non-empty label = the screen's heading, for visibility
    const heading = await page
      .$$eval('flt-semantics', (els) =>
        els.map((e) => (e.getAttribute('aria-label') || e.textContent || '').replace(/\s+/g, ' ').trim()).find((s) => s && s.length < 60) || ''
      )
      .catch(() => '');
    console.log(`  ✓ ${r}  (${nodes} nodes)  ${heading.slice(0, 40)}`);
  }
});
