# Inteshar Point — Flutter Demo App: Implementation Instructions

> **You are a Sonnet model implementing this Flutter app.** Read `plan.md` first for product context. This file is your operating manual: step-by-step build order, conventions, code templates, gotchas. **Follow it top-to-bottom.**
>
> **Verified against backend source on 2026-05-15.** API shapes, security rules, and pitfalls reflect the actual Java code, not just the Postman doc. Postman is a starting sketch; the controllers/helpers in `/Users/ahmed/Desktop/ARP-Offline-Core/avdp_inteshar/src/main/java/...` are authoritative.
>
> **Working directory:** `/Users/ahmed/Desktop/Inteshar Frontend/inteshar/` (a Flutter project that currently only has the stock `main.dart`).
>
> **Backend reference:** the source under `/Users/ahmed/Desktop/ARP-Offline-Core/avdp_inteshar/src/main/java/...` is the source of truth. The Postman collection (`AVDP - Inteshar.postman_collection.json`) is a useful sketch but **not authoritative** — several of its `auth: noauth` flags don't match `SecurityConfig`, and a couple of response shapes differ. When the Postman doc and the code disagree, **trust the code**.

---

## 0. Ground rules

1. **Demo, not production.** Optimize for happy-path clarity. Show clear progress indicators, friendly error messages, and never crash the UI on a 4xx — surface the message and let the user retry.
2. **No fake screens.** Every screen must be wired to a real endpoint (or a real local action like Bluetooth scan). The only synthetic data lives behind the **Seed demo** button.
3. **Match the Java DTOs exactly.** Field names are `camelCase` on the wire (`defaultPrice`, `currentOwner`, `lineTotal`, `processMessage`, …). Don't rename them.
4. **IDs are strings.** Even when they look numeric (`"1"`, `"101"`). Send and parse as `String`.
5. **Money is a string** in the API (`"5000"`). Parse to `int` in the UI layer; serialize back as a string on writes.
6. **DELETE for transactions takes a JSON body**, not a query param. The other DELETEs use query params. Don't mix them up.
7. **Login response is top-level `{ "token": "..." }`** — no envelope. Every other authenticated endpoint returns `{ "status": int, "message": "...", "data": ... }`. Health endpoints return a raw `Map`. Three shapes, no exceptions.
8. **Only `/api/auth/login` is unauthenticated.** Every other endpoint (including `/api/health/*` and the first `/api/entity/create`) requires a JWT. The "Seed demo" button cannot bootstrap an empty database — see §7.
9. **Run flutter analyze + flutter test before declaring a milestone done.** Fix every analyzer warning.
10. **Commit per milestone** with a conventional commit message (`feat(auth): login + JWT persistence`, etc.). The repo is currently not a git repo at the Flutter project root — `git init` if needed.
11. **When in doubt, prefer fewer abstractions.** This is a demo. Don't introduce a use-case layer on top of a repository on top of a service; one repository per feature is enough.
12. **Do not invent endpoints.** If you need one that isn't in the Java controllers, surface a TODO and stub the UI; don't fabricate the API.

---

## 1. Bootstrap (Milestone M0)

### 1.1 Update `pubspec.yaml`

Replace the dependencies block with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # State + routing
  flutter_riverpod: ^2.5.1
  go_router: ^14.2.7

  # HTTP + serialization
  dio: ^5.7.0
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

  # Storage
  shared_preferences: ^2.3.2
  flutter_secure_storage: ^9.2.2

  # Files / Excel
  file_picker: ^8.1.2
  excel: ^4.0.6

  # Bluetooth thermal printing
  flutter_blue_plus: ^1.32.12
  esc_pos_utils_plus: ^2.0.4
  image: ^4.2.0   # for ESC/POS image conversion

  # UX
  google_fonts: ^6.2.1
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.8.0

flutter:
  uses-material-design: true
  generate: true   # for l10n
  assets:
    - assets/images/
```

Run:
```
flutter pub get
```

### 1.2 Android Bluetooth permissions

Edit `android/app/src/main/AndroidManifest.xml` and add (above `<application>`):

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

Set `minSdkVersion 21` (or higher) in `android/app/build.gradle.kts` / `build.gradle` if it's lower.

### 1.3 iOS

In `ios/Runner/Info.plist` add:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Inteshar Point uses Bluetooth to print vouchers on thermal printers.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Inteshar Point uses Bluetooth to print vouchers on thermal printers.</string>
```

> iOS Bluetooth Classic to non-MFi printers is unreliable. Target Android first for the demo.

