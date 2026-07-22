import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/logo_loader.dart';
import 'package:inteshar/core/printing/print_queue.dart';
import 'package:inteshar/core/printing/rovo_printer.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
import 'package:inteshar/core/api/error_mapper.dart' show friendlyError;
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos/data/pos_self_repository.dart';
import 'package:inteshar/features/chat/presentation/chat_thread_screen.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/pos/presentation/pos_account_panel.dart';
import 'package:inteshar/features/pos/presentation/pos_sales_panel.dart';
import 'package:inteshar/features/pos/presentation/pos_statement_panel.dart';
import 'package:inteshar/features/pos/presentation/printer_picker_page.dart';
import 'package:inteshar/shared/widgets/map_location_picker.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_backdrop.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

class PosHomePage extends ConsumerStatefulWidget {
  const PosHomePage({super.key});

  @override
  ConsumerState<PosHomePage> createState() => _PosHomePageState();
}

/// Sentinel governorate bucket for region-free (untagged) vouchers, kept distinct
/// from a real governorate name in the drill-down grouping.
const String _kRegionFree = '\u0000region-free';

class _PosHomePageState extends ConsumerState<PosHomePage> with WidgetsBindingObserver {
  List<SellableSku>? _sellable;
  AgentBalance? _balance;
  List<String> _sliderUrls = const [];
  List<String> _recentKeys = const []; // B-064: recently sold SKU keys (quick-sell)
  Object? _error;
  bool _loading = true;
  String _search = '';
  int _tab = 0; // bottom nav: 0=Store, 1=الحسابات, 2=التقارير, 3=التواصل, 4=الحساب

  // Drill-down navigation state: Home (companies) → Governorate (only when a
  // company spans >1 region bucket) → Card types. Null [_company] == the home step.
  String? _company;      // selected company key ('' = the "Other" bucket)
  bool _govChosen = false;
  String? _gov;          // chosen governorate; null (with [_govChosen]) = region-free

