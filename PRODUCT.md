# Product

## Register

product

## Users

Four roles in a telecom voucher-distribution hierarchy in Iraq (`INTESHAR → AGENT1 → AGENT2 → STORE`):

- **HQ / Platform Admin** (Flutter Web): manages voucher templates, the SKU catalog, inventory (single + batch), the entity hierarchy, and white-label branding. Power user, desk context, larger screens.
- **Governorate (AGENT1)** and **Distributor (AGENT2)**: mid-tier agents who move virtual balance/inventory to their children and browse their own (distributor also browses children read-only).
- **Store / POS (STORE / USER)**: a shop clerk at a thermal-printer POS, often on a phone/tablet, customer present, working fast. Needs the voucher reveal/print flow to be instant and unambiguous.

Context: Arabic-first (RTL default, English secondary). No real money in the system — balances are virtual credit. The leaf POS prints a prepaid voucher code on a 58 mm ESC/POS thermal receipt for an end customer.

## Product Purpose

Inteshar Point distributes prepaid telecom voucher codes (Asiacell, Zain, etc.) down a 4-tier agent tree using virtual balance, ending at a shop POS that prints/decrypts the code for a customer. Success = agents move inventory and complete sales quickly and correctly, with codes kept secure (decryption bound to the print event only) and each Main Agent able to apply its own white-label branding.

## Brand Personality

"Inteshar Sunburst" — confident, retail, warm-but-precise. Three words: **trustworthy, fast, branded**. A saturated marigold gold (`#F5B100`) is the single hero accent against deep ink and cool off-white surfaces; Codec Pro carries the whole type system with JetBrains Mono reserved for serials/PINs/MACs. The product should feel like a dependable point-of-sale tool with a distinct retail identity, not a generic admin panel. Money/codes are treated with care; status is friendly (rounded chips), not bureaucratic (rubber stamps).

## Anti-references

- Generic Material-default SaaS admin (purple seed color, stock components, no identity).
- Cream / sand / parchment "warm minimalism" — surfaces are deliberately cool off-white so the gold is the only warm note; do not drift warm.
- Editorial / publisher aesthetic (italic serif titles, tracked all-caps eyebrows above every section, print rules) — an earlier iteration leaned this way and was deliberately replaced by the retail-brand primitives.
- Anything that buries the voucher PIN or makes the POS reveal/print flow ambiguous or slow.

## Design Principles

1. **Tokens over one-offs.** Color, spacing, radius, shadow, and type all come from `IntesharColors/Spacing/Radii/Shadows/Type` and the `ThemeData`. A literal value in a widget is drift to be named and fixed.
2. **The tool disappears into the task.** Earned familiarity over novelty — standard affordances, consistent component vocabulary screen to screen, density where the role needs it.
3. **Every interactive element ships all its states.** Default, hover/pressed, focus, disabled, loading, error, empty. Lists use `EmptyState`; async errors use `ErrorState` with retry.
4. **Identity is carried by accent + type + the star mark**, never by tinting the body surface. One hero color, used for primary action / selection / state — not decoration.
5. **RTL and white-label are first-class.** Use directional insets/alignment; never hard-code the Sunburst gold where a brand override should flow through the theme.
6. **Security shows in the UI.** PINs are mono, revealed only through the audited print lifecycle, and treated as sensitive throughout.

## Accessibility & Inclusion

- Target WCAG AA: body text ≥ 4.5:1, large/bold text ≥ 3:1. The bright gold demands **ink** (not white) foreground in both light and dark modes — never white-on-gold.
- Full RTL (Arabic default) + LTR (English); all spacing/alignment uses directional (`EdgeInsetsDirectional`, `start/end`) values.
- Respect reduced-motion; keep motion to state/feedback (150–250 ms), no decorative choreography.
- POS touch targets ≥ 44×44 px; serial/PIN text selectable and high-contrast.