### 1.4 Create the folder structure

Create every folder listed in `plan.md` §3.2. Empty `.gitkeep` files are fine for now. Replace the stock `lib/main.dart` with the bootstrap below.

### 1.5 `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: IntesharApp()));
}
```

### 1.6 `lib/app/app.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/app/theme.dart';

class IntesharApp extends ConsumerWidget {
  const IntesharApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Inteshar Point',
      debugShowCheckedModeBanner: false,
      theme: intesharLightTheme,
      darkTheme: intesharDarkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
    );
  }
}
```

### 1.7 `lib/app/theme.dart`

Brand colors:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _seed = Color(0xFF0E3A6B);

ThemeData _build(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: GoogleFonts.cairoTextTheme(
      b == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

final intesharLightTheme = _build(Brightness.light);
final intesharDarkTheme = _build(Brightness.dark);
```

### 1.8 `lib/app/router.dart`

Use GoRouter with a redirect based on auth state. Routes (sketch):

```
/splash
/login
/diagnostics            (hidden)
/home                   → role-dispatched
/hq/...                 (INTESHAR only)
/agent1/...             (AGENT1 only)
/agent2/...             (AGENT2 only)
/store/...              (STORE only)
/pos/...                (POS user session)
```

Implement `routerProvider` as a `Provider<GoRouter>` that depends on `authStateProvider`. On unauthenticated state, redirect to `/login` for any non-login/non-splash route.

---

## 2. Core API client (Milestone M0/M1)

### 2.1 `lib/core/api/endpoints.dart`

```dart
class Endpoints {
  // Auth
  static const login = '/api/auth/login';

  // Health
  static const healthGeneral = '/api/health/general';
  static const healthRam = '/api/health/ram';
  static const healthCpu = '/api/health/cpu';
  static const healthStorage = '/api/health/storage';

  // Entities
  static const entityCreate = '/api/entity/create';
  static const entityRead = '/api/entity/read';
  static const entityReadAll = '/api/entity/readall';
  static const entityReadWithChildren = '/api/entity/readwithchildren';
  static const entityUpdate = '/api/entity/update';
  static const entityDelete = '/api/entity/delete';

  // Definitions
  static const definitionCreate = '/api/inventory/definition/create';
  static const definitionRead = '/api/inventory/definition/read';
  static const definitionReadAll = '/api/inventory/definition/readall';
  static const definitionUpdate = '/api/inventory/definition/update';
  static const definitionDelete = '/api/inventory/definition/delete';

  // Products
  static const productCreate = '/api/inventory/product/create';
  static const productRead = '/api/inventory/product/read';
  static const productReadAll = '/api/inventory/product/readall';
  static const productReadByEntity = '/api/inventory/product/readByEntity';
  static const productUpdate = '/api/inventory/product/update';
  static const productDelete = '/api/inventory/product/delete';

  // Transactions
  static const transactionCreate = '/api/transactions/create';
  static const transactionRead = '/api/transactions/read';
  static const transactionReadAll = '/api/transactions/readall';
  static const transactionUpdate = '/api/transactions/update';
  static const transactionDelete = '/api/transactions/delete'; // DELETE with body
}
```

### 2.2 `lib/core/api/api_client.dart`

Riverpod-provided Dio:

- `baseUrl` from `SessionStorage.baseUrl` (default `http://localhost:8080`).
- Adds `Authorization: Bearer <token>` if the token exists.
- Wraps `DioException` into `ApiException(message, statusCode, raw)` so the UI never sees raw Dio errors.
- Auto-decodes JSON. Handle the **three response shapes**:
  1. **Login** (`/api/auth/login`): top-level `{ "token": "..." }`. Don't try to unwrap.
  2. **Standard envelope** (entities, definitions, products, transactions): `{ "status": <int>, "message": "...", "data": <payload> }`. Expose `T unwrap<T>(Response r, T Function(dynamic) parse)` that returns `parse(r.data['data'])`. `status` here is the HTTP status (200/201/202), so it always indicates success when present — error responses come back as non-2xx HTTP and are caught by the Dio error path. If `r.data['message']` looks like an error and `r.data['data']` is missing, throw `ApiException(r.data['message'], r.statusCode)`.
  3. **Health** (`/api/health/*`): raw `Map<String,Object>`. No envelope. Return as-is.
- The standard envelope class is `Core/Models/Response<T>` with `@JsonInclude(NON_NULL)` server-side — `data` is omitted on null, so check existence before reading.

