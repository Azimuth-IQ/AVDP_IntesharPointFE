# Inteshar Point — Flutter Demo App: Plan

> **Audience:** an implementer model (Sonnet) that will read this file together with `instructions.md` and produce the full Flutter app in `lib/`.
>
> **Scope:** a *demo* application — the goal is to **showcase** the Inteshar Point business model and the AVDP backend to the client. Polish, clarity of flows, and visual fidelity matter more than handling every edge case.
>
> **Verified against backend source on 2026-05-15** at `/Users/ahmed/Desktop/ARP-Offline-Core/avdp_inteshar/src/main/java/...`. When this doc and the Java code disagree, the Java code wins — file an update.

---

## 1. Product context

### 1.1 The client

**Inteshar Point** is an Iraqi voucher distribution company. They sell prepaid telecom vouchers (Asiacell, Zain, Korek, …) through a multi-level distribution hierarchy. The demo must communicate:

- How stock flows from HQ → governorate → main distributor → shop → individual POS.
- How users at each level only see what is relevant to their role.
- How a voucher is physically *printed* at the last mile (thermal printer).

### 1.2 The hierarchy (5 logical levels)

| # | Business level | Backend `EntityType` | Example |
|---|----------------|----------------------|---------|
| 1 | HQ (the company) | `INTESHAR` | Inteshar |
| 2 | Governorate distributor | `AGENT1` | Baghdad Distribution |
| 3 | Local distributor (intra-governorate) | `AGENT2` | Rusafa Distribution |
| 4 | Merchant / shop | `STORE` | Waleed Mobile |
| 5 | POS (a signed-in terminal inside a shop) | *user inside `STORE`* + virtual sub-inventory | Counter 1 @ Waleed Mobile |

