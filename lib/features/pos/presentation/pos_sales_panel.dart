import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/printing/print_queue.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/logo_loader.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/print_operation.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:share_plus/share_plus.dart';

/// التقارير (سستم A95): the shop's purchased cards over a date window, with
/// re-print / copy / share for any card and a clear badge on sales whose
/// physical print was never confirmed.
class PosSalesPanel extends ConsumerStatefulWidget {
  const PosSalesPanel({super.key});

  @override
  ConsumerState<PosSalesPanel> createState() => _PosSalesPanelState();
}

class _PosSalesPanelState extends ConsumerState<PosSalesPanel> {
  List<PrintOperation> _ops = const [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  late DateTimeRange _range;
  // B-066: page through the window instead of a silent 100-row cap.
  static const int _size = 50;
  int _page = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _notPrintedOnly = false; // end-of-day recovery filter

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    _load();
  }

  String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
    });
    try {
      final ops = await ProductRepository(ref.read(apiClientProvider)).printOperations(
          from: _day(_range.start), to: _day(_range.end), page: 0, size: _size);
      if (!mounted) return;
      setState(() {
        _ops = ops;
        _hasMore = ops.length == _size; // a full page suggests there may be more
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Appends the next page (the API returns a plain list, so a full page ⇒ maybe more).
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final more = await ProductRepository(ref.read(apiClientProvider)).printOperations(
          from: _day(_range.start), to: _day(_range.end), page: next, size: _size);
      if (!mounted) return;
      setState(() {
        _ops = [..._ops, ...more];
        _page = next;
        _hasMore = more.length == _size;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load();
  }

  /// Re-serves the SAME sale (recover — no new card, no new debit) and offers
  /// print / copy / share on the recovered code.
  Future<void> _reprint(PrintOperation op) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final recovered = await repo.drawRecover(productId: op.productId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ReprintSheet(recovered: recovered, op: op, onPrinted: _load),
      );
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final shown = _notPrintedOnly ? _ops.where((o) => !o.printed).toList() : _ops;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 28),
        children: [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range, size: 18),
                label: Text('${_day(_range.start)} → ${_day(_range.end)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            // End-of-day recovery: show only the cards whose print was never confirmed.
            FilterChip(
              selected: _notPrintedOnly,
              onSelected: (v) => setState(() => _notPrintedOnly = v),
              avatar: Icon(Icons.print_disabled_outlined, size: 16,
                  color: _notPrintedOnly ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              label: Text(ar ? 'غير المطبوعة' : 'Not printed'),
            ),
          ]),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _notPrintedOnly
                      ? (ar ? 'لا توجد بطاقات غير مطبوعة.' : 'No unprinted cards.')
                      : (ar ? 'لا توجد بطاقات في هذه الفترة.' : 'No cards in this window.'),
                  style: IntesharType.sans(14, color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final op in shown) _opCard(op, ar, cs),
          // Load the next page. When filtering, the hint reminds the operator that
          // more unprinted cards may still be further back in the window.
          if (_hasMore) ...[
            const SizedBox(height: 4),
            Center(
              child: _loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  : TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: Text(ar ? 'تحميل المزيد' : 'Load more'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _opCard(PrintOperation op, bool ar, ColorScheme cs) {
    final when = op.createdAt.length >= 16
        ? op.createdAt.substring(0, 16).replaceFirst('T', ' ')
        : op.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${op.productName.isNotEmpty ? op.productName : op.sku}  ·  #${op.receiptNo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
            ),
            if (!op.printed)
              StampPill(
                  label: ar ? 'لم تتم الطباعة' : 'Not printed',
                  color: IntesharColors.oxblood),
          ]),
          const SizedBox(height: 3),
          Text('SN ${op.serialNumber}',
              style: IntesharType.mono(11.5, color: cs.onSurfaceVariant)),
          Row(children: [
            Expanded(
                child: Text(when,
                    style: IntesharType.mono(11, color: cs.onSurfaceVariant))),
            if (op.soldPrice != null)
              Text(Formatters.iqd(op.soldPrice!.round()),
                  style: IntesharType.mono(12.5, color: cs.onSurface)),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _reprint(op),
              icon: const Icon(Icons.print_outlined, size: 16),
              label: Text(ar ? 'إعادة طباعة / مشاركة' : 'Reprint / share'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bottom sheet for a recovered sale: print again (confirms the print outcome),
/// copy the PIN, or share the receipt as text.
class _ReprintSheet extends ConsumerStatefulWidget {
  const _ReprintSheet({required this.recovered, required this.op, required this.onPrinted});
  final RevealResult recovered;
  final PrintOperation op;
  final VoidCallback onPrinted;

  @override
  ConsumerState<_ReprintSheet> createState() => _ReprintSheetState();
}

class _ReprintSheetState extends ConsumerState<_ReprintSheet> {
  bool _printing = false;

  String _receiptText() {
    final p = widget.recovered.product;
    final def = p.productDefinition;
    return [
      widget.recovered.companyName ?? '',
      def.name,
      'SN: ${p.serialNumber}',
      'PIN: ${p.pin}',
      if (p.expiryDate != null && p.expiryDate!.isNotEmpty) 'EXP: ${p.expiryDate}',
      '#${widget.recovered.receiptNo}',
    ].where((s) => s.isNotEmpty).join('\n');
  }

  Future<void> _print() async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    setState(() => _printing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
      final p = widget.recovered.product;
      final def = p.productDefinition;
      final t = def.template;
      final agentLogo = t.showAgentLogo ? await loadReceiptLogo(widget.recovered.agentLogoUrl) : null;
      final companyLogo = t.showCompanyLogo ? await loadReceiptLogo(widget.recovered.companyLogoUrl) : null;
      final bytes = await buildVoucherReceipt(
        template: t,
        headerFallback: 'Inteshar Platform',
        shopName: auth?.entity.meta.name ?? 'Store',
        posLabel: 'Counter 1',
        operatorPhone: auth?.entity.users.firstOrNull?.phone ?? '',
        productName: def.name,
        price: Formatters.iqd(def.defaultPrice),
        serial: p.serialNumber,
        pin: p.pin,
        timestamp: DateTime.now(),
        agentLogo: agentLogo,
        companyLogo: companyLogo,
        companyName: widget.recovered.companyName,
        categoryName: widget.recovered.categoryName ?? def.name,
        expiry: p.expiryDate,
        receiptNo: widget.recovered.receiptNo,
      );
      await ref.read(printQueueProvider).enqueue(bytes);
      // B-054: a successful physical print confirms the sale's print outcome.
      final opId = widget.recovered.operationId ?? widget.op.id;
      if (opId.isNotEmpty) {
        try {
          await ProductRepository(ref.read(apiClientProvider))
              .confirmPrint(opId, printed: true);
        } catch (_) {}
      }
      widget.onPrinted();
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(ar ? 'تمت الطباعة' : 'Printed')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final p = widget.recovered.product;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 20,
        right: 20,
        top: 16,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 14),
        Text(widget.recovered.categoryName ?? p.productDefinition.name,
            textAlign: TextAlign.center,
            style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('SN ${p.serialNumber}',
            textAlign: TextAlign.center,
            style: IntesharType.mono(12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        SelectableText(p.pin,
            textAlign: TextAlign.center,
            style: IntesharType.mono(22, color: cs.onSurface, letterSpacing: 2)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _printing ? null : _print,
          icon: const Icon(Icons.print_outlined, size: 18),
          label: Text(ar ? 'طباعة' : 'Print'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: p.pin));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ar ? 'تم النسخ' : 'Copied')));
                }
              },
              icon: const Icon(Icons.copy, size: 16),
              label: Text(ar ? 'نسخ الرمز' : 'Copy PIN'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                // Real OS share sheet (WhatsApp, SMS, …). Falls back to a clipboard
                // copy if the platform has no share provider (e.g. desktop/web).
                try {
                  await SharePlus.instance.share(
                    ShareParams(text: _receiptText()),
                  );
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: _receiptText()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
        ]),
      ]),
    );
  }
}
