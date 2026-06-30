// @ts-check
// Primitives for driving a Flutter (CanvasKit) web app from Playwright via its
// accessibility/semantics tree. Flutter paints to <canvas>, so there is no DOM to
// click until semantics is enabled — after which each widget with a label/role/action
// is mirrored into a <flt-semantics> element, and text fields become real <input>s.
const { expect } = require('@playwright/test');

const BOOT_MS = 8000;

/** Wait for Flutter's first frame, then turn on the semantics tree. */
async function boot(page) {
  await page.waitForSelector('flt-glass-pane, flutter-view', { timeout: 40_000 }).catch(() => {});
  await page.waitForTimeout(BOOT_MS);
  await enableSemantics(page);
}

/** Click the hidden "Enable accessibility" placeholder via the DOM (a positional click
 *  can't land on the 0-size element), which makes Flutter build the semantics tree. */
async function enableSemantics(page) {
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder');
    if (p) /** @type {HTMLElement} */ (p).click();
  });
  await page
    .waitForFunction(() => document.querySelectorAll('flt-semantics').length > 1, { timeout: 12_000 })
    .catch(() => {});
  await page.waitForTimeout(1200);
}

/** A locator for a semantics node whose aria-label or visible text contains `text`. */
function node(page, text) {
  const esc = text.replace(/"/g, '\\"');
  return page.locator(`flt-semantics[aria-label*="${esc}"], flt-semantics:has-text("${esc}")`);
}

/** Assert a node containing `text` exists (semantics nodes are often 0-size, so we assert
 *  attached, not visible). Re-enables semantics once if it dropped after a navigation. */
async function expectText(page, text, { timeout = 20_000 } = {}) {
  try {
    await expect(node(page, text).first()).toBeAttached({ timeout });
  } catch (e) {
    await enableSemantics(page);
    await expect(node(page, text).first()).toBeAttached({ timeout: 8000 });
  }
}

/** Find the TIGHTEST semantics node matching `text` and return its center point. A label
 *  like a button's appears both on the real control (a small leaf) and on wrapping
 *  containers (whose textContent also contains it) — we want the smallest box so the click
 *  lands on the control, not empty space in a container. Prefers an exact text/label match. */
async function findBox(page, text, { nth = 0, region = null } = {}) {
  return page.evaluate(
    ({ text, nth, region }) => {
      const ns = [...document.querySelectorAll('flt-semantics')];
      const own = (e) => (e.getAttribute('aria-label') || e.textContent || '').replace(/\s+/g, ' ').trim();
      const exact = ns.filter((e) => own(e) === text);
      const contains = ns.filter((e) => own(e).includes(text));
      const pool = exact.length ? exact : contains;
      let boxed = pool
        .map((e) => { const r = e.getBoundingClientRect(); return { r, area: r.width * r.height }; })
        .filter((o) => o.r.width > 0 && o.r.height > 0);
      if (region) {
        boxed = boxed.filter((o) => {
          const cx = o.r.x + o.r.width / 2, cy = o.r.y + o.r.height / 2;
          return (region.minX == null || cx >= region.minX) && (region.maxX == null || cx <= region.maxX) &&
                 (region.minY == null || cy >= region.minY) && (region.maxY == null || cy <= region.maxY);
        });
      }
      boxed.sort((a, b) => a.area - b.area);
      const pick = boxed[nth] || boxed[0];
      if (!pick) return null;
      const r = pick.r;
      return { cx: r.x + r.width / 2, cy: r.y + r.height / 2, w: r.width, h: r.height };
    },
    { text, nth, region }
  );
}

/** Tap a semantics node matching `text` (button, tile, nav item, …) by clicking the canvas
 *  at its center — Flutter hit-tests the paint there, which is more reliable than a DOM
 *  click on the (often action-less) semantics element. */
async function tap(page, text, { timeout = 20_000, nth = 0, region = null } = {}) {
  await node(page, text).first().waitFor({ state: 'attached', timeout });
  let box = await findBox(page, text, { nth, region });
  if (!box) { await enableSemantics(page); box = await findBox(page, text, { nth, region }); }
  if (!box) throw new Error(`tap: no semantics node found for "${text}"`);
  await page.mouse.click(box.cx, box.cy);
  await page.waitForTimeout(900);
}

/** Tap a left-hand-side… (RTL: right-hand) navigation-rail item by label, constraining to the
 *  rail region so a nav label can't collide with the same word in a KPI chip / page body. */
async function tapNav(page, text, { minX = 1120 } = {}) {
  await tap(page, text, { region: { minX } });
  await page.waitForTimeout(1800);
  await enableSemantics(page);
}

/** Fill the Nth text field on screen (Flutter exposes focused text fields as <input>/<textarea>). */
async function fillNth(page, n, value) {
  const inputs = page.locator('input:not([type=hidden]), textarea');
  await inputs.nth(n).waitFor({ state: 'attached', timeout: 15_000 });
  await inputs.nth(n).fill(value);
  await page.waitForTimeout(300);
}

/** How many text fields are currently on screen (sanity for form steps). */
async function inputCount(page) {
  return page.locator('input:not([type=hidden]), textarea').count();
}

/** Dump the current semantics nodes (debugging which labels exist on a screen). */
async function dumpNodes(page, limit = 80) {
  return page.$$eval(
    'flt-semantics, input, textarea',
    (els, lim) =>
      els
        .slice(0, lim)
        .map((e) => ({
          tag: e.tagName.toLowerCase(),
          role: e.getAttribute('role') || '',
          label: (e.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().slice(0, 60),
          type: e.getAttribute('type') || '',
          text: (e.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 50),
        }))
        .filter((n) => n.label || n.role || n.text || n.tag === 'input' || n.tag === 'textarea'),
    limit
  );
}

/** Full login: open the app, fill phone+password, tap دخول, wait off the /login route,
 *  and re-enable semantics on the landed screen. Requires TOTP off on the backend. */
async function login(page, phone, pass) {
  await page.goto('/');
  await boot(page);
  await fillNth(page, 0, phone);
  await fillNth(page, 1, pass);
  await tap(page, 'دخول');
  await page.waitForURL((u) => !/\/login\b/.test(u.toString()), { timeout: 30_000 }).catch(() => {});
  await page.waitForTimeout(3000);
  await enableSemantics(page);
}

/** Navigate to an in-app route via the URL hash (the nav rail is custom-painted and not in
 *  the semantics tree, so it can't be tapped by label — hash routing is the reliable path;
 *  the screen CONTENT is fully semantic and driven normally once there). Pass e.g. '#/hq/stores'. */
async function goRoute(page, hashPath) {
  await page.evaluate((h) => { window.location.hash = h; }, hashPath);
  await page.waitForTimeout(2500);
  await enableSemantics(page);
}

module.exports = { boot, enableSemantics, login, goRoute, node, expectText, tap, tapNav, findBox, fillNth, inputCount, dumpNodes, BOOT_MS };
