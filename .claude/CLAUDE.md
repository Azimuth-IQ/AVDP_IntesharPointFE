# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Inteshar Point** is a Flutter demo app for an Iraqi voucher distribution company. It talks to a Spring Boot + MongoDB backend (AVDP). The backend source lives at `/Users/ahmed/Desktop/ARP-Offline-Core/avdp_inteshar/src/main/java/...` and is the authoritative reference when the API behaves unexpectedly. The Postman collection is a sketch — trust the Java source over Postman.

---

## Commands

```bash
# Install / update packages
flutter pub get

# Run on a connected device or emulator
flutter run

# Analyze (zero warnings is the bar before declaring a milestone done)
flutter analyze

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Code generation (freezed + json_serializable — run after editing any model)
dart run build_runner build -d

# Watch mode for code generation
dart run build_runner watch -d
```

---

## Architecture

### State + routing

- **Riverpod** (`flutter_riverpod`) for all state. Providers are declared at the module level and consumed via `ref.watch` / `ref.read`.
- **GoRouter** (`routerProvider` in `lib/app/router.dart`) with a `refreshListenable` that fires on every `authStateProvider` change. All role-based redirects live in the router's `redirect` callback.
- The signed-in role (`EntityType`) determines which route prefix a user lands on: `/hq/*`, `/agent1/*`, `/agent2/*`, `/store/*`, or `/pos/*`.

### HTTP layer

`ApiClient` (`lib/core/api/api_client.dart`) wraps Dio. The `_AuthInterceptor` injects `Authorization: Bearer <token>` from `SessionStorage` on every request and converts `DioException` into `ApiException`.

**Three distinct response shapes from the backend — handle each differently:**

| Endpoint | Shape | How to parse |
|---|---|---|
| `POST /api/auth/login` | `{ "token": "..." }` (top-level, no envelope) | Read `response.data['token']` directly |
| All other endpoints | `{ "status": int, "message": "...", "data": T }` | Use `ApiClient.unwrap(response, parse)` |
| `GET /api/health/*` | Raw `Map<String,Object>` | Return `response.data` as-is |

### Session storage

`SessionStorage` (`lib/core/storage/session_storage.dart`) is a global singleton (`final sessionStorage = SessionStorage()`). It persists JWT, base URL, entity id, entity type, and phone to `SharedPreferences`. The base URL defaults to `http://localhost:8080` and is user-configurable in-app.

### Feature structure

Each feature under `lib/features/` follows: `data/` (repository) → `application/` (Riverpod controllers) → `presentation/` (pages). There is no use-case layer — one repository per feature is intentional for this demo.

### Models

Models are hand-written with `fromJson`/`toJson`/`copyWith` — **freezed code generation is not currently in use** even though it is in `pubspec.yaml`. Do not add `.freezed.dart`/`.g.dart` imports.

Key model conventions:
- All IDs are `String` (even when numeric on the wire).
- Money/amounts/prices are `String` on the wire; parse to `int` in the UI only.
- `Product` and `AppTransaction` carry `int? version` (Mongo `@Version`). Always round-trip `version` on PUTs — build update payloads from the last server response, not from in-memory copies.
- The transaction class is named `AppTransaction` (not `Transaction`) to avoid conflicts.

---

## Critical backend quirks

1. **`Entity.toJson()` has an `includeUsers` flag (default `false`).** Always use the default on meta-only PUTs. If you send existing users without plaintext passwords, the server will double-BCrypt the hash.

2. **`EntityHelper.updateEntity` removes the entity from its parent's `childrenIds`** (known backend bug). After any entity PUT, re-fetch the parent and, if it dropped the child id, PUT the parent again to restore the link.

3. **`DELETE /api/transactions/delete` takes a JSON body** `{ "id": "..." }`, not a query param. All other DELETEs use query params. See `TransactionRepository.delete`.

4. **`GET /api/entity/readwithchildren` returns `Map<Integer, List<Entity>>`** keyed by BFS depth as string integers (`"0"` = root, `"1"` = direct children, `"2"` = grandchildren). Do not assume the keys are parent IDs.

