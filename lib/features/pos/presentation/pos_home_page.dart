import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/logo_loader.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/pos/presentation/printer_picker_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';
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

class _PosHomePageState extends ConsumerState<PosHomePage> {
  List<Product>? _products;
  Object? _error;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
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
      final all = await repo.readByEntity(auth.entity.id);
      // Sellable = strictly AVAILABLE. Revealing a code consumes it (the backend
      // flips it to PRINTED on decrypt), so anything not AVAILABLE has already
      // been used and must never reappear on the counter.
      final available = all.where((p) => p.status == ProductStatus.AVAILABLE).toList();
      if (mounted) setState(() => _products = available);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<Product>> _groupBySku(List<Product> products) {
    final map = <String, List<Product>>{};
    for (final p in products) {
      map.putIfAbsent(p.productDefinition.sku, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onLongPress: () => context.go('/diagnostics'),
          child: Row(
            children: [
              IntesharStar(size: 22, color: cs.onSurface),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.posHome,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.posHomeLiveCounter,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w600,
                    ),
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
                  onTap: () => Navigator.push<void>(
                      ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                          size: 16,
                          color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                        ),
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
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : _buildGrid(l),
    );
  }

  Widget _buildGrid(AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    final products = _products ?? [];
    final filtered = _search.isEmpty
        ? products
        : products.where((p) {
            final q = _search.toLowerCase();
            return p.productDefinition.name.toLowerCase().contains(q) ||
                p.productDefinition.sku.toLowerCase().contains(q);
          }).toList();
    final groups = _groupBySku(filtered);

    final tileExtent = switch (context.screenSize) {
      ScreenSize.desktop => 260.0,
      ScreenSize.tablet => 220.0,
      ScreenSize.mobile => 168.0,
    };

    return MaxWidthBox(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.posHomePickDenomination,
                        style: IntesharType.display(28, color: cs.onSurface, w: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.posHomeCounterSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _StockTally(stock: products.length),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: TextField(
              decoration: InputDecoration(
                hintText: l.posHomeSearchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (groups.isEmpty)
            Expanded(
              child: EmptyState(
                message: products.isEmpty
                    ? l.posHomeNoVouchers
                    : l.posHomeNoMatches(_search),
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
                    childAspectRatio: 0.82,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final sku = groups.keys.elementAt(i);
                    final items = groups[sku]!;
                    return _SkuTile(
                      sku: sku,
                      products: items,
                      onTap: () => _showVoucher(items.first),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showVoucher(Product product) {
    // Tracks whether the voucher was consumed (revealed, or found already-used)
    // while the sheet was open. Reveal == sale on the backend: the instant it
    // succeeds we drop the code from the in-memory list so a swipe/scrim/back
    // dismissal can never leave the counter inflated, then reconcile on close.
    var consumed = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VoucherSheet(
        product: product,
        // The PIN stays hidden until the operator taps Reveal inside the sheet.
        // Fired the moment the voucher is consumed — drop it from the counter now.
        onConsumed: () {
          consumed = true;
          if (mounted) {
            setState(() => _products?.removeWhere((p) => p.id == product.id));
          }
        },
        // Done / Print just close the sheet; the reload happens in whenComplete.
        onPrinted: () => Navigator.pop(ctx),
      ),
    ).whenComplete(() {
      // ANY dismissal after a reveal (Done, Print, swipe, scrim, or back button)
      // routes through here, re-fetching from the server so the consumed code is
      // gone and the tally matches the source of truth.
      if (consumed) _load();
    });
  }
}

class _StockTally extends StatelessWidget {
  final int stock;
  const _StockTally({required this.stock});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: IntesharColors.saffron,
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        boxShadow: IntesharShadows.ctaShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            l.posHomeInStock,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 10,
              color: IntesharColors.ink.withValues(alpha: 0.65),
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stock.toString(),
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 28,
              color: IntesharColors.ink,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── SKU tile ────────────────────────────────────────────────────────────────

class _SkuTile extends StatefulWidget {
  final String sku;
  final List<Product> products;
  final VoidCallback onTap;
  const _SkuTile({required this.sku, required this.products, required this.onTap});

  @override
  State<_SkuTile> createState() => _SkuTileState();
}

class _SkuTileState extends State<_SkuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final def = widget.products.first.productDefinition;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: PressableScale(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(IntesharRadii.lg),
            boxShadow: _hover ? IntesharShadows.elev2 : IntesharShadows.elev1,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(IntesharRadii.lg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: IntesharColors.saffron,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          widget.sku,
                          style: IntesharType.mono(13, color: IntesharColors.ink, w: FontWeight.w900, letterSpacing: 0.6),
                        ),
                      ),
                      const Spacer(),
                      StampPill(label: '× ${widget.products.length}', color: IntesharColors.sage),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    def.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      color: cs.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.iqd(def.defaultPrice),
                    style: IntesharType.mono(15, color: cs.onSurface, w: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  BrandCTAButton(
                    label: l.posHomeSell,
                    leading: Icons.sell_outlined,
                    onPressed: widget.onTap,
                    height: 38,
                    fontSize: 12.5,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Voucher sheet ───────────────────────────────────────────────────────────

class _VoucherSheet extends ConsumerStatefulWidget {
  final Product product;
  // Fired the instant the voucher is consumed — a successful reveal, or a 409
  // telling us it was already used — so the parent can drop it from the counter.
  final VoidCallback onConsumed;
  final VoidCallback onPrinted;

  const _VoucherSheet({required this.product, required this.onConsumed, required this.onPrinted});

  @override
  ConsumerState<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends ConsumerState<_VoucherSheet> {
  // The list product arrives with its PIN stripped (encrypted at rest). The code
  // stays hidden until the operator EXPLICITLY taps "Reveal" — that single tap
  // calls sendForPrinting, which on the backend atomically marks the voucher used
  // (status PRINTED) and returns the decrypted code. Revealing is the point of
  // sale; it consumes the voucher and cannot be undone.
  Product? _sent;
  int _receiptNo = 0;
  String? _agentLogoUrl;
  String? _companyLogoUrl;
  bool _revealing = false;
  bool _printing = false;

  bool get _revealed => _sent != null;

  Future<void> _reveal() async {
    setState(() => _revealing = true);
    try {
      final api = ref.read(apiClientProvider);
      final full = await ProductRepository(api).sendForPrinting(widget.product.id);
      // The backend has atomically flipped this voucher to PRINTED (used). Drop it
      // from the counter NOW — before any further interaction — so an accidental
      // swipe/scrim/back can't leave the consumed code lingering on the tally.
      widget.onConsumed();
      if (mounted) {
        setState(() {
          _sent = full.product;
          _receiptNo = full.receiptNo;
          _agentLogoUrl = full.agentLogoUrl;
          _companyLogoUrl = full.companyLogoUrl;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.posHomePrintFailed(e.toString())), backgroundColor: Theme.of(context).colorScheme.error),
      );
      // Already used / no longer available → drop it from the counter and close.
      // The interceptor throws a DioException wrapping the ApiException, so unwrap
      // before inspecting the status (a bare `e is ApiException` never matches).
      final apiErr = ApiException.from(e);
      if (apiErr?.statusCode == 409) {
        widget.onConsumed();
        widget.onPrinted();
      }
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  Future<void> _print() async {
    final revealed = _sent;
    if (revealed == null) return; // print is only reachable after reveal
    setState(() => _printing = true);
    try {
      final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
      final def = revealed.productDefinition;
      final t = def.template;
      // Fetch + decode the logos (best-effort; printing proceeds without them on failure).
      final agentLogo = t.showAgentLogo ? await loadReceiptLogo(_agentLogoUrl) : null;
      final companyLogo =
          t.showCompanyLogo ? await loadReceiptLogo(_companyLogoUrl) : null;
      final bytes = await buildVoucherReceipt(
        template: t,
        companyName: 'Inteshar Platform',
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
        expiry: revealed.expiryDate,
        receiptNo: _receiptNo,
      );
      await ref.read(bluetoothServiceProvider.notifier).send(bytes);
      if (mounted) widget.onPrinted();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.posHomePrintFailed(e.toString())), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    final revealed = _revealed;
    final p = _sent ?? widget.product;
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
        padding: EdgeInsets.only(
          bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            // Receipt preview tile
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(IntesharRadii.lg),
                  boxShadow: IntesharShadows.elev2,
                ),
                child: Column(
                  children: [
                    IntesharStar(size: 36, color: cs.onSurface),
                    const SizedBox(height: 10),
                    Text(
                      t.headerText.trim().isNotEmpty
                          ? t.headerText.trim().toUpperCase()
                          : 'INTESHAR PLATFORM',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        fontSize: 12,
                        color: cs.onSurface,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (t.showProductName) ...[
                      const SizedBox(height: 16),
                      Text(
                        def.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'CodecPro',
                          fontSize: 22,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
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
                    if (t.showSerial) ...[
                      _ReceiptRow(label: l.posSerial, value: p.serialNumber, monoSize: 13),
                      const SizedBox(height: 12),
                    ],
                    if (t.showPin)
                      _ReceiptRow(
                        label: l.posPin,
                        value: revealed ? p.pin : '•••• •••• ••••',
                        monoSize: 20,
                        monoSpacing: 5,
                      ),
                    if (t.qrEnabled) ...[
                      const SizedBox(height: 16),
                      if (revealed)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(IntesharRadii.sm),
                          ),
                          child: QrImageView(
                            data: t.qrPayload(pin: p.pin, serial: p.serialNumber),
                            version: QrVersions.auto,
                            size: 128,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: IntesharColors.ink,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: IntesharColors.ink,
                            ),
                          ),
                        )
                      else
                        _LockedQr(label: l.posPinHidden),
                      if (revealed) ...[
                        const SizedBox(height: 8),
                        Text(
                          t.redeemInstructions.trim().isNotEmpty
                              ? t.redeemInstructions.trim()
                              : t.qrPayload(pin: p.pin, serial: p.serialNumber),
                          textAlign: TextAlign.center,
                          style: IntesharType.mono(12, color: cs.onSurface, w: FontWeight.w700),
                        ),
                      ],
                    ],
                    if (t.showExpiry && (p.expiryDate ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ReceiptRow(
                        label: Localizations.localeOf(context).languageCode == 'ar'
                            ? 'تاريخ الانتهاء'
                            : 'Expiry',
                        value: p.expiryDate!,
                        monoSize: 13,
                      ),
                    ],
                    if (revealed && _receiptNo > 0) ...[
                      const SizedBox(height: 12),
                      _ReceiptRow(
                        label: Localizations.localeOf(context).languageCode == 'ar'
                            ? 'رقم العملية'
                            : 'Receipt #',
                        value: '$_receiptNo',
                        monoSize: 13,
                      ),
                    ],
                    const SizedBox(height: 14),
                    const _ReceiptDivider(),
                    const SizedBox(height: 14),
                    Text(
                      t.footerText.trim().isNotEmpty
                          ? t.footerText.trim()
                          : l.posHomeScratchNote,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
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

  // Pre-reveal: the PIN/QR are masked. The operator must explicitly tap Reveal,
  // which consumes the voucher (decrypt == used) — so we surface that warning.
  Widget _buildRevealActions(AppLocalizations l, ColorScheme cs) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        children: [
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
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: BrandCTAButton(
                  label: l.posHomeCancel,
                  variant: BrandCTAVariant.outline,
                  onPressed: _revealing ? null : () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BrandCTAButton(
                  label: _revealing ? l.posRevealing : l.posReveal,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Consumer(
        builder: (ctx, ref, _) {
          final ps = ref.watch(bluetoothServiceProvider);
          final isConnected = ps.status == PrinterStatus.connected;
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isConnected
                      ? IntesharColors.sage.withValues(alpha: 0.10)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isConnected ? IntesharColors.sage.withValues(alpha: 0.4) : cs.outline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      size: 14,
                      color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isConnected
                          ? (ps.deviceName ?? l.posPrinterConnected)
                          : l.posHomePrinterNotConnected,
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
                  onPressed: () => Navigator.push<void>(
                      ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BrandCTAButton(
                      label: l.posDone,
                      variant: BrandCTAVariant.outline,
                      onPressed: _printing ? null : () => widget.onPrinted(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BrandCTAButton(
                      label: _printing ? l.posHomePrinting : l.posPrintVoucher,
                      leading: _printing ? null : Icons.print_outlined,
                      loading: _printing,
                      onPressed: (_printing || !isConnected) ? null : _print,
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
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
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
          style: TextStyle(
            fontFamily: 'CodecPro',
            color: cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
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
    final paint = Paint()..color = color..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
