// @ts-check
// Happy-path entity creation: HQ creates a Main Agent through the 2-step wizard (Details →
// Users) and it appears in the list. Also exercises the fix where new entities used to get a
// blank _id. Creates real UAT data with a unique name/phone each run.
const { test, expect } = require('@playwright/test');
const F = require('../helpers/flutter');

test('HQ creates a Main Agent via the wizard', async ({ page }) => {
  await F.login(page, process.env.HQ_PHONE || '07705371953', process.env.HQ_PASS || 'root');
  await F.goRoute(page, '#/hq/main-agents');
  await F.tap(page, 'وكيل رئيسي جديد'); // New Main Agent
  await page.waitForTimeout(1500);
  await F.enableSemantics(page);

  const stamp = Date.now();
  const name = 'E2E Agent ' + stamp;
  const phone = '079' + String(stamp).slice(-8); // unique, valid 11-digit Iraqi phone

  // Step 1 — Details: commercial name + one governorate (Muthanna, obscure → avoids the
  // "one Main Agent per governorate" rule colliding with seeded agents).
  await F.fillNth(page, 0, name);
  await F.tap(page, 'المثنى'); // Muthanna
  await F.tap(page, 'التالي'); // Next
  await page.waitForTimeout(1500);
  await F.enableSemantics(page);

  // Step 2 — Users: the admin login (phone + password).
  await F.fillNth(page, 0, phone);
  await F.fillNth(page, 1, 'Root1234');
  await F.tap(page, 'إنشاء'); // Create
  await page.waitForTimeout(4000);
  await F.enableSemantics(page);

  // The wizard popped back to the list (a validation error would have kept us on the form
  // with the "إنشاء" button). The list cards are custom-painted, so agent NAMES aren't in
  // the semantics tree to assert on — confirm the creation via the API instead (the whole
  // interaction above was real UI; only this verification reads the server).
  expect(page.url(), 'should return to the main-agents list').toContain('/hq/main-agents');
  await F.expectText(page, 'وكيل رئيسي جديد'); // "New Main Agent" button => on the list, not the form

  const lr = await page.request.post('/api/auth/login', {
    data: { phone: process.env.HQ_PHONE || '07705371953', password: process.env.HQ_PASS || 'root' },
  });
  const token = (await lr.json()).token;
  const all = await page.request.get('/api/entity/readall', { headers: { Authorization: `Bearer ${token}` } });
  expect((await all.text()).includes(name), 'the new Main Agent should exist on the server').toBeTruthy();
});