### 2.3 Session storage

```dart
class SessionStorage {
  Future<void> setToken(String token);
  Future<String?> getToken();
  Future<void> clear();

  Future<void> setBaseUrl(String url);
  Future<String> getBaseUrl(); // default 'http://localhost:8080'

  Future<void> setCurrentEntityId(String id);
  Future<String?> getCurrentEntityId();
}
```

Back it with `SharedPreferences`. No need for secure storage at this stage (a comment is enough).

---

## 3. Models (codegen)

Use `freezed` + `json_serializable`. For every model below, generate `model.dart`, `model.freezed.dart`, `model.g.dart` via:

```
dart run build_runner build -d
```

### 3.1 Enums

```dart
enum EntityType { INTESHAR, AGENT1, AGENT2, STORE }
enum UserRole { USER, ADMIN }
enum ProductStatus { AVAILABLE, PRINTED, DAMAGED }
enum TransactionStatus { PENDING, PROCESSING, COMPLETED, FAILED }
```

Serialize as uppercase strings (use `@JsonValue('AVAILABLE')` etc.).

### 3.2 EntityMeta

```dart
@freezed
class EntityMeta with _$EntityMeta {
  factory EntityMeta({
    @Default('') String name,
    @Default('') String slogan,
    @Default('') String description,
    @Default('') String logoUrl,
    @Default('') String backgroundUrl,
    @Default([]) List<String> sliderImagesUrl,
  }) = _EntityMeta;
  factory EntityMeta.fromJson(Map<String, dynamic> json) => _$EntityMetaFromJson(json);
}
```

### 3.3 Entity

```dart
@freezed
class Entity with _$Entity {
  factory Entity({
    required String id,
    required EntityMeta meta,
    @Default('') String parent,
    required EntityType type,
    @Default([]) List<String> childrenIds,
    @Default([]) List<String> productsIds,
    @Default([]) List<EntityUser> users,
  }) = _Entity;
  factory Entity.fromJson(Map<String, dynamic> json) => _$EntityFromJson(json);
}

@freezed
class EntityUser with _$EntityUser {
  factory EntityUser({
    @Default('') String id,
    required String phone,
    @Default('') String password,  // empty on reads — server never returns plaintext
    required UserRole role,
  }) = _EntityUser;
  factory EntityUser.fromJson(Map<String, dynamic> json) => _$EntityUserFromJson(json);
}
```

> Server-side `EntityHelper.updateEntity` **does** process and BCrypt the `users` array on PUT. So:
> - When you don't want to change users, omit the `users` field on the update payload.
> - When you do want to add/change a user, send them with their plaintext password — the server will re-BCrypt anything that doesn't start with `$2a$/$2b$/$2y$`.
> - The server never returns plaintext passwords on reads — incoming `users[].password` will be a BCrypt hash. Don't send that back unmodified for unrelated updates (or you double-hash a hash, which is wrong); strip `users` on plain meta-edits.
>
> Also note: `EntityHelper.updateEntity` currently **removes** the entity id from its parent's `childrenIds` (see plan.md §8 risks). Compensate by re-fetching the parent after update and PUT-ing it back with `childrenIds` re-included if it dropped.

### 3.4 ProductDefinition

```dart
@freezed
class ProductDefinition with _$ProductDefinition {
  factory ProductDefinition({
    required String id,
    required String name,
    @Default('') String description,
    @Default('') String imageUrl,
    required String defaultPrice,   // string per API
    required String sku,
  }) = _ProductDefinition;
  factory ProductDefinition.fromJson(Map<String, dynamic> json) =>
      _$ProductDefinitionFromJson(json);
}
```

### 3.5 Product

```dart
@freezed
class Product with _$Product {
  factory Product({
    required String id,
    int? version,                            // Mongo @Version — round-trip on PUT
    required ProductDefinition productDefinition,
    required ProductStatus status,
    required String serialNumber,
    required String pin,
    @Default([]) List<String> owners,
    required String currentOwner,
  }) = _Product;
  factory Product.fromJson(Map<String, dynamic> json) => _$ProductFromJson(json);
}
```

> `version` is a Mongo optimistic-locking counter. **Always send back the `version` you received from the last server read** on updates. If you mint a fresh `Product` from memory and PUT it without `version`, the server falls back to a DB lookup (per `InventoryHelper.updateProduct`), but you risk lost updates if anyone else is writing. Better: build update payloads from the last server response.
>
> When **creating** a product manually, omit `version` (Mongo assigns it).