> Source-of-truth comments in `EntityType.java`: `INTESHAR // Root`, `AGENT1 // Governate Distributer`, `AGENT2 // Local Distributer`, `STORE // Store`.
>
> The backend exposes **four** entity types. **Level 5 (POS) is a `USER` belonging to a `STORE`**, with an additional client-side "POS slot" concept that holds a slice of the shop's available vouchers earmarked for printing. For the demo we treat each POS user as having a *virtual* sub-inventory derived from the parent shop's `currentOwner == storeId` products. We do **not** create a real `POS` entity (the backend doesn't have that type).

### 1.3 Supported thermal printers (Bluetooth, ESC/POS)

- X-Printer X50 (or similar X-series 58 mm)
- Sumi v2, Sumi v2s, Sumi v1, Sumi se, Sumi v2 pro
- Sunrise
- Capa z91
- Rovo, Rove plus

All are 58 mm Bluetooth ESC/POS printers — a single Bluetooth-printing pipeline serves all of them. We expose a **printer picker** so the user can pair / select any of these in the POS UI.

---

## 2. Backend API surface (verified against the Spring Boot source)

**Base URL:** `http://localhost:8080` (configurable in the app).
**Stack:** Spring Boot, MongoDB (`mongodb://admin:password@localhost:27017/avdp?authSource=admin`), JWT-secured.
**Auth:** `Authorization: Bearer <jwt>` on **every** endpoint. The only `permitAll` matcher in `SecurityConfig` is `/api/auth/**`.

### 2.1 Unauthenticated endpoints — only one

- `POST /api/auth/login` — `{ phone, password }` → **top-level** `{ "token": "..." }` (no envelope on this endpoint).

> The Postman collection marks several requests as `auth: noauth` (health checks, first entity create). **Those will 401 in reality.** Treat the Postman flags as Postman-side hints, not server truth. See §2.5 for how to bootstrap a clean backend.

### 2.2 Authenticated endpoints (envelope: `{ "status": int, "message": string, "data": T }`)

#### System health (`/api/health`)
- `GET /general | /ram | /cpu | /storage` — returns a **raw `Map<String,Object>`**, *not* wrapped in the envelope. Still requires JWT.

#### Entities (`/api/entity`)
- `POST /create` (HTTP 201) — body: `id`, `meta {name,slogan,description,logoUrl,backgroundUrl,sliderImagesUrl[]}`, `parent`, `type` (`INTESHAR|AGENT1|AGENT2|STORE`), `childrenIds[]`, `productsIds[]`, optional `users[]` (`{phone,password,role}` with `role ∈ {USER,ADMIN}`). `EntityHelper.createEntity` BCrypt-hashes user passwords and appends the new id to its parent's `childrenIds`.
- `GET /read?id=` and `GET /readall`.
- `GET /readwithchildren?id=` and alias `GET /getwithchildren?id=` — returns `Map<Integer, List<Entity>>` **keyed by BFS depth level** (0 = the root passed in, 1 = its direct children, 2 = grandchildren, …). The UI rebuilds the parent-child relationships from each node's `childrenIds`.
- `PUT /update` — **the `users` array IS re-processed on update** (passwords are re-BCrypted). It's also safe to omit it. ⚠️ The current implementation **removes** the entity id from its parent's `childrenIds` on update (see `EntityHelper.updateEntity` line 57) — appears to be a backend bug. Avoid edits that rely on the entity staying linked, or re-link manually.
- `DELETE /delete?id=` — also removes the id from the parent's `childrenIds`.

#### Inventory — Product *Definition* (`/api/inventory/definition`)
A definition is the catalog item, not stock.
- `POST /create` (HTTP 201) — `{id, name, description, imageUrl, defaultPrice, sku}` (all strings, including `defaultPrice`).
- `GET /read?id=`, `GET /readall`, `PUT /update`, `DELETE /delete?id=`.

#### Inventory — Product (`/api/inventory/product`)
A product is an individual voucher unit. Backed by Mongo with `@Version Long version` for optimistic locking.
- `POST /create` (HTTP 201) — `{id, productDefinition{…full embedded definition…}, status, serialNumber, pin, owners[], currentOwner}`. **`currentOwner` defaults to `owners.getLast()` if omitted**, but always send it explicitly.
- `GET /read?id=`, `GET /readall`.
- `GET /readByEntity?entityId=` — **the workhorse query**. It filters by **`currentOwner == entityId` only** (not by the `owners` history list).
- `PUT /update` — preserve and round-trip the `version` field returned by the server, otherwise updates may fail or duplicate. The helper falls back to looking up the existing version if the client doesn't send it (`InventoryHelper.updateProduct` lines 71–76).
- `DELETE /delete?id=`.

#### Transactions (`/api/transactions`)
A transaction moves stock by changing `currentOwner` on N products of matching SKU. **No inventory `status` field is touched by the backend** during a transfer. Also `@Version`-tracked.
- `POST /create` (HTTP 202 Accepted, "Transaction Queued") — body `{date "YYYY-MM-DD", time "HH:mm" (HH:MM is the docstring), sourceId, destinationId, lines:[{id, sku, amount, price, lineTotal}]}`. `status` is force-set to `PENDING` server-side regardless of what you send.
- An async `@Scheduled(fixedDelay = 1000)` `TransactionProcessor` runs every ~1 second: picks the next `PENDING`, marks it `PROCESSING`, then for each line:
  - finds `amount` products matching `productDefinition.sku == line.sku` AND `currentOwner == sourceId` (it **does not filter by status** — backend quirk, flag if it ever bites),
  - appends `destinationId` to each product's `owners` history and sets `currentOwner = destinationId`,
  - retries on `OptimisticLockingFailureException` up to 10× with linear backoff.
  - On success: `status = COMPLETED`, `processMessage = "Transaction processed successfully"`.
  - On insufficient stock or repeated failure: `status = FAILED`, `processMessage = "Error: …"` (e.g. `"Insufficient stock for SKU: AC5 at source: <id>"`).
- `GET /read?id=`, `GET /readall`, `PUT /update`.
- `DELETE /delete` — **takes a JSON body** `{ "id": "..." }`, not a query param.

> **Polling guidance:** Since the processor wakes once a second, polling `/read?id=` every 1.5–2 s is plenty. For a small transaction (≤ a few hundred lines) you'll see `COMPLETED` within 2–3 polls. Cap at ~30 s; if still `PROCESSING`, surface a "still processing" UI rather than hanging.

### 2.3 Canonical end-to-end story (from "Story Flow → First Time Installation")

The Postman collection ships a 10-step flow that mirrors a real deployment. With the security model in mind:

1. (Backend pre-seed — see §2.5 — produces a usable ADMIN user.)
2. **Login** as that admin → get JWT.
3. Create an `AGENT1` (Baghdad) entity under HQ.
4. `readwithchildren` HQ — verify Baghdad shows up at level 1.
5. Create a product *definition* (e.g. Asiacell 5000, SKU `AC5`).
6. Create a product unit on HQ (`owners=[hq]`, `currentOwner=hq`, `status=AVAILABLE`).
7. Create a transaction moving 1× `AC5` from HQ → Baghdad.
8. Poll the transaction `/read` until `status = COMPLETED`.
9. `readByEntity?entityId=baghdad` — confirm the unit's `currentOwner` is now Baghdad.

The demo must reproduce this story screen-by-screen.

### 2.4 Response shapes (concrete)

- **Login** (`POST /api/auth/login`): top-level `{ "token": "eyJhbGc..." }`. No `data` wrapper, no `status` field.
- **Everything else** (entities, definitions, products, transactions): `{ "status": <int>, "message": "...", "data": <payload> }`. `status` is the HTTP status code (200, 201, 202), not a boolean/string.
- **Health endpoints**: raw map, no envelope.
- The shared envelope class is `Core/Models/Response<T>` with `@JsonInclude(NON_NULL)`, so `data` is absent on error or empty responses.

### 2.5 Bootstrap problem (read this — it's a real gap)

Because `SecurityConfig` only `permitAll`s `/api/auth/**`, **every other endpoint requires a JWT**, and the JWT requires an existing user (`CustomUserDetailsService.loadUserByUsername` looks up an `Entity` by `users.phone`). A clean, freshly-deployed database has **no users**, so:

- You can't log in (no user exists).
- You can't create the root entity (entity-create requires auth).
- There is no `CommandLineRunner` / `@PostConstruct` seeder in the backend (verified by source search).

**Resolutions, in order of preference:**

1. **Manual Mongo seed** — insert a root INTESHAR entity with one ADMIN user directly via `mongosh` before the demo. The Flutter app's `Seed demo` button then only does steps 3–9 above (after a successful login). See `instructions.md` §7 for the snippet.
2. **Ask the backend team** to add a `CommandLineRunner` that seeds a default admin if `entities` is empty. Out of scope for the demo frontend, but worth flagging.
3. **Accept that this is a demo** — ship with a known-good Mongo dump that the operator restores once.

The Flutter app must therefore not assume it can bootstrap a 100% empty server. Make the "Seed demo" button check whether a login succeeds first; if not, surface a clear "Backend has no users — run the Mongo seed snippet from instructions.md §7" message.

---

## 3. App architecture

### 3.1 Tech choices

| Concern | Choice | Why |
|---|---|---|
| State management | **Riverpod** (`flutter_riverpod`) | Compact, testable, well-suited to async API state. |
| Routing | **GoRouter** | Declarative routes, role-aware redirects. |
| HTTP | **Dio** with an interceptor for JWT + base URL | Clean injection of the bearer token. |
| Local storage | **shared_preferences** for JWT + base URL; **flutter_secure_storage** for password (optional). | Simple, no SQLite needed for a demo. |
| Excel import | **excel** package (pure-Dart .xlsx reader) | Parse batch uploads without native deps. |
| File picking | **file_picker** | Pick `.xlsx` from disk on desktop/mobile. |
| Bluetooth printing | **flutter_blue_plus** + **esc_pos_utils_plus** (or **blue_thermal_printer** on Android) | All listed printers are 58 mm ESC/POS over Bluetooth Classic / BLE. |
| Forms/UI | Material 3, custom theme (Inteshar brand) | Looks credible to client. |
| Codegen | **freezed** + **json_serializable** for models | Stops drift between API and UI. |
| i18n | EN + AR (RTL), `flutter_localizations` + `intl` | The client is Iraqi — show Arabic. |

### 3.2 Folder layout (target state of `lib/`)

```
lib/
├── main.dart                       # bootstrap, ProviderScope, theme, locale
├── app/
│   ├── app.dart                    # MaterialApp.router + theme
│   ├── router.dart                 # GoRouter + role-based redirects
│   ├── theme.dart                  # Inteshar brand colors, M3 theme
│   └── locale.dart                 # EN/AR setup
├── core/
│   ├── api/
│   │   ├── api_client.dart         # Dio instance + interceptors
│   │   ├── auth_interceptor.dart   # injects Bearer token
│   │   ├── api_exception.dart
│   │   └── endpoints.dart          # path constants
│   ├── storage/
│   │   └── session_storage.dart    # JWT, baseUrl, current entity
│   ├── utils/
│   │   ├── id_generator.dart       # short ids for new entities/products
│   │   ├── excel_parser.dart       # batch xlsx → List<ProductDraft>
│   │   └── formatters.dart         # currency (IQD), date, time
│   └── printing/
│       ├── printer_registry.dart   # list of supported printer models
│       ├── bluetooth_service.dart  # scan / connect / disconnect
│       ├── escpos_builder.dart     # voucher receipt template (58 mm)
│       └── print_job.dart
├── features/
│   ├── auth/
│   │   ├── data/auth_repository.dart
│   │   ├── application/auth_controller.dart
│   │   └── presentation/
│   │       ├── splash_page.dart
│   │       └── login_page.dart
│   ├── entities/
│   │   ├── data/entity_repository.dart
│   │   ├── domain/{entity.dart, entity_type.dart, entity_meta.dart}
│   │   ├── application/{entity_tree_controller.dart, entity_form_controller.dart}
│   │   └── presentation/
│   │       ├── entity_tree_page.dart   # the hierarchy explorer
│   │       ├── entity_detail_page.dart
│   │       └── entity_form_page.dart   # create/edit
│   ├── inventory/
│   │   ├── data/{definition_repository.dart, product_repository.dart}
│   │   ├── domain/{product_definition.dart, product.dart, product_status.dart}
│   │   ├── application/{definitions_controller.dart, inventory_controller.dart, batch_import_controller.dart}
│   │   └── presentation/
│   │       ├── definitions_page.dart       # catalog management (HQ only)
│   │       ├── inventory_page.dart         # current entity's stock
│   │       ├── batch_add_page.dart         # manual / xlsx batch creation
│   │       └── product_detail_page.dart
│   ├── transactions/
│   │   ├── data/transaction_repository.dart
│   │   ├── domain/{transaction.dart, transaction_line.dart, transaction_status.dart}
│   │   ├── application/transactions_controller.dart
│   │   └── presentation/
│   │       ├── transactions_page.dart
│   │       └── new_transaction_page.dart
│   ├── pos/
│   │   ├── application/pos_controller.dart # holds POS-slot inventory slice
│   │   └── presentation/
│   │       ├── pos_home_page.dart          # voucher picker + sell button
│   │       ├── printer_picker_page.dart
│   │       └── voucher_receipt_preview.dart
│   └── diagnostics/
│       └── presentation/health_page.dart   # hidden behind long-press on logo
├── shared/
│   ├── widgets/
│   │   ├── app_scaffold.dart       # navigation rail / drawer per role
│   │   ├── role_badge.dart
│   │   ├── empty_state.dart
│   │   └── error_state.dart
│   └── extensions/
└── l10n/
    ├── app_en.arb
    └── app_ar.arb
```

### 3.3 Role-based navigation

The signed-in user's `entity.type` determines the navigation surface:

| Entity type | Tabs / menu items |
|---|---|
| **INTESHAR (HQ)** | Dashboard · Hierarchy (tree) · Catalog (definitions) · Inventory · **Batch add** · Transactions · Entities (create/manage) |
| **AGENT1 (Governorate)** | Dashboard · Children (AGENT2s) · Inventory · Transactions (incoming + outgoing to children) · Create child entity |
| **AGENT2 (Main distributor)** | Dashboard · Children (STOREs) · Inventory · Transactions · Create child entity |
| **STORE (Merchant)** | Dashboard · Inventory · Transactions (incoming) · **POS terminals** (list of POS users + a "Open POS" button) |
| **POS (user inside STORE)** | POS Home · My Slot · Printer · Sales log |

GoRouter does an authoritative redirect: if `currentEntity.type` doesn't match a route's allowed roles, send the user to their default home.

---

## 4. Feature specifications

### 4.1 Splash + Login
- Splash hits `GET /api/health/general`; on success goes to `/login` (or `/home` if a JWT already exists).
- Login form: phone (`07701234567` placeholder), password. Calls `POST /api/auth/login`, stores token + user identity, then fetches the user's entity (so we know the role) and routes accordingly.
- A "Server URL" gear in the corner lets you swap base URL for the demo (e.g. between localhost and a LAN IP).

### 4.2 Hierarchy / Entities (HQ-centric, but visible to all levels for their subtree)
- The **tree page** uses `GET /api/entity/readwithchildren?id=<my_entity_id>` and renders a collapsible tree.
- Each node shows: name, type badge, child count, product count, slogan.
- Tap → detail page. Detail page actions (gated by role):
  - **Edit** (admin of that entity or HQ)
  - **Add child** — opens entity form pre-filled with `parent=<current>` and a type picker constrained to one level below.
  - **Delete** (HQ only, with confirmation).
- Entity form supports `meta` fields and an inline **users** mini-form (phone, password, role) — visible only when creating an entity, since `update` doesn't accept `users`.

### 4.3 Product definitions (HQ only)
- List of all definitions (`/definition/readall`) with SKU, name, default price.
- Create/edit form: `name`, `description`, `imageUrl` (text field for demo; optional image picker later), `defaultPrice`, `sku`.
- Delete with confirmation.

### 4.4 Inventory
- Two views:
  1. **My inventory** — `readByEntity?entityId=<me>`, grouped by SKU, with counts of `AVAILABLE / PRINTED / DAMAGED`.
  2. **Drill into a child's inventory** — same endpoint with their id; available to HQ/AGENT1/AGENT2 for their descendants.
- Filter by SKU, by status. Search by serial.

### 4.5 Batch add (HQ only — adds stock onto the root inventory)
Two tabs:

- **Manual**
  - Pick a product definition (autocomplete by name/SKU).
  - Enter a quantity N.
  - Choose how serials/pins are sourced:
    - **Auto-generate** (e.g. `SN-{sku}-{yyyymmddHHmmss}-{i}` and a random PIN) — for demo.
    - **Sequential range** (start serial + start pin + increment).
  - Press **Create batch** → loops `POST /api/inventory/product/create` N times, showing a progress bar and a per-row success/failure list.

- **Excel import**
  - User picks an `.xlsx` (`file_picker`).
  - Expected columns: `sku`, `serialNumber`, `pin`, `status` (optional, default `AVAILABLE`).
  - We resolve `sku → product_definition_id` from `/definition/readall`.
  - Show a preview table with validation errors (unknown SKU, duplicate serial within the file, missing pin).
  - **Import** triggers the same per-row create loop with a progress indicator.

> Both methods set `owners=[currentEntityId]` and `currentOwner=currentEntityId`.

### 4.6 Transactions
- **List** (`/readall`, then filter client-side to "involving me as source or destination") with status chips.
- **Create transaction** (visible to HQ, AGENT1, AGENT2, STORE-to-POS):
  - Source = current entity (fixed).
  - Destination picker — only direct children of the current entity (uses `readwithchildren`).
  - **Lines**: pick a SKU + quantity + price (default from definition).
  - Submit → `POST /create`. After response, poll `GET /read?id=...` until status leaves `PENDING` (or stop after N tries — demo only).
- Transaction detail shows the line items, status badge, and a "Refresh" button.

### 4.7 POS (the most "demo-able" screen)

This is where the client will be wowed. The flow:

1. A STORE admin opens the **POS terminals** page and taps **Open POS** for a given POS user (or just "Anonymous POS" for the demo).
2. The POS Home shows the shop's `AVAILABLE` inventory grouped by definition as **big tappable cards** (e.g. "Asiacell 5000  ×42").
3. Tapping a card → opens the **voucher print sheet**:
   - Shows the next available serial/pin (a random `AVAILABLE` product of that SKU).
   - **Connect printer** button → opens **Printer Picker**.
   - **Print** button → builds an ESC/POS receipt (logo + shop name + SKU + denomination + serial + pin + barcode/QR + footer) and pushes it to the printer.
   - On success: `PUT /api/inventory/product/update` setting `status="PRINTED"` (and append a log entry locally).
4. A sales log shows the last N prints in this session.

#### Printer picker
- Lists the **supported models** (the device list above) as templates *and* scans Bluetooth for paired devices.
- User taps a discovered device → `connect()` → ✅ persisted to `shared_preferences` so subsequent prints don't re-pair.
- A **Test print** button prints a centered "Inteshar Point — Printer OK" receipt.

### 4.8 Diagnostics (hidden)
- Long-press the Inteshar logo on the login/dashboard → opens a hidden Diagnostics page showing the four health endpoints + the active base URL + the active JWT (masked).

---

## 5. UX / branding direction

- **Theme:** Material 3, primary color `#0E3A6B` (a dependable deep blue used by many Iraqi telecoms), secondary `#F5A623` (warm accent matching voucher posters). Light + dark.
- **Typography:** Cairo (Google Fonts) for Arabic + Latin — handles both scripts cleanly.
- **Layout:** Navigation rail on tablet/desktop, bottom-nav on phone.
- **Empty states:** every list page must have a friendly empty state with an illustration placeholder + "Create your first X" CTA.
- **Numbers:** IQD currency with Arabic numerals when locale=AR, Latin digits when locale=EN.
- **RTL:** enabled when locale=AR.
- **Demo data seeding:** a "Seed demo" button on the login screen (visible only when the entity list is empty and we're connected) runs the "First Time Installation" sequence end-to-end and lands you logged in as HQ admin with one Baghdad child + one definition + one product.

---

## 6. Non-goals (explicitly out of scope for the demo)

- Real payment processing.
- Real telecom integration (vouchers are synthetic).
- Multi-tenant production hardening (rate limiting, refresh tokens, etc.).
- Offline-first sync (the AVDP project has an offline core, but the demo can assume connectivity).
- Persisting POS slot inventory across reinstalls.
- Localizing every string on day one — start with the high-traffic screens (auth, navigation, POS).

---

## 7. Milestones

| M | Milestone | Definition of done |
|---|---|---|
| M0 | **Project skeleton** | `pubspec.yaml` updated, router + theme + Dio + Riverpod wired, splash + login render. |
| M1 | **Auth + session** | Login works against a running backend; JWT persisted; "Server URL" override works. |
| M2 | **Entity tree** | Tree explorer works; entity create/edit/delete works; role-based redirect works. |
| M3 | **Catalog + Inventory** | Product definitions CRUD; inventory-by-entity view with filters. |
| M4 | **Batch add** | Manual batch (auto-gen + range) and `.xlsx` import both create products. |
| M5 | **Transactions** | Create, list, detail, with polling on status. |
| M6 | **POS** | Voucher picker UI works, prints to a connected Bluetooth ESC/POS printer, marks product `PRINTED`. |
| M7 | **Polish + i18n** | AR + EN, RTL, empty states, demo seed button, branded splash. |

A Sonnet model implementing this should ship M0-M2 in one pass, then M3-M5, then M6 (printer work is the biggest unknown), then M7.

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Bluetooth printing on iOS is restrictive (Made-for-iPhone program). | For the demo target **Android** first; iOS prints can be added later or routed through a USB/network mode. Document this explicitly. |
| Fresh backend has no users → can't login → can't bootstrap (§2.5). | Ship a `mongosh` seed snippet in `instructions.md` §7. The "Seed demo" button only handles steps 3-9, not the initial admin. |
| Backend `EntityHelper.updateEntity` removes the entity from its parent's `childrenIds` (likely bug). | After every entity PUT, re-fetch the parent and, if needed, PUT the parent again to restore the link. Flag to backend team. |
| `TransactionProcessor` ignores `ProductStatus` when picking units to move (it grabs any product matching `sku + currentOwner`, including `PRINTED`/`DAMAGED`). | For the demo, never create `PRINTED`/`DAMAGED` products on the source side of a pending transfer. Add a client-side sanity check that the source has ≥ `amount` `AVAILABLE` units of the SKU before submitting. |
| `Product` and `Transaction` use Mongo `@Version` optimistic locking. | Always round-trip the server's `version` on PUTs. Don't reconstruct payloads from memory; copy from the last server response. |
| Backend may evolve; new endpoints appear. | Centralize all paths in `core/api/endpoints.dart` and all DTOs in `freezed` models so changes ripple to one place. |
| "POS as user" doesn't map to the 4-type backend. | POS slots are a client-side concept: a POS user is a `USER`-role login on a `STORE` entity; its slot inventory is a filter over the store's products. Document the gap so the backend team can add a `POS` type later without a front-end rewrite. |
| Excel files in the wild are messy. | Show a *preview* with validation before any API call; never fail silently. |
| Demo network instability. | Keep a small in-memory cache for entity tree + definitions, refreshed on pull-down. |

---

## 9. What "done" looks like for the demo

A presenter can:

1. Open the app on a fresh device, point it at a running backend, press **Seed demo**, and within 5 seconds be staring at the HQ dashboard.
2. Walk through the tree, add a Rusafa AGENT2 under Baghdad, add Waleed Mobile STORE under Rusafa, and see them appear live.
3. Add 100 Asiacell 5000 vouchers via Excel.
4. Move 30 of them HQ → Baghdad → Rusafa → Waleed in three quick transactions.
5. Sign out, sign in as Waleed's POS user, tap an Asiacell 5000 card, connect the X-Printer X50, and **physically print a real voucher receipt**.
6. Switch the app to Arabic and re-walk the same flow with RTL layout.

If all six work, the demo succeeds.
