# Inteshar Point — UI E2E (Playwright)

End-to-end UI tests that drive the **live** Flutter web app against the UAT stack
(`http://34.185.153.95`).

## Why it looks the way it does

The app is **Flutter Web / CanvasKit** — it paints to a single `<canvas>`, so there is
**no normal DOM to click**. We drive it through Flutter's **accessibility/semantics tree**:

- On each page we click the hidden "Enable accessibility" placeholder (via a DOM `.click()`),
  which makes Flutter mirror every labelled widget into a `<flt-semantics>` element and turn
  focused text fields into real `<input>`s.
- We **tap** a widget by finding the *tightest* semantics node whose text/label matches and
  clicking the **canvas at its centre** (Flutter hit-tests the paint there — more reliable
  than a DOM click on the often action-less semantics element).
- We **fill** text fields as normal `<input>`s.

Helpers live in `helpers/flutter.js` (`boot`, `enableSemantics`, `login`, `goRoute`, `tap`,
`tapNav`, `fillNth`, `findBox`, `expectText`, `dumpNodes`).

### Known limitation (and an app a11y gap)

The **navigation rail is custom-painted and is NOT in the semantics tree** — its items can't
be tapped by label. So **section navigation is done by URL hash** (`goRoute(page, '#/hq/...')`),
which is reliable; the **screen content is fully semantic** and is interacted with normally.
Adding `Semantics(label: …)` to the rail items would let the tests click the real nav — a
worthwhile a11y improvement to the app itself.

## Prerequisites

1. **System Chrome** at the default macOS path (override with `CHROME_PATH`). No
   Playwright-managed browser is downloaded — install with
   `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install`.
2. **TOTP must be OFF on the target backend.** It's an env toggle, not a code change:
   `AUTH_TOTP_ENABLED=false` (the VM compose sets it `true` in normal operation). With it on,
   login returns the TOTP enroll/verify step instead of a token and the suite can't sign in.
   Re-enable it after a run.

## Run

```bash
cd e2e
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install        # once
npx playwright test                                   # all specs
npx playwright test tests/01-login.spec.js            # one spec
BASE_URL=http://localhost:8080 npx playwright test    # against another backend
npx playwright show-report                            # HTML report
```

Config: `playwright.config.js` (single worker — the suite is one stateful storyline;
system Chrome with software GL so it renders headless).

## Specs

| File | Covers |
|------|--------|
| `01-login.spec.js` | HQ logs in through the real login screen and lands on the dashboard. |
| `02-hq-navigation.spec.js` | Every HQ section (main/sub agents, stores, inventory, batch, transactions, hierarchy, print-ops, reallocation, catalog, templates, companies) loads and renders. |

### Planned (next)

- `03-pos-sell.spec.js` — POS operator logs in, passes the PIN gate, sees a sellable SKU
  from the parent pool, taps **Sell** → draw-on-print reveals the PIN + prints.
- `04-create-and-fund.spec.js` — HQ creates a main agent → sub-agent → store and grants
  withdrawal limits (the full hierarchy-build flow).
