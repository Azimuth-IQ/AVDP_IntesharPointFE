import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/logo_loader.dart';
import 'package:inteshar/core/printing/print_queue.dart';
import 'package:inteshar/core/printing/printer_errors.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/chat/application/chat_provider.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
import 'package:inteshar/features/pos/domain/pin_verify_result.dart';
import 'package:inteshar/features/pos/domain/sale_error.dart';
import 'package:inteshar/core/api/error_mapper.dart' show friendlyError;
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos/data/pos_self_repository.dart';
import 'package:inteshar/features/chat/presentation/chat_thread_screen.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/notifications/presentation/alert_banner.dart';
import 'package:inteshar/features/pos/presentation/pos_account_panel.dart';
import 'package:inteshar/features/pos/presentation/pos_brand.dart';
import 'package:inteshar/features/pos/presentation/pos_sales_panel.dart';
import 'package:inteshar/features/pos/presentation/pos_statement_panel.dart';
import 'package:inteshar/features/pos/presentation/print_queue_indicator.dart';
import 'package:inteshar/features/pos/presentation/printer_picker_page.dart';
import 'package:inteshar/features/pos/presentation/printer_status_chip.dart';
import 'package:inteshar/shared/widgets/map_location_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_backdrop.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
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
  Object? _error;
  bool _loading = true;
  // UX-48: a refresh that has a grid to keep on screen must not blank it. The
  // very first load (nothing to show yet) still gets the full-screen spinner;
  // every later load — and every sale ends with one — runs "in place": the last
  // grid stays rendered under a thin progress line.
  bool _refreshing = false;
  /// An in-place refresh that failed. The grid stays (with the previous counts),
  /// so the operator has to be told those counts may now be stale.
  String? _refreshError;

  /// UX-89: when the counts on screen were last actually fetched. Stamped in the
  /// app bar, because "العداد المباشر" (live counter) is a promise about
  /// freshness and the operator has no other way to judge it.
  DateTime? _updatedAt;

  /// UX-89: what makes the counter live.
  ///
  /// The pool belongs to the PARENT agent, so it moves without this device
  /// doing anything — the agent withdraws stock, a second POS on the same shop
  /// sells. Until now the counts only changed on open, on pull-to-refresh and
  /// after this operator's own sale, so a cashier could promise a card the pool
  /// no longer held and meet the 409 at reveal, after the customer had been told
  /// yes.
  ///
  /// This is a READ (`/product/sellable` + balance). It never touches the draw
  /// path, and it is suppressed while a sheet or dialog is open so it can never
  /// rebuild the screen under a sale in progress.
  Timer? _poll;
  static const _pollEvery = Duration(seconds: 60);
  final TextEditingController _searchCtrl = TextEditingController();
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
    _poll?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      // UX-55: a shift break is exactly when the printer gets switched off,
      // unplugged or carried away, and the chip would otherwise still be green
      // on the first sale back. Fire-and-forget: it writes no bytes, it cannot
      // fail loudly, and nothing on screen waits for it.
      unawaited(ref.read(printerServiceProvider.notifier).verifyConnection());
      if (since != null && DateTime.now().difference(since) >= _relockAfter) {
        // Left unattended — drop the unlock flag and send the operator back to the PIN.
        ref.read(posUnlockedProvider.notifier).state = false;
        if (mounted) context.go('/pos/pin-lock');
        return;
      }
      // UX-89: the pool almost certainly moved while the app was away — a break
      // is exactly when the agent rebalances stock. Coming back to the counts
      // from before, under a label that says "live", is how a cashier promises a
      // card that is gone. A read (`/product/sellable`), never the draw path.
      //
      // Skipped when the counts are seconds old: a Share sheet and a vendor
      // print intent each background and restore the app, so a bulk print would
      // otherwise fire one fetch per card.
      final fresh = _updatedAt != null &&
          DateTime.now().difference(_updatedAt!) < const Duration(seconds: 15);
      if (!fresh && ref.read(posUnlockedProvider) && _sellable != null) {
        unawaited(_load());
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
    _startPolling();
  }

  /// UX-89: keep the counter honest between manual refreshes. Cheap guards, all
  /// of them about not surprising the operator:
  /// * only the Store tab — the other tabs don't show pool counts;
  /// * only when this route is on top, so a poll can never rebuild the screen
  ///   beneath an open voucher sheet or confirm dialog;
  /// * never on top of a load already in flight.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) {
      if (!mounted || _tab != 0 || _loading || _refreshing) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (!ref.read(posUnlockedProvider)) return;
      unawaited(_load());
    });
  }

  /// Fetch the sellable pool + balance.
  ///
  /// UX-48: this is called after EVERY sale, hundreds of times a shift, with the
  /// next customer already at the counter. Only the first load (when there is no
  /// grid yet) may take the screen; once cards are on screen a reload keeps them
  /// and shows a thin inline progress line instead. `/product/sellable` walks
  /// every definition server-side, so this is not a quick blink.
  Future<void> _load() async {
    final inPlace = _sellable != null;
    setState(() {
      if (inPlace) {
        _refreshing = true;
      } else {
        _loading = true;
        _error = null;
      }
      _refreshError = null;
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
      if (mounted) {
        setState(() {
          _sellable = sellable;
          _balance = balance;
          _sliderUrls = slider;
          // Only a SUCCESSFUL fetch moves the stamp — a failed refresh leaves it
          // reading when the numbers on screen were last known to be true.
          _updatedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // With a grid already on screen, a failed refresh must not throw the
        // operator onto a full-screen error page — the previously loaded cards
        // are still sellable. Flag the staleness instead.
        if (inPlace) {
          _refreshError = friendlyError(e, context);
        } else {
          _error = e;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final auth = ref.watch(authStateProvider).valueOrNull;
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
              // White-label: the owning agent's logo (falls back to the shop's
              // initial), never the Inteshar star (B-083).
              const PosBrandMark(size: 26),
              const SizedBox(width: 12),
              // Expanded so both lines actually ellipsise: a Row lays non-flex
              // children out unbounded, which is where a long shop name gets to
              // overflow instead of truncating.
              Expanded(
                child: Column(
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
                    // UX-89: "العداد المباشر" is a claim about freshness, so it
                    // now carries the evidence — when these counts were last
                    // fetched. The counter is genuinely live (resume + poll, see
                    // _startPolling); the stamp is how the operator can tell,
                    // and it stops moving the moment a refresh starts failing.
                    Text(
                      _counterSubtitle(l),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'CodecPro', fontSize: 11, color: cs.onSurfaceVariant, letterSpacing: 0.2, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // UX-55/UX-63: one chip, one vocabulary (see printer_status_chip.dart).
          // "Connected" is now a probed fact rather than a claim, "a decision is
          // waiting for you" is no longer printed as "nothing found", and the
          // label is width-clamped so a MAC-named printer cannot crowd out the
          // shop name beside it.
          Consumer(
            builder: (ctx, ref, _) => Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: PrinterStatusChip(
                state: ref.watch(printerServiceProvider),
                ar: _ar,
                onTap: () => Navigator.push<void>(
                    ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
              ),
            ),
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
      //
      // POS lives OUTSIDE AppShell, so the app-wide AlertBanner never reaches it —
      // mount one here so an ALERT addressed to POS operators is actually seen (B-071).
      body: Column(
        children: [
          const AlertBanner(),
          Expanded(child: BrandBackdrop(child: _tabBody(l))),
        ],
      ),
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
          // B-133: the shop had no way to learn a reply had arrived short of
          // opening the tab. The count comes from the per-thread `unread` the
          // backend already returned and nothing consumed.
          NavigationDestination(
            icon: _chatBadge(const Icon(Icons.forum_outlined)),
            selectedIcon: _chatBadge(const Icon(Icons.forum)),
            label: _ar ? 'التواصل' : 'Chat',
          ),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: _ar ? 'الحساب' : 'Profile'),
        ],
      ),
    );
  }

  /// UX-89: the live-counter label plus when it was last true.
  ///
  /// "Just now" for the first minute (the poll interval — anything finer would
  /// be a ticking number nobody reads), then the clock time it was fetched, so a
  /// stale screen is obvious at a glance rather than implied.
  String _counterSubtitle(AppLocalizations l) {
    final at = _updatedAt;
    if (at == null) return l.posHomeLiveCounter;
    final age = DateTime.now().difference(at);
    final ar = _ar;
    final stamp = age < const Duration(minutes: 1)
        ? (ar ? 'الآن' : 'just now')
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return '${l.posHomeLiveCounter} · ${ar ? 'حُدّث' : 'updated'} $stamp';
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
        // Full-screen states only while there is genuinely nothing to show.
        if (_sellable == null) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_error != null) return ErrorState(error: _error!, onRetry: _load);
        }
        return Column(
          children: [
            // UX-48: the in-place refresh hint. 2px, no layout jump when idle.
            SizedBox(
              height: 2,
              child: _refreshing ? const LinearProgressIndicator(minHeight: 2) : null,
            ),
            if (_refreshError != null) _staleBanner(),
            Expanded(child: _buildBody(l)),
          ],
        );
    }
  }

  /// Shown when an in-place refresh failed: the cards below are the previous
  /// load's, so their counts may no longer match the pool.
  Widget _staleBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: context.status.warn.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.sync_problem_outlined, size: 16, color: context.status.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _ar
                  ? 'تعذّر التحديث — الأعداد المعروضة قد تكون قديمة.'
                  : "Couldn't refresh — the counts shown may be out of date.",
              style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
          ),
          TextButton(
            onPressed: _refreshing ? null : _load,
            // UX-119: `VisualDensity.compact` does not just tighten the padding
            // — it shrinks the PADDED tap target from 48dp to 40dp. This is the
            // way out of a stale-counts screen; it keeps the full target and
            // pays for it with horizontal padding instead.
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: Text(_ar ? 'إعادة المحاولة' : 'Retry'),
          ),
        ],
      ),
    );
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

  /// UX-60: the query and the box that shows it are one thing — resetting one
  /// without the other left the screen contradicting itself (results cleared,
  /// the typed text still sitting in the field).
  void _clearSearchField() {
    _searchCtrl.clear();
    _search = '';
  }

  void _openCompany(String companyKey, List<SellableSku> rows) {
    final buckets = _buckets(rows);
    setState(() {
      _company = companyKey;
      _clearSearchField();
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
        _clearSearchField();
      });

  void _back() {
    final rows = _companyGroups()[_company] ?? const <SellableSku>[];
    final multiBucket = _buckets(rows).length > 1;
    setState(() {
      _clearSearchField();
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

  double _skuTileExtent() => switch (context.screenSize) {
        ScreenSize.desktop => 240.0,
        ScreenSize.tablet => 210.0,
        ScreenSize.mobile => 172.0,
      };

  /// UX-52/UX-110: the tile now has to fit a two-line SKU name (so an Arabic name
  /// never ellipsises away its denomination), a large price, the sellable count
  /// and a 48dp Sell button. Both SKU grids (global search + cards step) share
  /// this so they can't drift apart.
  double _skuRowHeight() => context.screenSize == ScreenSize.mobile ? 250.0 : 264.0;

  // Home: HQ slider + a grid of telecom companies (printing companies).
  /// Unread-chat badge for the التواصل tab. Silent on error (the provider yields
  /// 0), because a failed count must never break the navigation it decorates.
  Widget _chatBadge(Widget icon) {
    final n = ref.watch(chatUnreadCountProvider).valueOrNull ?? 0;
    if (n == 0) return icon;
    return Badge(label: Text('$n'), isLabelVisible: true, child: icon);
  }

  Widget _homeStep(AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    final groups = _companyGroups();
    final keys = groups.keys.toList()
      ..sort((a, b) => _companyLabel(a).toLowerCase().compareTo(_companyLabel(b).toLowerCase()));

    final searching = _search.trim().isNotEmpty;
    final matches = searching ? _globalMatches(_search) : const <SellableSku>[];

    // SKU-card grid geometry for the global search results.
    final skuExtent = _skuTileExtent();
    final skuRowHeight = _skuRowHeight();

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
                  // UX-60: controller-backed, so clearing the query clears the box.
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: l.posHomeSearchHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: _ar ? 'مسح البحث' : 'Clear search',
                            onPressed: () => setState(_clearSearchField),
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
                return _GovCard(
                  label: b == _kRegionFree ? (_ar ? 'بدون تخصيص' : 'Region-free') : b,
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
    final tileExtent = _skuTileExtent();
    final rowHeight = _skuRowHeight();

    return MaxWidthBox(
      child: Column(
        children: [
          _header(l, title: _companyLabel(_company!), subtitle: subtitle, onBack: _back),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              // UX-60: same controller as the home step, and a clear button this
              // field never had.
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l.posHomeSearchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: _ar ? 'مسح البحث' : 'Clear search',
                        onPressed: () => setState(_clearSearchField),
                      )
                    : null,
              ),
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
  Widget _header(AppLocalizations l, {required String title, String? subtitle, VoidCallback? onBack}) => PosStepHeader(
        title: title,
        subtitle: subtitle,
        onBack: onBack,
        backTooltip: l.posHomeCancel,
        balance: _balance,
      );

  void _showVoucher(SellableSku sku) {
    // A successful draw consumes one card from the parent pool. We can't optimistically
    // patch the in-memory count (the backend picks the card), so just reload the sellable
    // counts from the server once the sheet closes after a sale.
    var consumed = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // UX-64: BEFORE the draw nothing has happened yet — a mis-tapped card must
      // be undoable with the gesture the operator already reached for, not by
      // hunting for Cancel. The sheet's own PopScope(canPop: !_sold && !_revealing)
      // is what locks it, at the exact moment the sale becomes irreversible, and a
      // scrim tap routes through Navigator.maybePop, which that PopScope vetoes.
      //
      // enableDrag stays FALSE on purpose: Flutter's drag-to-close calls
      // Navigator.pop() DIRECTLY from BottomSheet.onClosing (material/bottom_sheet.dart)
      // and never consults PopScope — enabling it would let a swipe discard a
      // sold, un-printed code.
      isDismissible: true,
      enableDrag: false,
      builder: (ctx) => _VoucherSheet(
        sku: sku,
        onConsumed: () => consumed = true,
        onPrinted: () => Navigator.pop(ctx),
      ),
    ).whenComplete(() {
      // After a sale, re-fetch so the pool counts match the source of truth.
      if (consumed) _load();
    });
  }
}

// ── Printer tab ───────────────────────────────────────────────────────────────

/// The POS step header — title/subtitle on one side, the live balance on the other.
///
/// B-095: those two compete for a single row, and on a 360dp counter (a Sunmi V2)
/// a real balance wins hard — `25,876,000 IQD` measures 170px of a 320px budget,
/// which left the title 90px on the back-arrow steps and clipped `تأكيد البيع`
/// to `تأكيد ال…` on the CONFIRM screen, the one place the operator most needs to
/// read what they're about to sell. The contract now: the tally is `Flexible` so
/// it yields, its numerals scale down rather than ellipsise, and the title steps
/// down a size on narrow screens. Public so that contract is directly testable.
///
/// The tally is bounded by a *ceiling* (half the row) rather than given a flex
/// share: a `Flexible` tally next to an `Expanded` title splits the row 50/50
/// even when the balance is `—` and needs 100px, needlessly starving the title.
/// A `ConstrainedBox` sizes to content, so the title keeps every pixel the
/// balance doesn't actually need.
class PosStepHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final String? backTooltip;
  final AgentBalance? balance;

  const PosStepHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.backTooltip,
    this.balance,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final narrow = MediaQuery.sizeOf(context).width < 420;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack != null ? 8 : 20, 20, 20, 6),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            if (onBack != null)
              IconButton(
                icon: Icon(ar ? Icons.arrow_forward : Icons.arrow_back, color: cs.onSurface),
                tooltip: backTooltip,
                onPressed: onBack,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: IntesharType.display(narrow ? 19 : 24, color: cs.onSurface, w: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 0.45 is measured, not taste: the longest shipped title with a back
            // arrow ("Confirm sale", ~112px at 19px) needs the remainder on a
            // 360dp counter. Widen this and English clips again.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
              child: _BalanceTally(balance: balance),
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceTally extends StatelessWidget {
  final AgentBalance? balance;
  const _BalanceTally({required this.balance});

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final tones = context.tones;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      // B-094: white tally with a brand accent rule — the counter's balance is a
      // NUMBER, so ink numerals on paper read it fastest. Was a solid gold slab.
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: IntesharShadows.elev1,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(color: tones.brand, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        // Flexible so the tally yields width to the title instead of pinning its
        // intrinsic size; that in turn bounds the FittedBox below so it can scale.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                ar ? 'الرصيد' : 'BALANCE',
                style: TextStyle(fontFamily: 'CodecPro', fontSize: 10, color: cs.onSurfaceVariant, letterSpacing: 1.4, fontWeight: FontWeight.w800),
                maxLines: 1,
              ),
              const SizedBox(height: 3),
              // B-095: money SHRINKS, it never ellipsises — "25,876,0…" would be a
              // worse lie than smaller numerals, and a counter operator reads this
              // to decide whether they can sell.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  // iqdOf, not iqd: the unit follows THIS widget's locale rather than the
                  // app-wide default, so the counter reads د.ع on an Arabic till and
                  // a test that pumps a locale gets that locale's unit.
                  balance == null ? '—' : Formatters.iqdOf(context, balance!.available),
                  maxLines: 1,
                  style: TextStyle(fontFamily: 'CodecPro', fontSize: 19, color: cs.onSurface, fontWeight: FontWeight.w900, letterSpacing: -0.4, height: 1),
                ),
              ),
            ],
          ),
        ),
      ]),
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

  /// UX-151: set the moment the operator touches the carousel. Auto-advance is a
  /// WCAG 2.2.2 moving-content hazard on a counter device — it used to yank the
  /// page out from under a finger 5s after a deliberate swipe, because the timer
  /// was only ever cancelled in dispose(). User intent wins permanently.
  bool _userTookOver = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  /// Runs the 5s timer only while it is both wanted and allowed.
  void _syncTimer() {
    final media = MediaQuery.maybeOf(context);
    // Respect the platform's reduce-motion / screen-reader settings — nothing in
    // this app was reading them.
    final motionAllowed =
        !(media?.disableAnimations ?? false) && !(media?.accessibleNavigation ?? false);
    final wanted = widget.urls.length > 1 && !_userTookOver && motionAllowed;
    if (!wanted) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.urls.length;
      _controller.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  /// The operator drove the carousel (swipe or dot) — stop advancing it for good.
  void _stopAuto() {
    if (_userTookOver) return;
    _userTookOver = true;
    _timer?.cancel();
    _timer = null;
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
        // nothing gets re-cropped.
        //
        // UX-122: the cap used to be a flat 280dp of HEIGHT, which on a wide
        // screen pinned the hero at 497×280 while the page around it kept
        // growing — a 1920px asset displayed at 497 logical px, shrinking
        // relative to everything else. That was a clamp, not a decision.
        //
        // The decision: the slide runs the full content width, up to a slide
        // width that still reads as a banner rather than a billboard, and never
        // takes more than ~40% of the viewport height (it sits above the company
        // grid, which must not be pushed off the first screen).
        const maxSlideWidth = 720.0;
        final heightBudget = MediaQuery.sizeOf(context).height * 0.4;
        final width = constraints.maxWidth
            .clamp(0.0, maxSlideWidth)
            .clamp(0.0, heightBudget * 16 / 9);
        return Center(
          child: SizedBox(
            width: width,
            height: width * 9 / 16,
            child: _frame(cs),
          ),
        );
      }),
    );
  }

  Widget _frame(ColorScheme cs) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return ClipRRect(
      borderRadius: BorderRadius.circular(IntesharRadii.lg),
      child: Stack(
        children: [
              // A drag start is the operator taking over; a programmatic
              // animateToPage carries no drag details, so the timer's own moves
              // never mistake themselves for a swipe.
              NotificationListener<ScrollStartNotification>(
                onNotification: (n) {
                  if (n.dragDetails != null) _stopAuto();
                  return false;
                },
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.urls.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => Image.network(
                    widget.urls[i],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    // UX-150: no POS image carried a description. The slide
                    // itself is promotional and its content is unknown to us,
                    // so it announces its position rather than pretending to
                    // describe the artwork.
                    semanticLabel: ar
                        ? 'صورة ${i + 1} من ${widget.urls.length}'
                        : 'Slide ${i + 1} of ${widget.urls.length}',
                    errorBuilder: (_, _, _) => Container(
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant, size: 32),
                    ),
                    loadingBuilder: (ctx, child, progress) =>
                        progress == null ? child : Container(color: cs.surfaceContainerHighest),
                  ),
                ),
              ),
              if (widget.urls.length > 1)
                Positioned(
                  bottom: 6,
                  left: 0,
                  right: 0,
                  // UX-151: the dots were 6px, non-interactive, and white@70% over
                  // an arbitrary photo. They are now real controls with a 28dp hit
                  // box, on their own scrim so they read on any image.
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(widget.urls.length, (i) {
                          final active = i == _page;
                          return Semantics(
                            button: true,
                            selected: active,
                            label: ar ? 'صورة ${i + 1} من ${widget.urls.length}' : 'Slide ${i + 1} of ${widget.urls.length}',
                            child: InkResponse(
                              onTap: () {
                                _stopAuto();
                                _controller.animateToPage(i,
                                    duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                              },
                              radius: 16,
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: Center(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    width: active ? 20 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
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
  final VoidCallback onTap;
  const _CompanyCard({required this.name, required this.logoUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                        // UX-150: the logo IS the company name for a screen
                        // reader — the text below it is the only other clue.
                        semanticLabel: name,
                        errorBuilder: (_, _, _) => _logoFallback(context, cs, name),
                      )
                    : _logoFallback(context, cs, name),
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
          ],
        ),
      ),
    );
  }

  Widget _logoFallback(BuildContext context, ColorScheme cs, String name) => Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(26)),
        child: Text(
          name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase(),
          style: IntesharType.display(22, color: context.tones.onBrand, w: FontWeight.w900),
        ),
      );
}

// ── Governorate card ──────────────────────────────────────────────────────────

class _GovCard extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GovCard({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            Icon(Icons.location_on_outlined, color: context.tones.brandInk, size: 26),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.1),
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
    // UX-53: the server only returns a row when the pool HAS stock (`avail > 0`),
    // so `affordable == 0` can only mean one thing — the shop's withdrawal limit
    // no longer covers a single card. Selling it would fail 402 three taps later,
    // after the customer has been promised a card, so the tile has to say so up
    // front and refuse the tap.
    final unaffordable = s.affordable <= 0;
    final artHeight = context.screenSize == ScreenSize.mobile ? 88.0 : 96.0;

    return PressableScale(
      onTap: unaffordable ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          // Washed-out surface rather than a blanket Opacity: the operator must
          // still be able to READ which card they can't sell, and the reason
          // line has to keep its contrast.
          color: unaffordable ? cs.surfaceContainerHighest : cs.surfaceContainer,
          borderRadius: BorderRadius.circular(IntesharRadii.lg),
          boxShadow: unaffordable ? const [] : IntesharShadows.elev1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card-type artwork (fixed height so the tile can never overflow); a
            // gradient + SKU chip stands in when no image is configured.
            SizedBox(
              height: artHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImg)
                    Image.network(
                      s.imageUrl!,
                      fit: BoxFit.cover,
                      // UX-150: the card artwork is how an operator recognises
                      // the denomination at a glance; name it.
                      semanticLabel: s.name,
                      errorBuilder: (_, _, _) => _artFallback(context, cs, s.sku),
                      loadingBuilder: (ctx, child, progress) =>
                          progress == null ? child : Container(color: cs.surfaceContainerHighest),
                    )
                  else
                    _artFallback(context, cs, s.sku),
                  if (unaffordable)
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0x59FFFFFF)),
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
                    // UX-52: TWO lines. At one line a 153px tile ellipsised
                    // "أسياسيل بطاقة شحن ٥٠٠٠ دينار" after its first two words —
                    // cutting the denomination, the only thing the customer
                    // actually asked for, on an irreversible money action.
                    Text(
                      s.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        color: cs.onSurface,
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // …and the price is now the loudest thing on the tile:
                    // it is the number the operator matches against what the
                    // customer said, and it shrinks rather than truncating.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        s.price > 0 ? Formatters.iqd(s.price) : (ar ? 'السعر غير محدَّد' : 'Price not set'),
                        maxLines: 1,
                        style: IntesharType.mono(20, color: context.tones.brandInk, w: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 3),
                    // UX-52: the old bare "× 12" pill floated over arbitrary
                    // artwork at 11px with a 14%-alpha fill — an unlabelled
                    // number nobody could read or interpret. It is now a
                    // labelled line on the tile's own surface.
                    _availabilityLine(context, ar: ar, unaffordable: unaffordable),
                    const Spacer(),
                    BrandCTAButton(
                      label: unaffordable ? (ar ? 'غير متاح' : 'Unavailable') : l.posHomeSell,
                      leading: unaffordable ? null : Icons.sell_outlined,
                      // UX-110: 36dp was the literal hit box of the most-tapped
                      // control on the handheld, all shift, one-handed.
                      onPressed: unaffordable ? null : onTap,
                      height: 48,
                      fontSize: 13,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How many of this card can actually be sold right now — or why none can.
  Widget _availabilityLine(BuildContext context, {required bool ar, required bool unaffordable}) {
    final cs = Theme.of(context).colorScheme;
    final color = unaffordable ? context.status.warn : context.status.success;
    return Row(
      children: [
        Icon(unaffordable ? Icons.block : Icons.inventory_2_outlined, size: 12, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            unaffordable
                ? (ar ? 'الرصيد لا يكفي' : 'Balance too low')
                : (ar ? 'يمكن بيع ${sellable.affordable}' : 'Can sell ${sellable.affordable}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: unaffordable ? color : cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _artFallback(BuildContext context, ColorScheme cs, String sku) {
    // UX-148: the SKU is the only thing identifying a card that has no artwork,
    // and it sits at the CENTRE of the gradient — but its ink was `tones.onBrand`,
    // which is measured against `cs.primary`, the top-left stop alone. The other
    // stop is `brandInk`, a deliberately darkened brand tone, so on a white-label
    // brand where the two stops straddle the light/dark threshold the winner at
    // the corner is the loser in the middle. Measure where the text actually is.
    final mid = Color.lerp(cs.primary, cs.onPrimaryContainer, 0.5)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.onPrimaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        sku,
        style: IntesharType.mono(20, color: legibleOn(mid), w: FontWeight.w900, letterSpacing: 1),
      ),
    );
  }
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
  /// Last draw/sale failure — shown as a persistent in-sheet banner. Classified
  /// (UX-62) so "the server refused" and "we never heard back" don't read the
  /// same: only the second one may have consumed a card.
  PosSaleFailure? _saleError;
  String? _printError; // last print failure — a persistent banner so it can't be missed

  // ── B-086 bulk sale ─────────────────────────────────────────────────────────
  /// How many cards to sell. 1 is the ordinary fast path — byte-for-byte the old flow.
  int _qty = 1;
  /// Server pre-flight: the ceiling, what bound it, and the unit price. No money moves.
  BulkQuote? _quote;
  /// Result of a committed bulk sale (null until then).
  BulkDrawResult? _bulk;

  /// Above this many cards the operator must re-enter the POS PIN (anti-theft on the
  /// highest-value action — user-approved 2026-07-26).
  static const int _pinRequiredFrom = 5;

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  /// True once this sheet holds a SOLD, irreversible code (single or bulk).
  /// Nothing may dismiss the sheet from here except an explicit Done/Print.
  bool get _sold => _sent != null || _bulk != null;

  @override
  void initState() {
    super.initState();
    // One idempotency key per sheet (per SKU selection), reused across Sell retries so a
    // lost-response retry returns the original sale instead of drawing a second card.
    _clientRef = 'draw-${widget.sku.sku}-${DateTime.now().microsecondsSinceEpoch}';
    _loadQuote();
    // UX-55: re-probe the printer NOW, while the operator is still reading the
    // price — this is the last moment before an irreversible tap, and until now
    // the pre-sale "no printer connected" warning could not fire for a printer
    // that was switched off, because the app still believed it was connected.
    //
    // Deliberately in initState (once per sheet, never from a rebuild), never
    // awaited, and it writes NOTHING to any print head. It cannot delay or block
    // the Sell button; the worst it does is turn the chip amber.
    unawaited(ref.read(printerServiceProvider.notifier).verifyConnection());
  }

  /// Ask the server how many cards may be sold right now. Read-only — it claims no cards
  /// and moves no money, so it is safe to call before the operator commits to anything.
  Future<void> _loadQuote() async {
    try {
      final q = await ProductRepository(ref.read(apiClientProvider))
          .bulkQuote(sku: widget.sku.sku, governorate: widget.sku.governorate);
      if (mounted) setState(() => _quote = q);
    } catch (_) {
      // Non-fatal: without a quote the sheet simply stays on the single-card path.
    }
  }

  /// The most cards this sale may include (server-authoritative; the server clamps again).
  int get _maxQty {
    final q = _quote;
    if (q == null) return 1;
    return q.maxAllowed < 1 ? 1 : q.maxAllowed;
  }

  bool get _bulkAvailable => (_quote?.bulkEnabled ?? false) && _maxQty > 1;

  /// Re-verify the POS PIN against the SERVER before a large bulk sale. Comparing locally
  /// would be theatre — this makes the operator actually know the PIN, which is the real
  /// control when a counter device is left unlocked. Returns false if cancelled/wrong.
  Future<bool> _confirmPin(bool ar) async {
    final ctrl = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> submit() async {
          final pin = ctrl.text.trim();
          if (pin.isEmpty) {
            setD(() => error = ar ? 'أدخل الرمز' : 'Enter your PIN');
            return;
          }
          try {
            final r = await ref.read(posPinRepositoryProvider).verifyPin(pin);
            if (!ctx.mounted) return;
            if (r.isOk) {
              Navigator.pop(ctx, true);
            } else {
              // B-065: the confirm-a-bulk-sale pad gets the same real reasons as
              // the lock screen — "wrong PIN" on a closed shop sent the operator
              // retyping a PIN that was never the problem.
              setD(() => error = posPinReasonText(r, ar));
            }
          } catch (e) {
            if (ctx.mounted) setD(() => error = friendlyError(e, ctx));
          }
        }

        return AlertDialog(
          title: Text(ar ? 'تأكيد بيع بالجملة' : 'Confirm bulk sale'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              ar
                  ? 'بيع $_qty بطاقة. أدخل رمز نقطة البيع للمتابعة.'
                  : 'Selling $_qty cards. Enter your POS PIN to continue.',
              style: IntesharType.sans(14, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              textAlign: TextAlign.center,
              style: IntesharType.mono(20, color: Theme.of(ctx).colorScheme.onSurface, letterSpacing: 10),
              decoration: InputDecoration(
                labelText: ar ? 'رمز نقطة البيع' : 'POS PIN',
                counterText: '',
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ar ? 'إلغاء' : 'Cancel')),
            FilledButton(onPressed: submit, child: Text(ar ? 'تأكيد' : 'Confirm')),
          ],
        );
      }),
    );
    return ok == true;
  }

  /// Sell [_qty] cards at once. Guarded by an explicit confirm (count + total, "cannot be
  /// undone") and, from [_pinRequiredFrom] cards up, a server-verified PIN re-entry.
  Future<void> _sellBulk() async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final unit = _quote?.unitPrice ?? widget.sku.price.toDouble();
    final total = unit * _qty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'تأكيد البيع' : 'Confirm sale'),
        content: Text(
          ar
              ? 'سيتم بيع $_qty بطاقة بمبلغ ${Formatters.iqd(total.round())}. لا يمكن التراجع عن هذا الإجراء.'
              : 'This sells $_qty cards for ${Formatters.iqd(total.round())}. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ar ? 'بيع $_qty بطاقة' : 'Sell $_qty cards'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (_qty >= _pinRequiredFrom && !await _confirmPin(ar)) return;
    if (!mounted) return;

    setState(() {
      _revealing = true;
      _saleError = null;
    });
    try {
      final res = await ProductRepository(ref.read(apiClientProvider)).drawBulk(
        sku: widget.sku.sku,
        governorate: widget.sku.governorate,
        qty: _qty,
        batchRef: _clientRef, // one batch key per sheet — a replay re-serves, never re-charges
      );
      widget.onConsumed();
      if (!mounted) return;
      setState(() => _bulk = res);
      // Warm the logo cache off the print critical path.
      final first = res.cards.isNotEmpty ? res.cards.first : null;
      if (first != null) {
        final t = first.product.productDefinition.template;
        if (t.showAgentLogo) loadReceiptLogo(first.agentLogoUrl);
        if (t.showCompanyLogo) loadReceiptLogo(first.companyLogoUrl);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saleError =
            posSaleFailure(e, ar: _ar, friendly: friendlyError(e, context)));
      }
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  /// Cards printed so far in the current batch run (drives the progress label).
  int _printedCount = 0;

  /// Print ONE card of a batch, confirming its own PrintOperation. Each card is a real
  /// sale record, so a failure here just leaves that row "not printed" — recoverable from
  /// the التقارير tab exactly like a single sale.

  /// Localized receipt labels, read while a BuildContext is still valid.
  ReceiptLabels _receiptLabels() {
    final l = AppLocalizations.of(context)!;
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return ReceiptLabels(
      serial: l.posSerial,
      pin: l.posPin,
      expiry: arabic ? 'تاريخ الانتهاء' : 'Expiry',
      receiptNo: arabic ? 'رقم العملية' : 'Receipt #',
    );
  }

  Future<void> _printCard(RevealResult card) async {
    // Captured before any await: the printed labels must match the voucher the
    // operator is looking at, and context must not be read across an async gap.
    final labels = _receiptLabels();
    final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
    final p = card.product;
    final def = p.productDefinition;
    final t = def.template;
    // CR-06: one receipt, one queue, whatever the printer. The transport picks
    // bytes or text; the POS no longer branches on the terminal's brand.
    // UX-59: the CARD IS ALREADY SOLD by the time we get here — the logo is
    // decorative and must never hold up the paper. Cached logos (the reveal warms
    // them) come back instantly; an unfetched one gets a short budget and is then
    // skipped, with the download left running for the next receipt.
    final agentLogo = t.showAgentLogo ? await receiptLogoForPrinting(card.agentLogoUrl) : null;
    final companyLogo = t.showCompanyLogo ? await receiptLogoForPrinting(card.companyLogoUrl) : null;
    final job = await buildVoucherPrintJob(
      template: t,
      headerFallback: auth?.entity.meta.name ?? 'POS',
      shopName: auth?.entity.meta.name ?? 'Store',
      productName: def.name,
      price: Formatters.iqd(def.defaultPrice),
      serial: p.serialNumber,
      pin: p.pin,
      timestamp: DateTime.now(),
      agentLogo: agentLogo,
      companyLogo: companyLogo,
      companyName: card.companyName,
      categoryName: card.categoryName ?? def.name,
      expiry: p.expiryDate,
      receiptNo: card.receiptNo,
      labelSerial: labels.serial,
      labelPin: labels.pin,
      labelExpiry: labels.expiry,
      labelReceiptNo: labels.receiptNo,
    );
    await ref.read(printQueueProvider).enqueue(job);
    final id = card.operationId;
    if (id != null && id.isNotEmpty) {
      try {
        await ProductRepository(ref.read(apiClientProvider)).confirmPrint(id, printed: true);
      } catch (_) {
        // Best-effort: the row stays "not printed" and is reprintable from التقارير.
      }
    }
  }

  /// Reprint a single row on demand (per-row retry after a failed print).
  Future<void> _printOne(RevealResult card) async {
    final messenger = ScaffoldMessenger.of(context);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    try {
      await _printCard(card);
      if (mounted) setState(() => _printError = null);
      messenger.showSnackBar(SnackBar(content: Text(ar ? 'تمت الطباعة' : 'Printed')));
    } catch (e) {
      // UX-49: the real printer reason, and it stays on screen — these cards are
      // already sold.
      if (mounted) setState(() => _printError = printerErrorMessage(e, ar: ar));
    }
  }

  /// Print every card in the batch, one at a time through the serialized queue, keeping a
  /// live count. One failure does not abort the rest — the failed rows stay reprintable.
  Future<void> _printAll(BulkDrawResult bulk) async {
    setState(() {
      _printing = true;
      _printedCount = 0;
      _printError = null;
    });
    var failed = 0;
    Object? lastError;
    for (final card in bulk.cards) {
      try {
        await _printCard(card);
      } catch (e) {
        failed++;
        lastError = e;
      }
      if (!mounted) return;
      setState(() => _printedCount++);
    }
    if (!mounted) return;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    setState(() {
      _printing = false;
      // UX-49: how many failed AND why — the count alone left the operator
      // guessing at a printer they could have fixed in ten seconds.
      _printError = failed == 0
          ? null
          : '${ar ? 'فشلت طباعة $failed بطاقة — أعد طباعتها من القائمة.' : '$failed card(s) failed to print — reprint them from the list.'} '
              '${printerErrorMessage(lastError, ar: ar)}';
    });
  }

  Future<void> _reveal() async {
    // qty > 1 takes the batched path; qty == 1 stays exactly the old single-card flow.
    if (_qty > 1) return _sellBulk();
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
      // A 402 (no withdrawal limit) or 409 (pool empty) means NOTHING was sold; a
      // timeout means we simply do not know. Both get a PERSISTENT banner (never a
      // fleeting snackbar) — but with DIFFERENT words, because only the second one
      // may have left a sold card stranded (UX-62). The operator can retry (same
      // idempotency key, never a 2nd card) or back out. Do NOT close as consumed.
      setState(() => _saleError =
          posSaleFailure(e, ar: _ar, friendly: friendlyError(e, context)));
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  Future<void> _print() async {
    final revealed = _sent;
    if (revealed == null) return; // print is only reachable after reveal
    final labels = _receiptLabels();
    setState(() {
      _printing = true;
      _printError = null; // clear the last failure while a retry is in flight
    });
    try {
      final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
      final def = revealed.productDefinition;
      final t = def.template;
      // Logos are best-effort AND time-boxed (UX-59): the code on this sheet is
      // already sold, so a slow logo host may not stand between the customer and
      // their receipt. Normally these are already cached — the reveal warms them.
      final agentLogo = t.showAgentLogo ? await receiptLogoForPrinting(_agentLogoUrl) : null;
      final companyLogo = t.showCompanyLogo ? await receiptLogoForPrinting(_companyLogoUrl) : null;
      // CR-06: build the receipt ONCE. Every raw transport (Sunmi AIDL, Bluetooth
      // Classic SPP, USB, TCP, BLE) prints these exact bytes, so the paper is the
      // same on every terminal. Only the vendor-intent fallback uses the text
      // twin — and the UI labels that output approximate.
      final job = await buildVoucherPrintJob(
        template: t,
        headerFallback: auth?.entity.meta.name ?? 'POS',
        shopName: auth?.entity.meta.name ?? 'Store',
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
        labelSerial: labels.serial,
        labelPin: labels.pin,
        labelExpiry: labels.expiry,
        labelReceiptNo: labels.receiptNo,
      );
      // Enqueue on the serialized print queue: one write at a time (so
      // rapid/concurrent prints never interleave bytes) with retry on transient
      // printer failures.
      await ref.read(printQueueProvider).enqueue(job);
      await _confirmPrinted();
      if (mounted) widget.onPrinted();
    } catch (e) {
      // The code is already sold; a failed print must NOT be a fleeting snackbar the
      // operator can miss and then tap "Done" believing it printed. Keep the sheet open
      // and surface a PERSISTENT banner (mirrors the sale-error banner) with a Reprint.
      //
      // UX-49: mapped by [printerErrorMessage], NOT friendlyError — a printer
      // throws a plain Exception, which friendlyError cannot classify and so
      // reports as a NETWORK problem. That sent operators to the WiFi settings
      // while the printer was simply out of paper.
      if (mounted) {
        setState(() => _printError = printerErrorMessage(e, ar: _ar));
      }
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

    // The single dismissal gate for EVERY state of this sheet (UX-64).
    //
    // Before the draw: nothing has happened, so back and a scrim tap are allowed
    // to cancel — the sheet is no different from any other cancellable sheet.
    //
    // From the moment the draw is IN FLIGHT (_revealing) and forever after the
    // sale (_sold): the server may already have claimed and debited the card, so
    // the code on this sheet is the only copy the shop will ever see. Nothing may
    // discard it except an explicit Done/Print. This also covers the BULK sheet,
    // which previously relied entirely on isDismissible: false.
    return PopScope(
      canPop: !_sold && !_revealing,
      child: _sheetBody(l, cs),
    );
  }

  Widget _sheetBody(AppLocalizations l, ColorScheme cs) {
    // A committed BULK sale renders its own list (PINs masked) instead of one receipt.
    final bulk = _bulk;
    if (bulk != null) return _bulkSheet(l, cs, bulk);
    // Pre-sale: a lean card (SKU + price + pool count) + the Sell button. The full
    // template-driven receipt only renders AFTER the draw, when we hold the real card.
    if (_sent == null) return _preRevealSheet(l, cs);

    final revealed = _sent != null; // always true past the guard above
    final p = _sent!;
    final def = p.productDefinition;
    final t = def.template;

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
                        Image.network(_agentLogoUrl!,
                            height: 44,
                            fit: BoxFit.contain,
                            semanticLabel: _ar ? 'شعار الوكيل' : 'Agent logo',
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        const SizedBox(height: 8),
                      ],
                      if (t.showCompanyLogo && (_companyLogoUrl ?? '').trim().isNotEmpty) ...[
                        Image.network(_companyLogoUrl!,
                            height: 36,
                            fit: BoxFit.contain,
                            semanticLabel: (_companyName ?? '').trim().isNotEmpty
                                ? _companyName!.trim()
                                : (_ar ? 'شعار الشركة' : 'Company logo'),
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                        const SizedBox(height: 8),
                      ],
                      const PosBrandMark(size: 40),
                      const SizedBox(height: 10),
                      Text(
                        t.headerText.trim().isNotEmpty
                            ? t.headerText.trim().toUpperCase()
                            : (posShopName(ref).isNotEmpty ? posShopName(ref).toUpperCase() : 'POS'),
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
                          style: IntesharType.mono(16, color: context.tones.brandInk, w: FontWeight.w800),
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
                            // Deliberately NOT theme tokens: a QR is a scan
                            // target, not a surface. It stays fixed dark-on-white
                            // whatever the agent's brand or the device theme is,
                            // because a white-label palette that lightened these
                            // modules would make the customer's code unscannable.
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
    );
  }

  /// UX-72: type the quantity instead of stepping to it.
  ///
  /// Nothing here touches the sale: it only edits [_qty] BEFORE the operator
  /// commits, and the same confirm dialog (+ PIN above [_pinRequiredFrom]) still
  /// stands between this number and `/product/drawBulk`. The value is clamped to
  /// the server's [_maxQty] on the way in, so the pad can never ask for more
  /// than the quote allows — and the server clamps again regardless.
  Future<void> _editQty(bool ar) async {
    final ctrl = TextEditingController(text: '$_qty');
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        void submit() {
          final n = int.tryParse(ctrl.text.trim());
          if (n == null || n < 1) {
            Navigator.pop(ctx);
            return;
          }
          Navigator.pop(ctx, n.clamp(1, _maxQty));
        }

        return AlertDialog(
          title: Text(ar ? 'الكمية' : 'Quantity'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 4,
              textAlign: TextAlign.center,
              style: IntesharType.mono(28, color: cs.onSurface, w: FontWeight.w900),
              decoration: InputDecoration(
                counterText: '',
                // The ceiling, stated where the number is entered — a typed 50
                // against a max of 12 is otherwise a silent correction.
                helperText: ar ? 'الحد الأقصى $_maxQty' : 'Max $_maxQty',
                helperMaxLines: 2,
              ),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 12),
            // Round numbers a shop actually asks for, capped at what it may buy.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final n in <int>{5, 10, 20, 50, _maxQty}.where((n) => n > 1 && n <= _maxQty).toList()..sort())
                  ActionChip(
                    label: Text('$n'),
                    onPressed: () => Navigator.pop(ctx, n),
                  ),
              ],
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ar ? 'إلغاء' : 'Cancel')),
            FilledButton(onPressed: submit, child: Text(ar ? 'تأكيد' : 'Set')),
          ],
        );
      },
    );
    if (picked != null && mounted) setState(() => _qty = picked);
  }

  /// B-086 quantity stepper — the single entry point for a bulk sale. Starts at 1 (so a
  /// mis-tap can never escalate a sale), clamps to the server's [_maxQty], and shows the
  /// running total plus WHY the ceiling is what it is.
  Widget _quantityStepper(ColorScheme cs) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final q = _quote;
    final unit = q?.unitPrice ?? widget.sku.price.toDouble();
    final total = unit * _qty;

    // Explain the binding constraint so the operator isn't left guessing.
    String? hint;
    if (_maxQty <= 1) {
      hint = null;
    } else if (q != null && _maxQty < q.configuredLimit) {
      hint = switch (q.limitedBy) {
        'CAP' => ar ? 'الحد اليومي: $_maxQty متبقية' : 'Daily limit — $_maxQty left',
        'STOCK' => ar ? 'المتوفر: $_maxQty فقط' : 'Only $_maxQty in stock',
        'BALANCE' => ar ? 'رصيدك يكفي $_maxQty' : 'Your balance covers $_maxQty',
        _ => ar ? 'الحد الأقصى $_maxQty' : 'Max $_maxQty',
      };
    } else {
      hint = ar ? 'الحد الأقصى $_maxQty' : 'Max $_maxQty';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.filledTonal(
            onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
            icon: const Icon(Icons.remove, size: 20),
            tooltip: ar ? 'إنقاص' : 'Decrease',
          ),
          // UX-72: the number is a BUTTON, not a caption. Selling 30 cards was
          // 29 taps on the + key, one-handed, with a customer waiting — and
          // nothing on screen said the count could be typed. The stepper keeps
          // ±1 for the common small adjustment; this is the way out of it.
          Tooltip(
            message: ar ? 'اكتب الكمية' : 'Type a quantity',
            child: InkWell(
              onTap: _maxQty > 1 ? () => _editQty(ar) : null,
              borderRadius: BorderRadius.circular(IntesharRadii.md),
              child: Container(
                width: 88,
                height: 52, // ≥48dp: this is a counter device, one-handed.
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(IntesharRadii.md),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$_qty',
                      style: IntesharType.display(28, color: cs.onSurface, w: FontWeight.w900),
                    ),
                    if (_maxQty > 1) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.edit_outlined, size: 13, color: cs.onSurfaceVariant),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: _qty < _maxQty ? () => setState(() => _qty++) : null,
            icon: const Icon(Icons.add, size: 20),
            tooltip: ar ? 'زيادة' : 'Increase',
          ),
        ]),
        if (hint != null)
          Text(hint, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
        if (_qty > 1) ...[
          const SizedBox(height: 8),
          Text(
            '${ar ? 'الإجمالي' : 'Total'}: ${Formatters.iqd(total.round())}',
            style: IntesharType.mono(16, color: context.tones.brandInk, w: FontWeight.w800),
          ),
        ],
      ]),
    );
  }

  /// B-086 post-sale list for a bulk sale. PINs are MASKED by default — a screen holding
  /// ten codes is a far bigger prize for a shoulder-surfer than one, and the printed cards
  /// are the actual deliverable. Each row reveals and reprints on demand.
  Widget _bulkSheet(AppLocalizations l, ColorScheme cs, BulkDrawResult bulk) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              Icon(Icons.check_circle, color: context.status.success, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    ar ? 'تم بيع ${bulk.sold} بطاقة' : '${bulk.sold} cards sold',
                    style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w800),
                  ),
                  Text(
                    '${widget.sku.name}  ·  ${Formatters.iqd(bulk.total.round())}',
                    style: IntesharType.sans(12, color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
          ),
          // Partial fulfilment is normal (the pool drained) — say so plainly; the
          // unsold remainder was refunded server-side.
          if (bulk.isPartial)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(IntesharRadii.md),
                  border: Border.all(color: cs.outline),
                ),
                child: Text(
                  ar
                      ? 'طُلب ${bulk.requested} وتوفّر ${bulk.sold}. لم يتم خصم قيمة غير المتوفر.'
                      : 'Asked for ${bulk.requested}, ${bulk.sold} were available. You were not charged for the rest.',
                  style: IntesharType.sans(12, color: cs.onSurface),
                ),
              ),
            ),
          // UX-49: a print failure in a BULK sale was computed into _printError and
          // then rendered nowhere at all — the operator saw the progress label go
          // back to "Print all" and had no idea any card had failed.
          if (_printError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(IntesharRadii.md),
                  border: Border.all(color: cs.error.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.print_disabled_outlined, size: 18, color: cs.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _printError!,
                        style: TextStyle(fontFamily: 'CodecPro', fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w700, color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              itemCount: bulk.cards.length,
              itemBuilder: (_, i) => _BulkCardRow(
                card: bulk.cards[i],
                index: i + 1,
                onPrint: () => _printOne(bulk.cards[i]),
              ),
            ),
          ),
          // UX-91: on a batch the queue depth is the whole story — "Printing 3/10"
          // says which card, this says whether the printer is keeping up or the
          // current one is on its second attempt.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: PrintQueueLine(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Expanded(
                child: BrandCTAButton(
                  label: l.posDone,
                  variant: BrandCTAVariant.outline,
                  onPressed: _printing ? null : () => widget.onPrinted(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: BrandCTAButton(
                  label: _printing
                      ? (ar ? 'جارٍ الطباعة $_printedCount/${bulk.cards.length}' : 'Printing $_printedCount/${bulk.cards.length}')
                      : (ar ? 'طباعة الكل' : 'Print all'),
                  leading: _printing ? null : Icons.print_outlined,
                  loading: _printing,
                  onPressed: _printing ? null : () => _printAll(bulk),
                ),
              ),
            ]),
          ),
        ]),
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
                    const PosBrandMark(size: 40),
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
                      style: IntesharType.mono(16, color: context.tones.brandInk, w: FontWeight.w800),
                    ),
                    const SizedBox(height: 16),
                    _LockedQr(label: l.posPinHidden),
                    const SizedBox(height: 14),
                    Text(
                      Localizations.localeOf(context).languageCode == 'ar' ? 'المتوفر في مخزن الوكيل: ${s.available}' : 'In main-agent pool: ${s.available}',
                      style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                    // UX-52: the tile's count and this pool count are DIFFERENT
                    // numbers (what your balance covers vs. what the agent holds),
                    // which read as a contradiction. Say both when they differ.
                    if (s.affordable < s.available) ...[
                      const SizedBox(height: 2),
                      Text(
                        _ar ? 'رصيدك يكفي ${s.affordable} بطاقة' : 'Your balance covers ${s.affordable}',
                        style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, color: context.tones.brandInk, fontWeight: FontWeight.w800),
                      ),
                    ],
                    // B-086: sell several cards at once (a shop asking for e.g. 10).
                    // Only rendered when this account is actually allowed more than one.
                    if (_bulkAvailable) _quantityStepper(cs),
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
          //
          // UX-55: this is the warning that silently did not fire in the most
          // common failure mode. It keyed off `status == connected`, which was set
          // once at adoption and never re-checked, so a printer switched off or out
          // of range kept the banner hidden and the operator learned about it with
          // a burned code in hand. The sheet re-probes on open (see initState) and
          // an unreachable printer now says so — in its own words, amber rather than
          // grey, because "chosen but not answering" is a different problem from
          // "none set up" and has a different fix.
          Consumer(
            builder: (ctx, ref, _) {
              final ps = ref.watch(printerServiceProvider);
              if (ps.isReady) return const SizedBox.shrink();
              final info = printerStatusInfo(ps, ar: ar);
              final warning = info.tone == PrinterChipTone.warn;
              final tint = info.tone.color(ctx);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: warning
                        ? tint.withValues(alpha: 0.10)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(IntesharRadii.md),
                    border: Border.all(
                        color: warning ? tint.withValues(alpha: 0.45) : cs.outline),
                  ),
                  child: Row(
                    children: [
                      Icon(info.icon, size: 18, color: warning ? tint : cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          info.sentence ?? info.label,
                          style: TextStyle(fontFamily: 'CodecPro', fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                        // UX-119: no compact density — this is the "fix your
                        // printer" escape hatch on the last screen before an
                        // irreversible sale, and compact would drop its tap
                        // target from 48dp to 40dp.
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: Text(
                          ps.needsChoice
                              ? (ar ? 'اختيار' : 'Choose')
                              : (ar ? 'ربط' : 'Connect'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Persistent failure banner: the last sale attempt failed. Stays until the
          // next attempt succeeds.
          //
          // UX-62: a refusal the server sent (402 no-limit, 409 pool-empty) and a
          // request that never came back are DIFFERENT events. The first is safe —
          // no card, no debit. The second may have claimed a card whose code never
          // reached this screen, so the banner has to say that retrying re-serves
          // the same sale rather than charging twice, and where to find the sale
          // (التقارير) if the operator backs out instead.
          if (_saleError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _saleError!.outcomeUnknown
                    ? context.status.warn.withValues(alpha: 0.12)
                    : cs.errorContainer,
                borderRadius: BorderRadius.circular(IntesharRadii.md),
                border: Border.all(
                    color: _saleError!.outcomeUnknown
                        ? context.status.warn.withValues(alpha: 0.55)
                        : cs.error.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _saleError!.outcomeUnknown ? Icons.help_outline : Icons.error_outline,
                    size: 18,
                    color: _saleError!.outcomeUnknown ? context.status.warn : cs.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _saleError!.headline,
                          style: TextStyle(
                              fontFamily: 'CodecPro',
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                              color: _saleError!.outcomeUnknown ? cs.onSurface : cs.onErrorContainer),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _saleError!.detail,
                          style: TextStyle(
                              fontFamily: 'CodecPro',
                              fontSize: 11.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: _saleError!.outcomeUnknown ? cs.onSurface : cs.onErrorContainer),
                        ),
                      ],
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
              color: context.tones.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(IntesharRadii.md),
              border: Border.all(color: context.tones.brand.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: context.tones.brandInk),
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
                          : (_qty > 1
                              // Name the consequence: how many cards and for how much.
                              ? (ar
                                  ? 'بيع $_qty بطاقة · ${Formatters.iqd(((_quote?.unitPrice ?? widget.sku.price.toDouble()) * _qty).round())}'
                                  : 'Sell $_qty cards · ${Formatters.iqd(((_quote?.unitPrice ?? widget.sku.price.toDouble()) * _qty).round())}')
                              : (ar ? 'بيع وإظهار' : 'Sell & reveal'))),
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
          final ps = ref.watch(printerServiceProvider);
          final isConnected = ps.isReady;
          // UX-55: the code is ALREADY SOLD here, so a failed probe must not
          // take the Print button away — a probe can be wrong, and trapping a
          // paid-for code behind our own guess is the worse failure. The chip
          // tells the truth; the button still lets them try, and a real failure
          // comes back through printerErrorMessage with something actionable.
          final canPrint = ps.hasPrinter;
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.print_disabled_outlined, size: 18, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ar
                                  ? 'فشلت الطباعة — الرمز مُباع.'
                                  : 'Print failed — the code is sold.',
                              style: TextStyle(fontFamily: 'CodecPro', fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w800, color: cs.onErrorContainer),
                            ),
                            const SizedBox(height: 3),
                            // UX-49: the actual, actionable reason. It was being
                            // computed into _printError and then thrown away here
                            // in favour of a fixed sentence.
                            Text(
                              _printError!,
                              style: TextStyle(fontFamily: 'CodecPro', fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: cs.onErrorContainer),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              ar
                                  ? 'أو انسخ/شارك الرمز أدناه.'
                                  : 'Or copy/share the code below.',
                              style: TextStyle(fontFamily: 'CodecPro', fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w600, color: cs.onErrorContainer),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // CR-06: the vendor-intent path hands the receipt to another app to
              // lay out, so its paper genuinely differs from every other terminal.
              // Say so at the counter, not only in the setup screen.
              if (isConnected && ps.isApproximate) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.status.warn.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(IntesharRadii.md),
                    border: Border.all(color: context.status.warn.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: context.status.warn),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ar
                              ? 'هذه الطابعة تعيد تنسيق الإيصال — قد يختلف شكله عن بقية الأجهزة.'
                              : 'This printer re-formats the receipt — it may not match other devices.',
                          style: TextStyle(fontFamily: 'CodecPro', fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w600, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              PrinterStatusChip(
                state: ps,
                ar: ar,
                filled: true,
                // A voucher sheet is wider than the app bar and this row has
                // nothing to compete with, so the name can run longer here.
                maxWidth: 260,
              ),
              const SizedBox(height: 12),
              if (!isConnected)
                BrandCTAButton(
                  // The printer icon, not a Bluetooth one: the head may be the
                  // built-in Sunmi/Rovo thermal printer, no radio involved.
                  label: ps.needsChoice
                      ? (ar ? 'اختر الطابعة' : 'Choose a printer')
                      : l.posConnectPrinter,
                  leading: Icons.print_outlined,
                  variant: BrandCTAVariant.outline,
                  onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                ),
              const SizedBox(height: 8),
              // UX-91: "Printing…" for four seconds is either a printer chewing
              // through paper or attempt 2 of 3 after a silently failed write.
              const PrintQueueLine(),
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
                      onPressed: (_printing || !canPrint) ? null : _print,
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
    // B-080: start on the hint the onboarding agent dropped (if any) rather than
    // the centre of Iraq — the operator nudges a nearby pin instead of hunting.
    final p = ref.read(authStateProvider).valueOrNull;
    final prof = p is AuthAuthenticated ? p.entity.profile : null;
    final hint = (prof?.latitude != null && prof?.longitude != null)
        ? LatLng(prof!.latitude!, prof.longitude!)
        : null;
    final picked = await pickLocationOnMap(context, initial: hint);
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
              style: IntesharType.sans(14, color: cs.onSurfaceVariant),
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

/// B-086: one card in a bulk-sale list. The PIN is MASKED until the operator taps the eye —
/// the printed cards are the deliverable, and a screen showing ten live codes at once is a
/// far bigger prize for a shoulder-surfer than a single sale.
class _BulkCardRow extends StatefulWidget {
  const _BulkCardRow({required this.card, required this.index, required this.onPrint});

  final RevealResult card;
  final int index;
  final Future<void> Function() onPrint;

  @override
  State<_BulkCardRow> createState() => _BulkCardRowState();
}

class _BulkCardRowState extends State<_BulkCardRow> {
  bool _revealed = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final p = widget.card.product;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 26,
            child: Text('${widget.index}',
                style: IntesharType.mono(12, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // UX-147: the serial identifies WHICH card of the batch a
              // customer is disputing — 11px was the smallest text on a screen
              // holding ten live sales.
              Text('#${widget.card.receiptNo}  ·  SN ${p.serialNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.mono(12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                _revealed ? p.pin : '•' * (p.pin.isEmpty ? 8 : p.pin.length.clamp(6, 16)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.mono(14,
                    color: _revealed ? cs.onSurface : cs.onSurfaceVariant,
                    w: FontWeight.w800,
                    letterSpacing: _revealed ? 1 : 2),
              ),
            ]),
          ),
          IconButton(
            tooltip: _revealed ? (ar ? 'إخفاء' : 'Hide') : (ar ? 'إظهار' : 'Reveal'),
            icon: Icon(_revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
            onPressed: () => setState(() => _revealed = !_revealed),
          ),
          IconButton(
            tooltip: ar ? 'طباعة' : 'Print',
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print_outlined, size: 18),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await widget.onPrint();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
        ]),
      ),
    );
  }
}

/// The field labels the printed receipt uses, taken from the SAME strings as the
/// on-screen voucher (`_ReceiptRow`) so paper and screen never disagree.
class ReceiptLabels {
  final String serial;
  final String pin;
  final String expiry;
  final String receiptNo;
  const ReceiptLabels({
    required this.serial,
    required this.pin,
    required this.expiry,
    required this.receiptNo,
  });
}
