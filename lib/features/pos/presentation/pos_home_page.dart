import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/logo_loader.dart';
import 'package:inteshar/core/printing/print_queue.dart';
import 'package:inteshar/core/printing/rovo_printer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
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
  List<SellableSku>? _sellable;
  AgentBalance? _balance;
  Object? _error;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    // Gate the POS terminal behind a PIN lock on every session start.
    // The lock page (or setup page, if no PIN is configured) handles
    // authentication; once the session is unlocked we load the inventory.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPinGate());
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
      if (mounted) {
        setState(() {
          _sellable = sellable;
          _balance = balance;
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
                        Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, size: 16, color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : _buildGrid(l),
    );
  }

  Widget _buildGrid(AppLocalizations l) {
    final cs = Theme.of(context).colorScheme;
    final sellable = _sellable ?? [];
    final filtered = _search.isEmpty
        ? sellable
        : sellable.where((s) {
            final q = _search.toLowerCase();
            return s.name.toLowerCase().contains(q) || s.sku.toLowerCase().contains(q);
          }).toList();
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
                      Text(l.posHomeCounterSubtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                _BalanceTally(balance: _balance),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: TextField(
              decoration: InputDecoration(hintText: l.posHomeSearchHint, prefixIcon: const Icon(Icons.search, size: 18)),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (filtered.isEmpty)
            Expanded(
              child: EmptyState(message: sellable.isEmpty ? l.posHomeNoVouchers : l.posHomeNoMatches(_search), actionLabel: l.retryButton, onAction: _load),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: tileExtent, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.82),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final s = filtered[i];
                    return _SkuTile(sellable: s, onTap: () => _showVoucher(s));
                  },
                ),
              ),
            ),
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
      builder: (ctx) => _VoucherSheet(sku: sku, onConsumed: () => consumed = true, onPrinted: () => Navigator.pop(ctx)),
    ).whenComplete(() {
      // After a sale, re-fetch so the pool counts match the source of truth.
      if (consumed) _load();
    });
  }
}

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

// ── SKU tile ────────────────────────────────────────────────────────────────

class _SkuTile extends StatefulWidget {
  final SellableSku sellable;
  final VoidCallback onTap;
  const _SkuTile({required this.sellable, required this.onTap});

  @override
  State<_SkuTile> createState() => _SkuTileState();
}

class _SkuTileState extends State<_SkuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final s = widget.sellable;

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
                        decoration: BoxDecoration(color: IntesharColors.saffron, borderRadius: BorderRadius.circular(24)),
                        child: Text(
                          s.sku,
                          style: IntesharType.mono(13, color: IntesharColors.ink, w: FontWeight.w900, letterSpacing: 0.6),
                        ),
                      ),
                      const Spacer(),
                      // How many THIS POS can print (min of pool stock and what the balance
                      // affords), not the raw main-agent pool count.
                      StampPill(label: '× ${s.affordable}', color: IntesharColors.sage),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    s.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'CodecPro', color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.price > 0 ? Formatters.iqd(s.price) : (Localizations.localeOf(context).languageCode == 'ar' ? 'السعر غير محدَّد' : 'Price not set'),
                    style: IntesharType.mono(15, color: cs.onSurface, w: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  BrandCTAButton(label: l.posHomeSell, leading: Icons.sell_outlined, onPressed: widget.onTap, height: 38, fontSize: 12.5),
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
    setState(() => _printing = true);
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
      if (mounted) widget.onPrinted();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.posHomePrintFailed(e.toString())), backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        children: [
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
                  label: _revealing
                      ? l.posRevealing
                      : (_saleError != null ? l.retryButton : l.posReveal),
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
                  color: isConnected ? IntesharColors.sage.withValues(alpha: 0.10) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: isConnected ? IntesharColors.sage.withValues(alpha: 0.4) : cs.outline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, size: 14, color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant),
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