5. **`GET /api/inventory/product/readByEntity?entityId=`** filters on `currentOwner == entityId` only — not the historical `owners` list. No `/readBySku` or `/readByStatus` endpoint exists; filter client-side.

6. **`TransactionProcessor` does not filter by `ProductStatus`** when picking products to move. Always pre-flight check client-side that the source has ≥ `amount` `AVAILABLE` units of each SKU before submitting a transaction.

7. **`ProductStatus` is never changed by the backend** during a transaction. Only the POS flow changes it by calling `PUT /api/inventory/product/update` after a successful print.

8. **JWT expires after 24 h.** On a 401, clear session and redirect to `/login` — no silent re-login needed for this demo.

9. **Only `/api/auth/login` is unauthenticated.** Health endpoints, entity-create, everything else requires a JWT. A clean MongoDB has no users, so the app cannot bootstrap itself — see "Seeding a fresh backend" below.

10. **Transaction processor polls every 1 s.** Poll `GET /transactions/read?id=` every 1.5–2 s, cap at 30 s. Show `processMessage` verbatim on `FAILED` rows.

---

## Seeding a fresh backend

A clean MongoDB has no users, making login impossible. Seed the root admin directly via `mongosh` once:

```js
use avdp;
const BCRYPT_PASSWORD = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy";
db.entities.replaceOne(
  { _id: "inteshar-1" },
  {
    _id: "inteshar-1",
    meta: { name: "Inteshar", slogan: "lead the way, sir ...", description: "leading company in voucher distribution", logoUrl: "", backgroundUrl: "", sliderImagesUrl: [] },
    parent: "", type: "INTESHAR", childrenIds: [], productsIds: [],
    users: [{ id: "u-1", phone: "07701234567", password: BCRYPT_PASSWORD, role: "ADMIN" }]
  },
  { upsert: true }
);
```

Login: `07701234567` / `password`. Everything else can be built from inside the app using the "Seed demo" button (visible on the HQ dashboard when fewer than two entities exist).

MongoDB dev URI: `mongodb://admin:password@localhost:27017/avdp?authSource=admin`

---

## Role-based navigation

| `EntityType` | Home route | Available sections |
|---|---|---|
| `INTESHAR` | `/hq/home` | Hierarchy, Catalog (definitions), Inventory, Batch add, Transactions |
| `AGENT1` | `/agent1/home` | Hierarchy, Inventory, Transactions |
| `AGENT2` | `/agent2/home` | Hierarchy, Inventory, Transactions |
| `STORE` | `/store/home` | Inventory, Transactions, POS terminals |
| `USER` on `STORE` | `/pos/home` | POS voucher picker, Printer |

A `USER`-role login on a `STORE` entity is treated as a POS session (`isPosUser = true` in `AuthAuthenticated`). There is no backend `POS` entity type — the POS slot is a client-side filter over the store's `AVAILABLE` products where `currentOwner == storeId`.

---

## Bluetooth / printing

- `BluetoothService` (`lib/core/printing/bluetooth_service.dart`) wraps `flutter_blue_plus` for scan/connect/write.
- `EscPosBuilder` (`lib/core/printing/escpos_builder.dart`) builds 58 mm ESC/POS byte arrays using `esc_pos_utils_plus`.
- All supported printer models are 58 mm ESC/POS over Bluetooth — a single pipeline serves all of them.
- Target Android first; iOS Bluetooth Classic to non-MFi printers is unreliable.
- Android 12+ requires runtime `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` permissions before scanning.
- Persist the last-connected device ID to `SharedPreferences` for auto-reconnect on the next POS session.

---

## Shared widgets

- `AppScaffold` — navigation rail (tablet) / bottom nav (phone) per role; takes a `role` string matching `EntityType.name`.
- `EmptyState` — use on every list page when the list is empty.
- `ErrorState` — use on every `AsyncValue.error` path with a retry button.
- `RoleBadge` — colored chip showing entity type.
