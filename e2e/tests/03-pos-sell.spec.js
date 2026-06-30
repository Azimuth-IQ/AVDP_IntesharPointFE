// @ts-check
// The marquee flow: a POS operator logs in, unlocks the PIN gate, and sells a voucher that
// is DRAWN from the parent Main Agent's pool (draw-on-print) — the store holds no cards.
//
// By default this stops BEFORE the Reveal tap, because revealing draws + consumes a real
// pool card (irreversible) and debits the withdrawal limit. Set E2E_DRAW=1 to complete the
// sale and assert the PIN is revealed (needs ≥1 available card in the Main Agent pool).
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

const POS_PHONE = process.env.POS_PHONE || '07703333333';
const POS_PASS = process.env.POS_PASS || 'FMg557ory';
const POS_PIN = process.env.POS_PIN || '1111';
const DO_DRAW = process.env.E2E_DRAW === '1';

test('POS sells a voucher drawn from the main-agent pool', async ({ page }) => {
  // Login → POS PIN gate.
  await F.login(page, POS_PHONE, POS_PASS);
  expect(page.url(), 'a POS operator should hit the PIN lock').toContain('/pos/pin-lock');

  // Unlock the session.
  await F.fillNth(page, 0, POS_PIN);
  await F.tap(page, 'فتح الجلسة'); // Open session
  await page.waitForTimeout(3500);
  await F.enableSemantics(page);
  expect(page.url(), 'should reach the POS counter').toContain('/pos/home');

  // The sellable SKU comes from the parent pool (the store owns no cards), priced + counted.
  await F.expectText(page, 'iCASH 5k IQD');
  await F.expectText(page, 'بيع'); // Sell

  // Open the sell sheet (pre-reveal — nothing is consumed until Reveal).
  await F.tap(page, 'بيع');
  await page.waitForTimeout(2000);
  await F.enableSemantics(page);
  await F.expectText(page, 'مخفي حتى الإظهار'); // PIN masked until revealed
  await F.expectText(page, 'المتوفر في مخزن الوكيل'); // "available in main-agent pool"
  await F.expectText(page, 'إظهار الرمز'); // Reveal button is present

  if (!DO_DRAW) {
    test.info().annotations.push({
      type: 'note',
      description: 'Stopped before Reveal. Run with E2E_DRAW=1 to complete the sale (consumes a real pool card).',
    });
    return;
  }

  // DESTRUCTIVE: Reveal draws one FIFO card from the Main Agent pool, debits the withdrawal
  // limit per tier, and returns the decrypted PIN.
  await F.tap(page, 'إظهار الرمز'); // Reveal the code
  await page.waitForTimeout(4500);
  await F.enableSemantics(page);
  // The masked placeholder is gone (the real PIN is now shown) and a print action appears.
  await expect(F.node(page, 'مخفي حتى الإظهار'), 'PIN should be revealed after draw').toHaveCount(0);
  const post = await F.dumpNodes(page, 50);
  const labels = [...new Set(post.map((n) => n.label || n.text).filter((s) => s && s.length < 40))];
  console.log('  POST-DRAW labels:', JSON.stringify(labels.slice(0, 18)));
  expect(labels.some((l) => /طباعة|تم|Print/.test(l)), 'a print/done action should appear post-draw').toBeTruthy();
});