### 3.6 Transaction

```dart
@freezed
class TransactionLine with _$TransactionLine {
  factory TransactionLine({
    required String id,
    required String sku,
    required String amount,
    required String price,
    required String lineTotal,
  }) = _TransactionLine;
  factory TransactionLine.fromJson(Map<String, dynamic> json) =>
      _$TransactionLineFromJson(json);
}

@freezed
class Transaction with _$Transaction {
  factory Transaction({
    @Default('') String id,
    int? version,                                 // Mongo @Version
    required String date,                         // YYYY-MM-DD
    required String time,                         // HH:mm (server doc says HH:MM)
    required String sourceId,
    required String destinationId,
    @Default(TransactionStatus.PENDING) TransactionStatus status,
    @Default([]) List<TransactionLine> lines,
    @Default('') String processMessage,           // populated by TransactionProcessor on COMPLETED/FAILED
  }) = _Transaction;
  factory Transaction.fromJson(Map<String, dynamic> json) =>
      _$TransactionFromJson(json);
}
```

> The async processor sets `processMessage = "Transaction processed successfully"` on completion, or `"Error: Insufficient stock for SKU: X at source: Y"` on failure. Show this string verbatim in the transaction detail page — it's the most informative thing the backend gives you.

---

## 4. Feature wiring (Milestones M1 → M5)

For each feature, follow this pattern: **repository → controller (Riverpod `AsyncNotifier`) → page**.

### 4.1 Auth (M1)

`AuthRepository.login(phone, password)` POSTs `{phone, password}` to `/api/auth/login` and parses the **top-level** `{ "token": "..." }` response. **There is no envelope on this endpoint** — don't try to unwrap `data`.

Controller flow:
1. POST → get `token`.
2. Store in `SessionStorage` (Dio interceptor will start sending it).
3. Call `/api/entity/readall` and find the entity whose `users[].phone == phone`. That's the signed-in user's home entity. Persist `entityId` and `entityType`.
4. Decide the home route from `entityType` (`INTESHAR` → `/hq/home`, `AGENT1` → `/agent1/home`, etc.). For `USER`-role on a `STORE`, route to `/pos/home`.

Expose `authStateProvider` returning `AuthState.signedIn(entity, role)` or `signedOut`.

Login page UX:
- Phone field (no validation beyond non-empty for demo).
- Password field, obscured.
- "Server URL" small button → bottom sheet to change base URL.
- "Sign in" button with loading state.
- If login fails with 401 and `entity/readall` (using a probe call) returns 401 too, show a one-time hint: **"The backend has no users yet. Run the Mongo seed snippet in instructions.md §7 to create the first admin."** Don't try to bootstrap from the app — see §7 for why.

### 4.2 Entities (M2)

Repository methods: `create`, `read`, `readAll`, `readWithChildren`, `update`, `delete`. **Trim `users` from update payloads.**