  // B-065: when the app was backgrounded, re-lock the session on return if it was
  // away long enough to be a walk-away — but NOT for the brief background caused by
  // a Share sheet or a Rovo/Sunmi print intent (those return in seconds).
  DateTime? _backgroundedAt;
  static const _relockAfter = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Gate the POS terminal behind a PIN lock on every session start.
    // The lock page (or setup page, if no PIN is configured) handles
    // authentication; once the session is unlocked we load the inventory.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPinGate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && DateTime.now().difference(since) >= _relockAfter) {
        // Left unattended — drop the unlock flag and send the operator back to the PIN.
        ref.read(posUnlockedProvider.notifier).state = false;
        if (mounted) context.go('/pos/pin-lock');
      }
    }
  }

  /// If the session is not yet unlocked, redirect to the PIN lock screen and
  /// let it handle the setup vs. verify decision. If already unlocked (the
  /// operator navigated back to home during the same session), load normally.
  void _checkPinGate() {
    if (!mounted) return;
    if (!ref.read(posUnlockedProvider)) {
      context.go('/pos/pin-lock');
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authStateProvider).valueOrNull;
      if (auth is! AuthAuthenticated) throw Exception('Not authenticated');

      final api = ref.read(apiClientProvider);
      final repo = ProductRepository(api);
      // Draw-on-print: the store holds NO cards — it sells from its parent Main Agent's
      // pool. Load the SKUs it can sell (the pool's available count + how many its
      // withdrawal limit can afford); a sale draws one card from the pool on reveal.
      final sellable = await repo.sellable(entityId: auth.entity.id);
      // Balance (withdrawal limit) is a nice-to-have on the POS — a failure here must not
      // block selling, so it's fetched best-effort.
      AgentBalance? balance;
      try {
        balance = await PricingRepository(api).balance(entityId: auth.entity.id);
      } catch (_) {}
      // HQ-managed home slider comes from the resolved session brand (fetched once at
      // login via /api/entity/branding), so no extra call on every refresh.
      final slider = auth.brand.sliderUrls;
      // B-064: recently sold SKUs (device-local) power the quick-sell row.
      final recent = await sessionStorage.getRecentPosSkus();
      if (mounted) {
        setState(() {
          _sellable = sellable;
          _balance = balance;
          _sliderUrls = slider;
          _recentKeys = recent;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final auth = ref.watch(authStateProvider).valueOrNull;
    // White-label: show the owning Main Agent's logo in the app bar when set.
    final agentLogo = auth is AuthAuthenticated ? auth.brand.agentLogoUrl : '';
    // Show the shop's own trade name as the title (falls back to a generic label).
    final shopName = (auth is AuthAuthenticated && auth.entity.meta.name.isNotEmpty)
        ? auth.entity.meta.name
        : l.posHome;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onLongPress: () => context.push('/diagnostics'),
          child: Row(
            children: [
              if (agentLogo.trim().isNotEmpty)
                Image.network(
                  agentLogo,
                  height: 26,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => IntesharStar(size: 22, color: cs.onSurface),
                )
              else
                IntesharStar(size: 22, color: cs.onSurface),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'CodecPro', fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.3, height: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.posHomeLiveCounter,
                    style: TextStyle(fontFamily: 'CodecPro', fontSize: 11, color: cs.onSurfaceVariant, letterSpacing: 0.2, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Consumer(
            builder: (ctx, ref, _) {
              final ps = ref.watch(bluetoothServiceProvider);
              final isConnected = ps.status == PrinterStatus.connected;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.push<void>(ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        // Neutral printer icon — the connected device may be the Sunmi/Rovo
                        // inner thermal head, not Bluetooth, so don't imply a radio.
                        Icon(isConnected ? Icons.print : Icons.print_disabled_outlined, size: 16, color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? (ps.deviceName ?? l.posPrinterConnected) : l.posHomeSetupPrinter,
                          style: TextStyle(
                            fontFamily: 'CodecPro',
                            fontSize: 12,
                            color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: l.signOut,
            onPressed: () async {
              // Reset the PIN unlock flag before logging out so re-entry
              // always requires PIN verification.
              ref.read(posUnlockedProvider.notifier).state = false;
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      // Only the active tab is built, so the statement/sales fetches and the chat's
      // background polling never run until their tab is opened. The Store tab's
      // drill-down state lives on this State, so it survives tab switches.
      body: BrandBackdrop(child: _tabBody(l)),
      // POS bottom nav (سستم تطبيق A92-A95): Store (sell), الحسابات (statement),
      // التقارير (purchased cards), الحساب (profile). Printer setup lives inside الحساب.
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.storefront_outlined), selectedIcon: const Icon(Icons.storefront), label: _ar ? 'المتجر' : 'Store'),
          // "كشف الحساب" (statement), disambiguated from tab 4 "الحساب" (profile).
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: _ar ? 'كشف الحساب' : 'Statement'),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: _ar ? 'التقارير' : 'Reports'),
          NavigationDestination(icon: const Icon(Icons.forum_outlined), selectedIcon: const Icon(Icons.forum), label: _ar ? 'التواصل' : 'Chat'),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: _ar ? 'الحساب' : 'Profile'),
        ],
      ),
    );
  }

  /// Builds only the selected tab (lazy) — see the body comment above.
  Widget _tabBody(AppLocalizations l) {
    switch (_tab) {
      case 1:
        return const PosStatementPanel();
      case 2:
        return const PosSalesPanel();
      case 3:
        return _PosChatTab();
      case 4:
        return PosAccountPanel(onOpenPrinter: _openPrinterPicker, onSignOut: _signOut);
      default:
        return _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorState(error: _error!, onRetry: _load)
                : _buildBody(l);
    }
  }

  void _openPrinterPicker() =>
      Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const PrinterPickerPage()));

  Future<void> _signOut() async {
    ref.read(posUnlockedProvider.notifier).state = false;
    await ref.read(authStateProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  // ── Drill-down grouping ─────────────────────────────────────────────────────

  /// Company key → its sellable rows. Key '' groups vouchers with no company.
  Map<String, List<SellableSku>> _companyGroups() {
    final m = <String, List<SellableSku>>{};
    for (final s in _sellable ?? const <SellableSku>[]) {
      m.putIfAbsent((s.companyName ?? '').trim(), () => []).add(s);
    }
    return m;
  }

  /// Distinct governorate buckets for [rows] (region-free represented by
  /// [_kRegionFree]), named governorates first then region-free last.
  List<String> _buckets(List<SellableSku> rows) {
    final set = <String>{};
    for (final s in rows) {
      final g = (s.governorate ?? '').trim();
      set.add(g.isEmpty ? _kRegionFree : g);
    }
    final list = set.toList()
      ..sort((a, b) {
        if (a == _kRegionFree) return 1;
        if (b == _kRegionFree) return -1;
        return a.compareTo(b);
      });
    return list;
  }

  /// The SKU cards for the current (company, chosen bucket), filtered by search.
  List<SellableSku> _currentCards() {
    var rows = _companyGroups()[_company] ?? const <SellableSku>[];
    if (_govChosen) {
      rows = rows.where((s) {
        final g = (s.governorate ?? '').trim();
        return _gov == null ? g.isEmpty : g == _gov;
      }).toList();
    }
    if (_search.isEmpty) return rows;
    final q = _search.toLowerCase();
    return rows
        .where((s) => s.name.toLowerCase().contains(q) || s.sku.toLowerCase().contains(q))
        .toList();
  }

  /// B-064: the recently sold SKUs that are still sellable now (available > 0),
  /// in recency order, resolved against the current pool. Powers the quick-sell row.
  List<SellableSku> _recentSellables() {
    final sellable = _sellable ?? const <SellableSku>[];
    final sep = SessionStorage.recentPosSkuSep;
    final byKey = {for (final s in sellable) '${s.sku}$sep${s.governorate ?? ''}': s};
    final out = <SellableSku>[];
    for (final k in _recentKeys) {
      final s = byKey[k];
      if (s != null && s.available > 0) out.add(s);
      if (out.length >= 6) break;
    }
    return out;
  }

  /// B-064: every sellable SKU matching [q] across ALL companies/governorates —
  /// the home-step global search that skips the company→region→card drill.
  List<SellableSku> _globalMatches(String q) {
    final query = q.trim().toLowerCase();
    return (_sellable ?? const <SellableSku>[])
        .where((s) =>
            s.name.toLowerCase().contains(query) ||
            s.sku.toLowerCase().contains(query) ||
            (s.companyName ?? '').toLowerCase().contains(query))
        .toList();
  }

  void _openCompany(String companyKey, List<SellableSku> rows) {
    final buckets = _buckets(rows);
    setState(() {
      _company = companyKey;
      _search = '';
      if (buckets.length > 1) {
        _govChosen = false; // route through the governorate step
        _gov = null;
      } else {
        _govChosen = true; // single bucket — straight to cards
        _gov = buckets.first == _kRegionFree ? null : buckets.first;
      }
    });
  }

  void _openBucket(String bucket) => setState(() {
        _govChosen = true;
        _gov = bucket == _kRegionFree ? null : bucket;
        _search = '';
      });

  void _back() {
    final rows = _companyGroups()[_company] ?? const <SellableSku>[];
    final multiBucket = _buckets(rows).length > 1;
    setState(() {
      _search = '';
      if (_govChosen && multiBucket) {
        _govChosen = false; // cards → governorate
        _gov = null;
      } else {
        _company = null; // → home
        _govChosen = false;
        _gov = null;
      }
    });
  }

  // ── Step router ─────────────────────────────────────────────────────────────

  Widget _buildBody(AppLocalizations l) {
    // سستم A92: selling is blocked until the shop confirms its location once.
    final auth = ref.watch(authStateProvider).valueOrNull;
    final entity = auth is AuthAuthenticated ? auth.entity : null;
    if (entity != null &&
        entity.type == EntityType.STORE &&
        entity.profile?.locationConfirmedAt == null) {
      return _LocationGate(onConfirmed: () async {
        // Re-fetch the entity so the gate lifts.
        await ref.read(authStateProvider.notifier).refresh();
        if (mounted) _load();
      });
    }
    if (_company == null) return _homeStep(l);
    final rows = _companyGroups()[_company] ?? const <SellableSku>[];
    if (!_govChosen && _buckets(rows).length > 1) return _governorateStep(l, rows);
    return _cardsStep(l);
  }

  String _companyLabel(String key) =>
      key.isEmpty ? (_ar ? 'أخرى' : 'Other') : key;

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  int _gridCols() => switch (context.screenSize) {
        ScreenSize.desktop => 4,
        ScreenSize.tablet => 3,
        ScreenSize.mobile => 2,
      };

  // Home: HQ slider + a grid of telecom companies (printing companies).
  Widget _homeStep(AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    final groups = _companyGroups();
    final keys = groups.keys.toList()
      ..sort((a, b) => _companyLabel(a).toLowerCase().compareTo(_companyLabel(b).toLowerCase()));

    final searching = _search.trim().isNotEmpty;
    final matches = searching ? _globalMatches(_search) : const <SellableSku>[];
    final recents = searching ? const <SellableSku>[] : _recentSellables();

    // SKU-card grid geometry, reused for the recents row and the global results.
    final skuExtent = switch (context.screenSize) {
      ScreenSize.desktop => 240.0,
      ScreenSize.tablet => 210.0,
      ScreenSize.mobile => 172.0,
    };
    final skuRowHeight = context.screenSize == ScreenSize.mobile ? 236.0 : 250.0;

    return MaxWidthBox(
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header(l, title: l.posHomePickDenomination, subtitle: l.posHomeCounterSubtitle)),
            // Global search: type a company/name/SKU and sell straight from the
            // results — no company→region→card drill for a known card (B-064).
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l.posHomeSearchHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _search = ''),
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
            ),
            if (searching) ...[
              if (matches.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: EmptyState(message: l.posHomeNoMatches(_search)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: skuExtent,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: skuRowHeight,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _SkuCard(sellable: matches[i], onTap: () => _showVoucher(matches[i])),
                      childCount: matches.length,
                    ),
                  ),
                ),
            ] else ...[
              if (_sliderUrls.isNotEmpty)
                SliverToBoxAdapter(child: _HomeSlider(urls: _sliderUrls)),
              // Quick-sell: recently sold cards as a one-tap horizontal row.
              if (recents.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Text(
                      _ar ? 'الأكثر مبيعاً' : 'Recent',
                      style: IntesharType.display(18, color: cs.onSurface, w: FontWeight.w800),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: skuRowHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: recents.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) => SizedBox(
                        width: skuExtent,
                        child: _SkuCard(sellable: recents[i], onTap: () => _showVoucher(recents[i])),
                      ),
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Text(
                    _ar ? 'اختر الشركة' : 'Choose a company',
                    style: IntesharType.display(18, color: cs.onSurface, w: FontWeight.w800),
                  ),
                ),
              ),
              if (keys.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: EmptyState(message: l.posHomeNoVouchers, actionLabel: l.retryButton, onAction: _load),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _gridCols(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: 150,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final key = keys[i];
                        final rows = groups[key]!;
                        return _CompanyCard(
                          name: _companyLabel(key),
                          logoUrl: rows.firstWhere((s) => (s.companyLogoUrl ?? '').isNotEmpty, orElse: () => rows.first).companyLogoUrl,
                          cardTypes: rows.length,
                          onTap: () => _openCompany(key, rows),
                        );
                      },
                      childCount: keys.length,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // Governorate step: shown only when the chosen company spans >1 region bucket.
  Widget _governorateStep(AppLocalizations l, List<SellableSku> rows) {
    final buckets = _buckets(rows);
    return MaxWidthBox(
      child: Column(
        children: [
          _header(l, title: _companyLabel(_company!), subtitle: _ar ? 'اختر المحافظة' : 'Choose a governorate', onBack: _back),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _gridCols(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                mainAxisExtent: 118,
              ),
              itemCount: buckets.length,
              itemBuilder: (context, i) {
                final b = buckets[i];
                final count = rows.where((s) {
                  final g = (s.governorate ?? '').trim();
                  return b == _kRegionFree ? g.isEmpty : g == b;
                }).length;
                return _GovCard(
                  label: b == _kRegionFree ? (_ar ? 'بدون تخصيص' : 'Region-free') : b,
                  cardTypes: count,
                  onTap: () => _openBucket(b),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Card-types step: the SKUs (with artwork) for the chosen company/governorate.
  Widget _cardsStep(AppLocalizations l) {
    final cards = _currentCards();
    final all = _companyGroups()[_company] ?? const <SellableSku>[];
    final subtitle = _govChosen && _gov != null
        ? _gov!
        : (_ar ? 'اختر نوع البطاقة' : 'Choose a card type');
    final tileExtent = switch (context.screenSize) {
      ScreenSize.desktop => 240.0,
      ScreenSize.tablet => 210.0,
      ScreenSize.mobile => 172.0,
    };
    final rowHeight = context.screenSize == ScreenSize.mobile ? 236.0 : 250.0;

    return MaxWidthBox(
      child: Column(
        children: [
          _header(l, title: _companyLabel(_company!), subtitle: subtitle, onBack: _back),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              decoration: InputDecoration(hintText: l.posHomeSearchHint, prefixIcon: const Icon(Icons.search, size: 18)),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (cards.isEmpty)
            Expanded(
              child: EmptyState(
                message: all.isEmpty ? l.posHomeNoVouchers : l.posHomeNoMatches(_search),
                actionLabel: l.retryButton,
                onAction: _load,
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: tileExtent,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    mainAxisExtent: rowHeight,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (context, i) {
                    final s = cards[i];
                    return _SkuCard(sellable: s, onTap: () => _showVoucher(s));
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Shared step header: optional back arrow, title/subtitle, and the balance tally.
  Widget _header(AppLocalizations l, {required String title, String? subtitle, VoidCallback? onBack}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack != null ? 8 : 20, 20, 20, 6),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: Icon(_ar ? Icons.arrow_forward : Icons.arrow_back, color: cs.onSurface),
              tooltip: l.posHomeCancel,
              onPressed: onBack,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: IntesharType.display(24, color: cs.onSurface, w: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _BalanceTally(balance: _balance),
        ],
      ),
    );
  }

  void _showVoucher(SellableSku sku) {
    // A successful draw consumes one card from the parent pool. We can't optimistically
    // patch the in-memory count (the backend picks the card), so just reload the sellable
    // counts from the server once the sheet closes after a sale.
    var consumed = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // After a draw the PIN/QR are shown once and must not be discarded by a swipe or
      // scrim tap. PopScope(canPop:false) blocks the back gesture; disabling drag + scrim
      // closes the remaining dismiss paths so a sold voucher can only be dismissed by Done/Print.
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _VoucherSheet(
        sku: sku,
        onConsumed: () {
          consumed = true;
          // B-064: remember this SKU so it surfaces in the quick-sell row next time.
          sessionStorage.pushRecentPosSku(sku.sku, sku.governorate ?? '');
        },
        onPrinted: () => Navigator.pop(ctx),
      ),
    ).whenComplete(() {
      // After a sale, re-fetch so the pool counts match the source of truth.
      if (consumed) _load();
    });
  }
}

// ── Printer tab ───────────────────────────────────────────────────────────────

class _BalanceTally extends StatelessWidget {
  final AgentBalance? balance;
  const _BalanceTally({required this.balance});

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: IntesharColors.saffron, borderRadius: BorderRadius.circular(IntesharRadii.md), boxShadow: IntesharShadows.ctaShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            ar ? 'الرصيد' : 'BALANCE',
            style: TextStyle(fontFamily: 'CodecPro', fontSize: 10, color: IntesharColors.ink.withValues(alpha: 0.65), letterSpacing: 1.4, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            balance == null ? '—' : Formatters.iqd(balance!.available),
            style: TextStyle(fontFamily: 'CodecPro', fontSize: 19, color: IntesharColors.ink, fontWeight: FontWeight.w900, letterSpacing: -0.4, height: 1),
          ),
        ],
      ),
    );
  }
}

// ── Home slider (HQ-managed) ──────────────────────────────────────────────────

/// Auto-advancing image carousel for the POS home, sourced from the HQ root
/// entity's `sliderImagesUrl`. Broken/slow URLs degrade to a neutral placeholder.
class _HomeSlider extends StatefulWidget {
  final List<String> urls;
  const _HomeSlider({required this.urls});

  @override
  State<_HomeSlider> createState() => _HomeSliderState();
}

class _HomeSliderState extends State<_HomeSlider> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.urls.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || !_controller.hasClients) return;
        final next = (_page + 1) % widget.urls.length;
        _controller.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: LayoutBuilder(builder: (context, constraints) {
        // Slides are cropped 16:9 at upload — render in a matching frame so
        // nothing gets re-cropped; height-capped (and centered) on wide screens.
        final height = (constraints.maxWidth * 9 / 16).clamp(0.0, 280.0);
        return Center(
          child: SizedBox(
            width: height * 16 / 9,
            height: height,
            child: _frame(cs),
          ),
        );
      }),
    );
  }

  Widget _frame(ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(IntesharRadii.lg),
      child: Stack(
        children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => Image.network(
                  widget.urls[i],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => Container(
                    color: cs.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant, size: 32),
                  ),
                  loadingBuilder: (ctx, child, progress) =>
                      progress == null ? child : Container(color: cs.surfaceContainerHighest),
                ),
              ),
              if (widget.urls.length > 1)
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.urls.length, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active ? IntesharColors.saffron : Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Company card ──────────────────────────────────────────────────────────────

class _CompanyCard extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final int cardTypes;
  final VoidCallback onTap;
  const _CompanyCard({required this.name, required this.logoUrl, required this.cardTypes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final hasLogo = (logoUrl ?? '').trim().isNotEmpty;
    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(IntesharRadii.lg),
          boxShadow: IntesharShadows.elev1,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: hasLogo
                    ? Image.network(
                        logoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _logoFallback(cs, name),
                      )
                    : _logoFallback(cs, name),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
            const SizedBox(height: 2),
            Text(
              ar ? '$cardTypes نوع' : '$cardTypes types',
              style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoFallback(ColorScheme cs, String name) => Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: IntesharColors.saffron, borderRadius: BorderRadius.circular(26)),
        child: Text(
          name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
          style: IntesharType.display(22, color: IntesharColors.ink, w: FontWeight.w900),
        ),
      );
}

// ── Governorate card ──────────────────────────────────────────────────────────

class _GovCard extends StatelessWidget {
  final String label;
  final int cardTypes;
  final VoidCallback onTap;
  const _GovCard({required this.label, required this.cardTypes, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(IntesharRadii.lg),
          boxShadow: IntesharShadows.elev1,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on_outlined, color: IntesharColors.saffronDeep, size: 26),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.1),
            ),
            const SizedBox(height: 2),
            Text(
              ar ? '$cardTypes نوع' : '$cardTypes types',
              style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SKU card (card type with artwork) ─────────────────────────────────────────

class _SkuCard extends StatelessWidget {
  final SellableSku sellable;
  final VoidCallback onTap;
  const _SkuCard({required this.sellable, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final s = sellable;
    final hasImg = (s.imageUrl ?? '').trim().isNotEmpty;

    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(IntesharRadii.lg),
          boxShadow: IntesharShadows.elev1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card-type artwork (fixed height so the tile can never overflow); a
            // gradient + SKU chip stands in when no image is configured.
            SizedBox(
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImg)
                    Image.network(
                      s.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _artFallback(cs, s.sku),
                      loadingBuilder: (ctx, child, progress) =>
                          progress == null ? child : Container(color: cs.surfaceContainerHighest),
                    )
                  else
                    _artFallback(cs, s.sku),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: StampPill(label: '× ${s.affordable}', color: IntesharColors.sage),
                  ),
                ],
              ),
            ),
            // Text + CTA fill the remaining bounded height — no Spacer overflow.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.price > 0 ? Formatters.iqd(s.price) : (ar ? 'السعر غير محدَّد' : 'Price not set'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.mono(14, color: cs.onSurface, w: FontWeight.w800),
                    ),
                    const Spacer(),
                    BrandCTAButton(label: l.posHomeSell, leading: Icons.sell_outlined, onPressed: onTap, height: 36, fontSize: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artFallback(ColorScheme cs, String sku) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [IntesharColors.saffron, IntesharColors.saffronDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          sku,
          style: IntesharType.mono(20, color: IntesharColors.ink, w: FontWeight.w900, letterSpacing: 1),
        ),
      );
}

// ── Voucher sheet ───────────────────────────────────────────────────────────

class _VoucherSheet extends ConsumerStatefulWidget {
  final SellableSku sku;
  // Fired the instant a card is drawn from the pool (a successful sale) so the parent
  // can reload the pool counts on close.
  final VoidCallback onConsumed;
  final VoidCallback onPrinted;

  const _VoucherSheet({required this.sku, required this.onConsumed, required this.onPrinted});

  @override
  ConsumerState<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends ConsumerState<_VoucherSheet> {
  // The PIN stays hidden until the operator EXPLICITLY taps "Sell". That single tap calls
  // /product/draw, which on the backend atomically claims one card from the parent Main
  // Agent's pool (AVAILABLE->PRINTED), debits the withdrawal limit per tier, and returns
  // the decrypted code. Selling consumes the voucher and cannot be undone. A per-attempt
  // idempotency key makes a retry over a flaky link return the SAME sale, never a 2nd card.
  late final String _clientRef;
  Product? _sent;
  int _receiptNo = 0;
  String? _operationId; // B-054: this sale's PrintOperation id, for confirmPrint
  // Wraps the on-screen receipt preview so a Rovo/intent print can capture it to a PNG.
  final GlobalKey _receiptKey = GlobalKey();
  String? _agentLogoUrl;
  String? _companyLogoUrl;
  // Resolved from the reveal response: the telecom company name (e.g. Asiacell)
  // and the human-readable category name (the product-definition name).
  String? _companyName;
  String? _categoryName;
  bool _revealing = false;
  bool _printing = false;
  String? _saleError; // last draw/sale failure — shown as a persistent in-sheet banner
  String? _printError; // last print failure — a persistent banner so it can't be missed

  @override
  void initState() {
    super.initState();
    // One idempotency key per sheet (per SKU selection), reused across Sell retries so a
    // lost-response retry returns the original sale instead of drawing a second card.
    _clientRef = 'draw-${widget.sku.sku}-${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _reveal() async {
    setState(() {
      _revealing = true;
      _saleError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final full = await ProductRepository(api).draw(sku: widget.sku.sku, governorate: widget.sku.governorate, clientRef: _clientRef);
      // A card has been drawn from the pool (atomically claimed + debited). Mark the sheet
      // consumed so the parent reloads pool counts on close.
      widget.onConsumed();
      if (mounted) {
        setState(() {
          _sent = full.product;
          _receiptNo = full.receiptNo;
          _operationId = full.operationId;
          _agentLogoUrl = full.agentLogoUrl;
          _companyLogoUrl = full.companyLogoUrl;
          _companyName = full.companyName;
          _categoryName = full.categoryName;
        });
        // Warm the logo cache now (off the print's critical path) so the eventual
        // print is instant and works even if the link drops by then.
        final t = full.product.productDefinition.template;
        if (t.showAgentLogo) loadReceiptLogo(full.agentLogoUrl);
        if (t.showCompanyLogo) loadReceiptLogo(full.companyLogoUrl);
      }
    } catch (e) {
      if (!mounted) return;
      // A 402 (no withdrawal limit) or 409 (pool empty) means NOTHING was sold — surface a
      // PERSISTENT banner (not a fleeting snackbar) with the friendly reason; the operator can
      // retry (same idempotency key, never a 2nd card) or back out. Do NOT close as consumed.
      setState(() => _saleError = friendlyError(e, context));
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  Future<void> _print() async {
    final revealed = _sent;
    if (revealed == null) return; // print is only reachable after reveal
    setState(() {
      _printing = true;
      _printError = null; // clear the last failure while a retry is in flight
    });
    try {
      final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
      final def = revealed.productDefinition;
      final t = def.template;
      // Rovo/BLD built-in printer prints via an ACTION_SEND intent (no ESC/POS). Print a TEXT
      // receipt: the text rides IN the intent (EXTRA_TEXT), so — unlike an image — it needs no
      // shared file for the separate print service (com.bld.settings.print) to read. (The image
      // path needs the PNG in shared storage; our app-private dir isn't readable by it, which
      // printed blank paper. TODO: re-enable image once written to a shared/public path.)
      if (ref.read(bluetoothServiceProvider.notifier).isRovo) {
        await RovoPrinter.printText(
          buildVoucherReceiptText(
            template: t,
            headerFallback: 'Inteshar Platform',
            shopName: auth?.entity.meta.name ?? 'Store',
            posLabel: 'Counter 1',
            operatorPhone: auth?.entity.users.firstOrNull?.phone ?? '',
            productName: def.name,
            price: Formatters.iqd(def.defaultPrice),
            serial: revealed.serialNumber,
            pin: revealed.pin,
            timestamp: DateTime.now(),
            companyName: _companyName,
            categoryName: _categoryName ?? def.name,
            expiry: revealed.expiryDate,
            receiptNo: _receiptNo,
          ),
        );
        await _confirmPrinted();
        if (mounted) widget.onPrinted();
        return;
      }
      // Fetch + decode the logos (best-effort; printing proceeds without them on failure).
      final agentLogo = t.showAgentLogo ? await loadReceiptLogo(_agentLogoUrl) : null;
      final companyLogo = t.showCompanyLogo ? await loadReceiptLogo(_companyLogoUrl) : null;
      final bytes = await buildVoucherReceipt(
        template: t,
        headerFallback: 'Inteshar Platform',
        shopName: auth?.entity.meta.name ?? 'Store',
        posLabel: 'Counter 1',
        operatorPhone: auth?.entity.users.firstOrNull?.phone ?? '',
        productName: def.name,
        price: Formatters.iqd(def.defaultPrice),
        serial: revealed.serialNumber,
        pin: revealed.pin,
        timestamp: DateTime.now(),
        agentLogo: agentLogo,
        companyLogo: companyLogo,
        companyName: _companyName,
        categoryName: _categoryName ?? def.name,
        expiry: revealed.expiryDate,
        receiptNo: _receiptNo,
      );
      // Enqueue on the serialized print queue: one ESC/POS write at a time (so
      // rapid/concurrent prints never interleave bytes) with retry on transient
      // printer failures.
      await ref.read(printQueueProvider).enqueue(bytes);
      await _confirmPrinted();
      if (mounted) widget.onPrinted();
    } catch (e) {
      // The code is already sold; a failed print must NOT be a fleeting snackbar the
      // operator can miss and then tap "Done" believing it printed. Keep the sheet open
      // and surface a PERSISTENT banner (mirrors the sale-error banner) with a Reprint.
      if (mounted) setState(() => _printError = friendlyError(e, context));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// A plain-text receipt for Copy/Share fallbacks (when no printer is connected
  /// or a print failed) — mirrors the reprint sheet's format.
  String _receiptText() {
    final p = _sent;
    if (p == null) return '';
    final def = p.productDefinition;
    return [
      _companyName ?? '',
      def.name,
      'SN: ${p.serialNumber}',
      'PIN: ${p.pin}',
      if (p.expiryDate != null && p.expiryDate!.isNotEmpty) 'EXP: ${p.expiryDate}',
      '#$_receiptNo',
    ].where((s) => s.isNotEmpty).join('\n');
  }

  /// B-054: confirm this sale's physical print outcome (best-effort — a failure
  /// leaves the op as "not printed", visible in the التقارير tab for a reprint).
  Future<void> _confirmPrinted() async {
    final id = _operationId;
    if (id == null || id.isEmpty) return;
    try {
      await ProductRepository(ref.read(apiClientProvider))
          .confirmPrint(id, printed: true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    // Pre-sale: a lean card (SKU + price + pool count) + the Sell button. The full
    // template-driven receipt only renders AFTER the draw, when we hold the real card.
    if (_sent == null) return _preRevealSheet(l, cs);

    final revealed = _sent != null; // always true past the guard above
    final p = _sent!;
    final def = p.productDefinition;
    final t = def.template;

    return PopScope(
      // After reveal the voucher is consumed and its PIN/QR are shown only once.
      // Block the back gesture / scrim tap so an accidental dismissal can't drop
      // the code before it's printed (Done/Print still pop explicitly). The
      // optimistic removal + whenComplete reload keep the counter correct even if
      // a drag-dismiss slips past this guard.
      canPop: !revealed,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              // Receipt preview tile — wrapped so a Rovo/intent print can snapshot it to a PNG.
              RepaintBoundary(
                key: _receiptKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(IntesharRadii.lg), boxShadow: IntesharShadows.elev2),
                    child: Column(
                      children: [
                        // Branding logos actually printed on the receipt, gated by the template
                        // toggles: the owning Main Agent's logo, then the SKU's company logo.
                        if (t.showAgentLogo && (_agentLogoUrl ?? '').trim().isNotEmpty) ...[
                          Image.network(_agentLogoUrl!, height: 44, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                          const SizedBox(height: 8),
                        ],
                        if (t.showCompanyLogo && (_companyLogoUrl ?? '').trim().isNotEmpty) ...[
                          Image.network(_companyLogoUrl!, height: 36, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                          const SizedBox(height: 8),
                        ],
                        IntesharStar(size: 36, color: cs.onSurface),
                        const SizedBox(height: 10),
                        Text(
                          t.headerText.trim().isNotEmpty ? t.headerText.trim().toUpperCase() : 'INTESHAR PLATFORM',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, color: cs.onSurface, letterSpacing: 2.2, fontWeight: FontWeight.w900),
                        ),
                        // Telecom company name (resolved on reveal) then the category
                        // name beneath it — each gated by its template flag.
                        if (t.showCompanyName && (_companyName ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _companyName!.trim().toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'CodecPro', fontSize: 15, color: cs.onSurface, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                          ),
                        ],
                        if (t.showCategoryName && (_categoryName ?? def.name).trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            (_categoryName ?? def.name).trim(),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'CodecPro', fontSize: 13, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ],
                        if (t.showProductName) ...[
                          const SizedBox(height: 16),
                          Text(
                            def.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'CodecPro', fontSize: 22, color: cs.onSurface, fontWeight: FontWeight.w900, letterSpacing: -0.4),
                          ),
                        ],
                        if (t.showPrice) ...[
                          const SizedBox(height: 4),
                          Text(
                            Formatters.iqd(def.defaultPrice),
                            style: IntesharType.mono(17, color: IntesharColors.saffronDeep, w: FontWeight.w800),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const _ReceiptDivider(),
                        const SizedBox(height: 14),
                        if (t.showSerial) ...[_ReceiptRow(label: l.posSerial, value: p.serialNumber, monoSize: 13), const SizedBox(height: 12)],
                        if (t.showPin) _ReceiptRow(label: l.posPin, value: revealed ? p.pin : '•••• •••• ••••', monoSize: 20, monoSpacing: 5),
                        if (t.qrEnabled) ...[
                          const SizedBox(height: 16),
                          if (revealed)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(IntesharRadii.sm)),
                              child: QrImageView(
                                data: t.qrPayload(pin: p.pin, serial: p.serialNumber),
                                version: QrVersions.auto,
                                size: 128,
                                backgroundColor: Colors.white,
                                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: IntesharColors.ink),
                                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: IntesharColors.ink),
                              ),
                            )
                          else
                            _LockedQr(label: l.posPinHidden),
                          if (revealed) ...[
                            const SizedBox(height: 8),
                            Text(
                              t.redeemInstructions.trim().isNotEmpty ? t.redeemInstructions.trim() : t.qrPayload(pin: p.pin, serial: p.serialNumber),
                              textAlign: TextAlign.center,
                              style: IntesharType.mono(12, color: cs.onSurface, w: FontWeight.w700),
                            ),
                          ],
                        ],
                        if (t.showExpiry && (p.expiryDate ?? '').isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _ReceiptRow(label: Localizations.localeOf(context).languageCode == 'ar' ? 'تاريخ الانتهاء' : 'Expiry', value: p.expiryDate!, monoSize: 13),
                        ],
                        if (revealed && _receiptNo > 0) ...[
                          const SizedBox(height: 12),
                          _ReceiptRow(label: Localizations.localeOf(context).languageCode == 'ar' ? 'رقم العملية' : 'Receipt #', value: '$_receiptNo', monoSize: 13),
                        ],
                        const SizedBox(height: 14),
                        const _ReceiptDivider(),
                        const SizedBox(height: 14),
                        Text(
                          t.footerText.trim().isNotEmpty ? t.footerText.trim() : l.posHomeScratchNote,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'CodecPro', fontSize: 11.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (!revealed) _buildRevealActions(l, cs) else _buildPrintActions(l, cs),
            ],
          ),
        ),
      ),
    );
  }

  // Pre-sale sheet: the store does not hold the card yet — show the SKU, price, and pool
  // availability, plus the Sell action that draws a card from the parent Main Agent's pool.
  Widget _preRevealSheet(AppLocalizations l, ColorScheme cs) {
    final s = widget.sku;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(IntesharRadii.lg), boxShadow: IntesharShadows.elev2),
                child: Column(
                  children: [
                    IntesharStar(size: 36, color: cs.onSurface),
                    const SizedBox(height: 12),
                    if ((s.companyName ?? '').trim().isNotEmpty) ...[
                      Text(
                        s.companyName!.trim().toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'CodecPro', fontSize: 14, color: cs.onSurface, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      s.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'CodecPro', fontSize: 22, color: cs.onSurface, fontWeight: FontWeight.w900, letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.price > 0 ? Formatters.iqd(s.price) : (Localizations.localeOf(context).languageCode == 'ar' ? 'السعر غير محدَّد' : 'Price not set'),
                      style: IntesharType.mono(17, color: IntesharColors.saffronDeep, w: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    _LockedQr(label: l.posPinHidden),
                    const SizedBox(height: 14),
                    Text(
                      Localizations.localeOf(context).languageCode == 'ar' ? 'المتوفر في مخزن الوكيل: ${s.available}' : 'In main-agent pool: ${s.available}',
                      style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildRevealActions(l, cs),
          ],
        ),
      ),
    );
  }

  // Pre-reveal: the PIN/QR are masked. The operator must explicitly tap Reveal,
  // which consumes the voucher (decrypt == used) — so we surface that warning.
  Widget _buildRevealActions(AppLocalizations l, ColorScheme cs) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        children: [
          // Selling burns the code the instant Reveal is tapped, so warn BEFORE that
          // moment if no printer is connected — the operator can still sell and then
          // Copy/Share the code, but they should know they'll have no receipt to print.
          Consumer(
            builder: (ctx, ref, _) {
              final connected =
                  ref.watch(bluetoothServiceProvider).status == PrinterStatus.connected;
              if (connected) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(IntesharRadii.md),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.print_disabled_outlined, size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ar
                              ? 'لا توجد طابعة متصلة — يمكنك البيع ثم نسخ أو مشاركة الرمز.'
                              : 'No printer connected — you can still sell, then copy or share the code.',
                          style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: Text(ar ? 'ربط' : 'Connect'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Persistent failure banner: the last sale attempt (402 no-limit / 409 pool-empty /
          // network) failed and nothing was sold — the operator can Retry (same idempotency
          // key) or Cancel. Stays until the next attempt succeeds.
          if (_saleError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(IntesharRadii.md),
                border: Border.all(color: cs.error.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: cs.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _saleError!,
                      style: TextStyle(fontFamily: 'CodecPro', fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w700, color: cs.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: IntesharColors.saffron.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(IntesharRadii.md),
              border: Border.all(color: IntesharColors.saffron.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: IntesharColors.saffronDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.posRevealWarning,
                    style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: BrandCTAButton(label: l.posHomeCancel, variant: BrandCTAVariant.outline, onPressed: _revealing ? null : () => Navigator.pop(context)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BrandCTAButton(
                  // The button that actually performs the irreversible draw+debit; its
                  // label names the consequence ("Sell & reveal") rather than reading like
                  // a harmless preview.
                  label: _revealing
                      ? l.posRevealing
                      : (_saleError != null
                          ? l.retryButton
                          : (ar ? 'بيع وإظهار' : 'Sell & reveal')),
                  leading: _revealing ? null : Icons.lock_open_outlined,
                  loading: _revealing,
                  onPressed: _revealing ? null : _reveal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Post-reveal: the code is shown and already consumed. Printing is optional;
  // Done just closes (the voucher has already dropped off the counter).
  Widget _buildPrintActions(AppLocalizations l, ColorScheme cs) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Consumer(
        builder: (ctx, ref, _) {
          final ps = ref.watch(bluetoothServiceProvider);
          final isConnected = ps.status == PrinterStatus.connected;
          return Column(
            children: [
              // Persistent print-failure banner — the code is already sold, so a missed
              // failure could leave the customer with nothing. Stays until a retry succeeds.
              if (_printError != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(IntesharRadii.md),
                    border: Border.all(color: cs.error.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.print_disabled_outlined, size: 18, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ar
                              ? 'فشلت الطباعة — الرمز مُباع. أعد الطباعة أو انسخ/شارك الرمز أدناه.'
                              : 'Print failed — the code is sold. Reprint, or copy/share the code below.',
                          style: TextStyle(fontFamily: 'CodecPro', fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w700, color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isConnected ? IntesharColors.sage.withValues(alpha: 0.10) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: isConnected ? IntesharColors.sage.withValues(alpha: 0.4) : cs.outline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isConnected ? Icons.print_outlined : Icons.print_disabled_outlined, size: 14, color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      isConnected ? (ps.deviceName ?? l.posPrinterConnected) : l.posHomePrinterNotConnected,
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!isConnected)
                BrandCTAButton(
                  label: l.posConnectPrinter,
                  leading: Icons.bluetooth,
                  variant: BrandCTAVariant.outline,
                  onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BrandCTAButton(label: l.posDone, variant: BrandCTAVariant.outline, onPressed: _printing ? null : () => widget.onPrinted()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BrandCTAButton(
                      label: _printing
                          ? l.posHomePrinting
                          : (_printError != null ? (ar ? 'إعادة الطباعة' : 'Reprint') : l.posPrintVoucher),
                      leading: _printing ? null : Icons.print_outlined,
                      loading: _printing,
                      onPressed: (_printing || !isConnected) ? null : _print,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Always-available fallback so a code is never trapped behind a missing or
              // failing printer: copy the PIN, or share the whole receipt to any app.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final pin = _sent?.pin ?? '';
                        await Clipboard.setData(ClipboardData(text: pin));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(ar ? 'تم النسخ' : 'Copied')));
                        }
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(ar ? 'نسخ الرمز' : 'Copy PIN'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await SharePlus.instance.share(ShareParams(text: _receiptText()));
                        } catch (_) {
                          await Clipboard.setData(ClipboardData(text: _receiptText()));
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text(ar
                                    ? 'نُسخ الإيصال — ألصقه في أي تطبيق للمشاركة'
                                    : 'Receipt copied — paste it anywhere to share')));
                          }
                        }
                      },
                      icon: const Icon(Icons.share_outlined, size: 16),
                      label: Text(ar ? 'مشاركة' : 'Share'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// Placeholder shown in place of the QR before the code is revealed.
class _LockedQr extends StatelessWidget {
  final String label;
  const _LockedQr({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 128,
      height: 128,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 30, color: cs.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontFamily: 'CodecPro', fontSize: 10.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final double monoSize;
  final double monoSpacing;
  const _ReceiptRow({required this.label, required this.value, this.monoSize = 13, this.monoSpacing = 0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
        SelectableText(
          value,
          style: IntesharType.mono(monoSize, color: cs.onSurface, w: FontWeight.w800, letterSpacing: monoSpacing),
        ),
      ],
    );
  }
}

class _ReceiptDivider extends StatelessWidget {
  const _ReceiptDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedLinePainter(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 3.0;
    const gap = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

/// سستم A92: a full-panel, one-time mandatory location confirmation. The shop
/// picks its spot on the map; selling stays blocked until it is confirmed.
class _LocationGate extends ConsumerStatefulWidget {
  const _LocationGate({required this.onConfirmed});
  final Future<void> Function() onConfirmed;

  @override
  ConsumerState<_LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends ConsumerState<_LocationGate> {
  bool _busy = false;

  Future<void> _confirm() async {
    final picked = await pickLocationOnMap(context);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PosSelfRepository(ref.read(apiClientProvider))
          .confirmLocation(latitude: picked.latitude, longitude: picked.longitude);
      await widget.onConfirmed();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_on_outlined, size: 56, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              ar ? 'ثبّت موقع نقطة البيع' : 'Confirm your shop location',
              textAlign: TextAlign.center,
              style: IntesharType.display(20, color: cs.onSurface, w: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              ar
                  ? 'مطلوب مرة واحدة عند الوصول إلى مكان عملك، ولا يمكن بيع أي بطاقة قبل التثبيت.'
                  : 'Required once, at your workplace. You cannot sell any card until this is confirmed.',
              textAlign: TextAlign.center,
              style: IntesharType.sans(13.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            BrandCTAButton(
              label: ar ? 'تحديد الموقع على الخريطة' : 'Pick location on map',
              leading: Icons.map_outlined,
              loading: _busy,
              onPressed: _busy ? null : _confirm,
            ),
          ]),
        ),
      ),
    );
  }
}

/// التواصل POS tab (B-057): a shop has exactly one conversation — with its
/// parent agent — so it opens that thread directly (no list step), embedded so it
/// doesn't stack a second app bar under the POS one. The partner's real name is
/// resolved from the parent entity (falling back to a generic label while loading).
class _PosChatTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PosChatTab> createState() => _PosChatTabState();
}

class _PosChatTabState extends ConsumerState<_PosChatTab> {
  String? _agentName;

  @override
  void initState() {
    super.initState();
    _resolveName();
  }

  Future<void> _resolveName() async {
    final auth = ref.read(authStateProvider).valueOrNull;
    final parentId = auth is AuthAuthenticated ? auth.entity.parent : '';
    if (parentId.isEmpty) return;
    try {
      final parent = await EntityRepository(ref.read(apiClientProvider)).read(parentId);
      if (mounted) setState(() => _agentName = parent.meta.name);
    } catch (_) {
      // Keep the generic label on failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final auth = ref.watch(authStateProvider).valueOrNull;
    final parentId = auth is AuthAuthenticated ? auth.entity.parent : '';
    if (parentId.isEmpty) {
      return Center(
        child: Text(ar ? 'لا يوجد وكيل للتواصل معه.' : 'No agent to message.',
            style: IntesharType.sans(14, color: cs.onSurfaceVariant)),
      );
    }
    return ChatThreadScreen(
      withId: parentId,
      withName: (_agentName != null && _agentName!.isNotEmpty)
          ? _agentName!
          : (ar ? 'الوكيل' : 'Agent'),
      embedded: true,
    );
  }
}