`entity_tree_controller.dart`:
- Loads the **current user's entity** with `/readwithchildren?id=<me>`. The response `data` is `Map<Integer, List<Entity>>` keyed by **BFS depth level** (`"0"` = the entity passed in, `"1"` = direct children, `"2"` = grandchildren, …).
- Flatten that map and re-index by `parent` field to build a `Map<String, List<Entity>>` for the tree widget. (Do **not** assume keys are parent ids — they're depth integers serialized as JSON object keys, i.e. strings `"0"`, `"1"`, etc.)

`entity_tree_page.dart`: uses an `ExpansionTile` per node. Each node card shows badge (type), name, slogan, and a 3-dot menu (Edit / Add child / Delete).

`entity_form_page.dart`: builds a `meta` block + a `parent` (locked when adding a child) + a `type` dropdown. On create, it also accepts a one-user mini form (phone, password, role). On submit, generate the `id` client-side using `core/utils/id_generator.dart` (short timestamp+rand string).

### 4.3 Catalog — product definitions (M3)

Straight CRUD list page. The "Add" FAB opens a sheet with the five fields. Validate that SKU is unique among existing definitions (client-side check).

### 4.4 Inventory (M3)

`inventory_page.dart` calls `readByEntity(entityId: currentEntity.id)`. Group by `productDefinition.sku`, show a card per SKU with totals split by status. Tap → drill into a flat list of individual products of that SKU.

For HQ/AGENT1/AGENT2: a top selector lets you switch to "Viewing inventory of: [child]". Reuse `readByEntity` with the child's id.

### 4.5 Batch add (M4) — **HQ only**

Implement two tabs:

**Manual:**
- Definition picker (autocomplete on name + SKU).
- Quantity (int input).
- Serial/PIN strategy:
  - **Auto**: `serial = "SN-${sku}-${now}-${i}"`, `pin = randomDigits(8)`.
  - **Range**: start serial (string), start pin (string), each incremented numerically.
- Submit → loop and `productRepository.create()` for each. Use a streamed progress bar (`StreamController<double>` or Riverpod `StateProvider<double>`). Show a per-row result list (✓/✗) so partial failures don't disappear.

**Excel:**
- `file_picker` to pick `.xlsx`.
- Parse with the `excel` package. First row = headers. Required headers: `sku`, `serialNumber`, `pin`. Optional: `status`.
- Validate: SKU exists in definitions (load definitions on page open), no duplicate `serialNumber` *within* the file, all required cells non-empty.
- Preview table with red highlights for invalid rows.
- "Import valid rows" button → same per-row create loop.

Both modes set `owners = [currentEntity.id]` and `currentOwner = currentEntity.id`.

### 4.6 Transactions (M5)

`new_transaction_page.dart`:
- `sourceId` = current entity (read-only).
- `destinationId` = picker over `readwithchildren(currentEntity.id)` at **level 1**. (The map is keyed by depth; `result[1]` is the list of direct children.) **Only direct children are valid destinations.**
- Lines table: pick SKU, amount, price (prefilled from `defaultPrice`), `lineTotal` auto-calculated.
- **Pre-flight sanity check** (client-side): before submitting, call `readByEntity?entityId=<source>` and verify the source has ≥ `amount` products matching each line's SKU **with `status == AVAILABLE`**. The backend processor doesn't filter by status — it will happily move a `PRINTED` voucher if it's the only one matching SKU+source. So we filter on the client to keep the demo honest.
- Submit → `POST /create` (returns HTTP 202 with `status: PENDING` regardless of what you sent).
- Navigate to the transaction detail page and start a polling timer **every 1.5 s for up to 30 s** calling `/read?id=`. The async `TransactionProcessor` wakes every 1 s, so small transactions land in `COMPLETED` within 2-3 polls. Show the status badge change; on `FAILED`, surface `processMessage`.

`transactions_page.dart`: list with status chips, search by source/destination, tap to detail. Render `processMessage` as a secondary line under failed transactions.

> **DELETE transaction uses a JSON body.** Implement `delete(String id)` as `dio.delete(path, data: {"id": id})`.

---

## 5. POS + Bluetooth printing (Milestone M6)

This is the hardest milestone. Stage it in small steps:

### 5.1 Printer registry

```dart
// lib/core/printing/printer_registry.dart
const supportedPrinterModels = <PrinterModel>[
  PrinterModel(name: 'X-Printer X50', paperMm: 58, profile: 'XP58'),
  PrinterModel(name: 'Sumi v1',       paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi v2',       paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi v2s',      paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi v2 pro',   paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sumi SE',       paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Sunrise',       paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Capa Z91',      paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Rovo',          paperMm: 58, profile: 'default'),
  PrinterModel(name: 'Rove Plus',     paperMm: 58, profile: 'default'),
];
```

The "profile" is informational — they are all 58 mm ESC/POS so the same byte stream works. We just label the connection nicely for the demo.

### 5.2 Bluetooth service

Use `flutter_blue_plus` for scanning + connection. Wrap in a service:

```dart
class BluetoothService {
  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 8)});
  Future<void> connect(BluetoothDevice device);
  Future<void> disconnect();
  Future<void> send(List<int> bytes);   // writes to the printer characteristic
  bool get isConnected;
  BluetoothDevice? get currentDevice;
}
```

> Many ESC/POS BT devices expose a single write characteristic on a SPP-like service. After connecting, discover services, find the first writable characteristic, and write to it in chunks (≤512 bytes).

### 5.3 ESC/POS receipt template

```dart
List<int> buildVoucherReceipt({
  required String companyName,    // "Inteshar Point"
  required String shopName,
  required String posLabel,       // "Counter 1"
  required String operatorPhone,
  required String denomination,   // "Asiacell 5000 IQD"
  required String serial,
  required String pin,
  required DateTime timestamp,
}) {
  final profile = CapabilityProfile.getDefault();
  final g = Generator(PaperSize.mm58, profile);
  final out = <int>[];

  out.addAll(g.text(companyName, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)));
  out.addAll(g.text(shopName, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.text(posLabel, styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.hr());
  out.addAll(g.text(denomination, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  out.addAll(g.feed(1));
  out.addAll(g.text('Serial: $serial', styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.text('PIN:    $pin',    styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
  out.addAll(g.feed(1));
  out.addAll(g.qrcode(pin));
  out.addAll(g.hr());
  out.addAll(g.text(timestamp.toIso8601String(), styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.text('Operator: $operatorPhone', styles: const PosStyles(align: PosAlign.center)));
  out.addAll(g.feed(2));
  out.addAll(g.cut());
  return out;
}
```

### 5.4 POS flow

`pos_home_page.dart` (signed in as a `USER` on a `STORE`):
1. Loads `readByEntity(currentStoreId)`, filters `status == AVAILABLE`, groups by `productDefinition.sku`.
2. Renders cards: SKU, name, count, price. Big finger targets.
3. Tap → bottom sheet:
   - Picks the first `AVAILABLE` product of that SKU (peel it from the in-memory list).
   - Shows serial + pin masked + denomination.
   - "Connect printer" button if not connected. Opens `printer_picker_page.dart`.
   - "Print voucher" button (disabled until connected).
4. On print:
   - Build receipt bytes (5.3).
   - Send via `BluetoothService.send(...)`.
   - On success: `productRepository.update(product.copyWith(status: ProductStatus.PRINTED))`.
   - Append to the on-screen sales log (in-memory list).
5. On failure: show a SnackBar and *do not* mark the product as printed.

### 5.5 Printer picker UX

- Top section: **Supported models** chips (informational — tapping shows the user what's expected).
- Middle section: **Paired / nearby devices** populated from `flutter_blue_plus.scanResults` stream.
- Tap a device → connect spinner → ✅, then **Test print** button to verify (prints a one-line "Inteshar Point — Printer OK 🖨️" — but **no emoji in ESC/POS unless we render to an image**; keep text plain).
- Save the device id to `SharedPreferences` so the next session auto-reconnects.

---

## 6. Polish & i18n (Milestone M7)

1. Add `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb`. Wire `AppLocalizations` from `flutter_localizations`.
2. Translate at minimum: app title, nav items, login screen, POS home, the "Seed demo" button.
3. RTL: when `locale == ar`, ensure `Directionality` works out of the box (MaterialApp handles this automatically when `supportedLocales` is set correctly).
4. Empty states: every list page must use `shared/widgets/empty_state.dart` when the list is empty.
5. Error states: every `AsyncValue.error` path must use `shared/widgets/error_state.dart` with a retry button.
6. Branded splash: a centered "Inteshar Point" mark with a small loading dot. Long-press → diagnostics page.
7. Add a small **About** entry in the drawer listing the supported printer models.

---

## 7. Bootstrapping a fresh backend (`mongosh` seed) + "Seed demo" button

### 7.1 Why this is a two-step process

`SecurityConfig` only `permitAll`s `/api/auth/**`. Entity-create requires a JWT, and the JWT requires an existing user (`CustomUserDetailsService` looks up `Entity` by `users.phone`). On a clean Mongo, **the Flutter app cannot create the first user**. Someone has to seed the root admin directly into Mongo before the demo.

There is no `CommandLineRunner` / `@PostConstruct` seeder in the backend (verified by source search). Until the backend team adds one, use the snippet below.

### 7.2 Step 1 — `mongosh` seed (run once per fresh database)

The dev URI is `mongodb://admin:password@localhost:27017/avdp?authSource=admin`. Connect and paste:

```js
use avdp;

// BCrypt hash of the literal string "password" (cost 10). Pre-computed — do not regenerate at runtime.
const BCRYPT_PASSWORD = "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy";

db.entities.replaceOne(
  { _id: "inteshar-1" },
  {
    _id: "inteshar-1",
    meta: {
      name: "Inteshar",
      slogan: "lead the way, sir ...",
      description: "leading company in voucher distribution",
      logoUrl: "",
      backgroundUrl: "",
      sliderImagesUrl: []
    },
    parent: "",
    type: "INTESHAR",
    childrenIds: [],
    productsIds: [],
    users: [{
      id: "u-1",
      phone: "07701234567",
      password: BCRYPT_PASSWORD,
      role: "ADMIN"
    }]
  },
  { upsert: true }
);

print("Seeded HQ admin: phone=07701234567 password=password");
```

After this you can log in with `07701234567` / `password`. Anything else can be built from inside the Flutter app.

> If you need a different password, generate the BCrypt hash with `htpasswd -bnBC 10 "" yourpw | tr -d ':\n'` (Linux/macOS) or any BCrypt utility — the cost must be 10 to match the server's `BCryptPasswordEncoder`.

### 7.3 Step 2 — "Seed demo" button in the Flutter app

Trigger: visible on the login page after a successful test login (or wired to a small "Populate demo data" button on the HQ dashboard). It runs **only after the user has a valid JWT**. The button should be hidden once `entity/readall` returns more than one entity.

```dart
Future<void> seedDemo({required String hqId}) async {
  // Pre-condition: caller is signed in as HQ admin. hqId is the seeded root id.

  // 1. AGENT1 — Baghdad
  await entityRepo.create(Entity(
    id: 'baghdad-1',
    meta: EntityMeta(
      name: 'Baghdad',
      slogan: 'Full Cover ... From Karkh to Rusafa',
      description: 'Distribution of Baghdad',
    ),
    parent: hqId,
    type: EntityType.AGENT1,
  ));

  // 2. AGENT2 — Rusafa (under Baghdad)
  await entityRepo.create(Entity(
    id: 'rusafa-1',
    meta: EntityMeta(name: 'Rusafa', description: 'Rusafa local distributor'),
    parent: 'baghdad-1',
    type: EntityType.AGENT2,
  ));

  // 3. STORE — Waleed Mobile, with a USER for POS login
  await entityRepo.create(Entity(
    id: 'waleed-1',
    meta: EntityMeta(name: 'Waleed Mobile', description: 'Voucher retail'),
    parent: 'rusafa-1',
    type: EntityType.STORE,
    users: [EntityUser(phone: '07701112222', password: 'password', role: UserRole.USER)],
  ));

  // 4. Product definition — Asiacell 5000
  final def = await definitionRepo.create(ProductDefinition(
    id: 'def-ac5',
    name: 'Asiacell 5000',
    description: 'Asiacell 5000 IQD Voucher',
    imageUrl: '',
    defaultPrice: '5000',
    sku: 'AC5',
  ));

  // 5. Five sample products on HQ
  for (var i = 1; i <= 5; i++) {
    await productRepo.create(Product(
      id: 'prod-${100 + i}',
      productDefinition: def,
      status: ProductStatus.AVAILABLE,
      serialNumber: 'SN10${i.toString().padLeft(2, '0')}',
      pin: 'PIN10${i.toString().padLeft(2, '0')}',
      owners: [hqId],
      currentOwner: hqId,
    ));
  }

  // 6. Transaction: move 1 unit HQ → Baghdad as a live demo
  await transactionRepo.create(Transaction(
    date: DateTime.now().toIso8601String().substring(0, 10),
    time: TimeOfDay.now().format(<context>),
    sourceId: hqId,
    destinationId: 'baghdad-1',
    lines: [TransactionLine(id: 'line_1', sku: 'AC5', amount: '1', price: '5000', lineTotal: '5000')],
  ));
}
```

After seeding, refresh the dashboard and walk the demo. If the button is pressed twice, the entity creates will fail with duplicate-id errors — wrap each call in a `try/catch` that ignores `409`/duplicate-key responses so re-pressing the button doesn't break the UI.

---

## 8. Common pitfalls — read this before you ship

1. **`/api/entity/update` accepts and re-BCrypts `users`.** If you only meant to update meta, **omit `users` from the PUT payload** (otherwise you'll double-hash an existing hash). If you do need to add/change users, send the new ones with plaintext passwords.
2. **`EntityHelper.updateEntity` removes the entity from its parent's `childrenIds`** (line 57 — looks like a bug: `parent.getChildrenIds().remove(entity.getId())`). After every entity PUT, re-fetch the parent and PUT it again if it dropped the child id. Flag the bug to backend in `## 11. Field notes`.
3. **`/api/transactions/delete` takes a JSON body** `{ "id": "..." }`, not a query param. Special-case the repository method.
4. **Prices, amounts, and lineTotals are strings on the wire.** Validate that they're parseable to int before sending, but always serialize as strings.
5. **`readwithchildren` returns `Map<Integer, List<Entity>>` keyed by BFS depth** (0 = the root, 1 = its direct children, 2 = grandchildren). Don't index it by parent id.
6. **`readByEntity` filters on `currentOwner == entityId`** only — not on the historical `owners` list. There is no `/readBySku` or `/readByStatus` — filter client-side.
7. **`ProductStatus` does NOT change automatically** when a transaction completes. The processor only flips `currentOwner` (and appends to `owners`). The status is only changed when *we* PUT `/product/update`, which is what the POS does after a successful print.
8. **`TransactionProcessor` does not filter by `ProductStatus`** when picking units to move. It'll grab any product matching `sku + currentOwner`, including `PRINTED`/`DAMAGED`. Always pre-flight check on the client (see §4.6).
9. **Login response is top-level `{ "token": "..." }`** — no envelope, no `data`. The Postman test script suggests both shapes; the real server only returns the flat form.
10. **Only `/api/auth/login` is unauth.** Health, entity-create, everything else requires a JWT. A clean DB has no users → no JWT possible → see §7 for the Mongo seed.
11. **`Product` and `Transaction` carry a `@Version Long version`** for Mongo optimistic locking. Round-trip the version on PUTs by building update payloads from the last server response, not from in-memory copies.
12. **Transaction processor wakes every 1 s** (`@Scheduled(fixedDelay = 1000)`). Polling at 1.5–2 s intervals is fine. Cap at 30 s.
13. **`Transaction.processMessage`** is the friendliest failure detail you'll get (e.g. `"Error: Insufficient stock for SKU: AC5 at source: hq-1"`). Show it verbatim on `FAILED` rows.
14. **JWT expires after 24 h** (hard-coded in `JwtService`). Silent re-login on 401 is overkill for the demo — just show "Session expired, please sign in again" and bounce to `/login`.
15. **Bluetooth on Android 12+** needs runtime permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`). Request them before scanning; surface a clear denial dialog.
16. **The `excel` package is slow on huge files.** For demo, cap imports at 5,000 rows and show a warning beyond that.
17. **POS users aren't a backend concept.** A POS session in this demo is just a `USER`-role login on a STORE. The "POS slot inventory" is purely a UI grouping over the STORE's products where `currentOwner == storeId`.
18. **The MongoDB dev URI** is `mongodb://admin:password@localhost:27017/avdp?authSource=admin` (see `application.properties`). Keep this handy for the seed snippet in §7.

---

## 9. Acceptance walkthrough

Before declaring the demo done, walk through this script *on a real Android device with a real X-Printer X50*:

1. Operator runs the `mongosh` seed snippet from §7.2 (one-time).
2. Fresh install → splash → login screen → tap "Server URL" → confirm `http://<lan-ip>:8080` → save.
3. Login as `07701234567` / `password` → land on HQ home.
4. Tap **Seed demo** on the HQ dashboard → see Baghdad, Rusafa, Waleed Mobile, Asiacell 5000 definition, 5 products on HQ, and an HQ → Baghdad transaction that goes from PENDING → COMPLETED within ~2 seconds.
5. Open the hierarchy tree — see Inteshar → Baghdad → Rusafa → Waleed Mobile rendered as a tree.
6. Catalog → add a definition "Zain 10000" (SKU `Z10`, price `10000`).
7. Batch add → Manual → 50× Asiacell 5000 with auto-gen. Watch progress bar fill.
8. Inventory → confirm 54 AVAILABLE Asiacells (50 + 5 from seed minus 1 already moved to Baghdad).
9. Transactions → new transaction → HQ → Baghdad → 30× AC5 → submit → status moves PENDING → PROCESSING → COMPLETED within polling window.
10. Repeat: Baghdad → Rusafa → 20× AC5; Rusafa → Waleed → 10× AC5.
11. Sign out → sign in as `07701112222` / `password` (the POS USER on Waleed Mobile from the seed).
12. POS Home → 10 AC5 cards visible → tap one.
13. Printer picker → tap X-Printer X50 in nearby devices → connect.
14. Test print → receipt comes out.
15. Print voucher → physical receipt with serial + PIN + QR.
16. Back to POS Home → AC5 count is now 9. Inventory page reflects 1 PRINTED.
17. Switch locale to AR in settings → app flips RTL → repeat step 12 — labels are translated.

If any step fails, fix it before declaring M7 done.

---

## 10. Hand-off note

When you (Sonnet) finish a milestone:

- Output a short summary of what changed and which Postman endpoints you exercised.
- Note any endpoint mismatches or surprises in a section at the bottom of this file (`## 11. Field notes` — append, don't rewrite).
- Run `flutter analyze` and paste the result. Zero warnings is the bar.
- Do not auto-commit; surface the diff and wait for the human to OK it before `git commit`.

Good luck. Build it like the client is sitting next to you.
