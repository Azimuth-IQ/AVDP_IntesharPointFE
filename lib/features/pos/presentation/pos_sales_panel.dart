import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/core/printing/print_queue.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/logo_loader.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/core/printing/report_receipt.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/print_operation.dart';
import 'package:inteshar/features/pos/domain/pos_report_summary.dart';
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

  // سستم A95/التقارير!A1: the window's own figures, and who the report belongs
  // to. The feed returns a bare list with no total, so the summary is walked
  // over the whole window rather than derived from the visible page — a total
  // that silently described only the first 50 sales would read as authoritative.
  static const int _summaryPageCap = 40; // 2,000 sales
  PosReportSummary _summary = PosReportSummary.empty;
  PosReportIdentity _identity = const PosReportIdentity();
  bool _summaryLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
    _load();
    _resolveIdentity();
  }

  /// The report header the spec mandates. The shop knows itself from the
  /// session; the agent names come from `/entity/chain`, which returns display
  /// rows only.
  ///
  /// This used to call `/entity/read` on the parent and then the grandparent —
  /// pulling two whole entity documents (users, phones, KYC) to print two names.
  /// That route is scoped to self-or-descendant now, so an upward read is
  /// correctly refused; the chain endpoint answers the question that was
  /// actually being asked.
  Future<void> _resolveIdentity() async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! AuthAuthenticated) return;
    var identity = PosReportIdentity(
      shopName: auth.entity.meta.name,
      ownerName: auth.entity.profile?.ownerName ?? '',
    );
    if (mounted) setState(() => _identity = identity);

    try {
      final chain = await EntityRepository(ref.read(apiClientProvider)).chain();
      // Match BY TYPE, not by position: a shop usually hangs off a sub-agent,
      // but a flatter tree can put it straight under the main agent, and taking
      // "the first ancestor" would then label a main agent as the sub-agent.
      String nameOf(EntityType t) {
        for (final row in chain) {
          if (row.type == t) return row.name;
        }
        return '';
      }

      identity = PosReportIdentity(
        shopName: identity.shopName,
        ownerName: identity.ownerName,
        subAgentName: nameOf(EntityType.AGENT2),
        mainAgentName: nameOf(EntityType.AGENT1),
      );
      if (mounted) setState(() => _identity = identity);
    } catch (_) {
      // Keep the shop's own lines — a partial header beats no report.
    }
  }

  /// Walks the whole window for the totals. Stops at [_summaryPageCap] and
  /// marks the summary truncated rather than quietly under-reporting.
  Future<void> _loadSummary() async {
    setState(() => _summaryLoading = true);
    final repo = ProductRepository(ref.read(apiClientProvider));
    final all = <PrintOperation>[];
    var truncated = false;
    try {
      for (var p = 0; p < _summaryPageCap; p++) {
        final batch = await repo.printOperations(
            from: _day(_range.start), to: _day(_range.end), page: p, size: _size);
        all.addAll(batch);
        if (batch.length < _size) break;
        if (p == _summaryPageCap - 1) truncated = true;
      }
      if (!mounted) return;
      setState(() {
        _summary = PosReportSummary.from(all, truncated: truncated);
        _summaryLoading = false;
      });
    } catch (_) {
      // The list itself already surfaces load errors; a failed summary must not
      // replace a usable report with an error screen.
      if (mounted) setState(() => _summaryLoading = false);
    }
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
      // Only worth a second walk when the first page was full; otherwise the
      // page we already hold IS the whole window.
      if (_hasMore) {
        _loadSummary();
      } else {
        setState(() => _summary = PosReportSummary.from(ops));
      }
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
          _summaryCard(ar, cs),
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

  /// سستم التقارير!A1 + A4: who the report belongs to, what the window totals,
  /// and the ability to put it on paper / share it — none of which the panel had.
  Widget _summaryCard(bool ar, ColorScheme cs) {
    final s = _summary;
    return InkCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_identity.isEmpty) ...[
          if (_identity.shopName.trim().isNotEmpty)
            Text(_identity.shopName.trim(),
                style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w800)),
          for (final line in [
            if (_identity.ownerName.trim().isNotEmpty)
              '${ar ? 'صاحب النقطة' : 'Owner'}: ${_identity.ownerName.trim()}',
            if (_identity.subAgentName.trim().isNotEmpty)
              '${ar ? 'الوكيل الفرعي' : 'Sub agent'}: ${_identity.subAgentName.trim()}',
            if (_identity.mainAgentName.trim().isNotEmpty)
              '${ar ? 'الوكيل الرئيسي' : 'Main agent'}: ${_identity.mainAgentName.trim()}',
          ])
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line,
                  style: IntesharType.sans(11.5, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 10),
        ],
        Row(children: [
          _stat(ar ? 'عدد الكروت' : 'Cards', '${s.cards}', cs),
          _stat(ar ? 'المجموع' : 'Total', Formatters.iqd(s.total.round()), cs),
          if (s.notPrinted > 0)
            _stat(ar ? 'لم تُطبع' : 'Not printed', '${s.notPrinted}', cs,
                tint: IntesharColors.oxblood),
        ]),
        if (s.unpriced > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              ar
                  ? '${s.unpriced} بطاقة بدون سعر مسجل — غير محتسبة في المجموع'
                  : '${s.unpriced} card(s) have no recorded price — not counted in the total',
              style: IntesharType.sans(11, color: cs.onSurfaceVariant),
            ),
          ),
        if (s.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              ar
                  ? 'الفترة تحتوي على مبيعات أكثر مما تم تحميله — المجموع جزئي'
                  : 'This window holds more sales than were loaded — the total is partial',
              style: IntesharType.sans(11, color: IntesharColors.oxblood, w: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: (_busy || _summaryLoading || s.cards == 0) ? null : _printReport,
              icon: _summaryLoading
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined, size: 16),
              label: Text(ar ? 'طباعة التقرير' : 'Print report'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: (_summaryLoading || s.cards == 0) ? null : _shareReport,
            icon: const Icon(Icons.share_outlined, size: 16),
            label: Text(ar ? 'مشاركة' : 'Share'),
          ),
        ]),
      ]),
    );
  }

  Widget _stat(String label, String value, ColorScheme cs, {Color? tint}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          // Money SHRINKS, it never ellipsizes. A daily total of 25,876,000 IQD
          // clipped to "25,876…" is worse than small type — it reads as a
          // different number. Same rule as the POS balance tally.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                maxLines: 1,
                style: IntesharType.mono(15, color: tint ?? cs.onSurface, w: FontWeight.w700)),
          ),
        ]),
      );

  Future<void> _printReport() async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final job = await buildSalesReportPrintJob(
        identity: _identity,
        summary: _summary,
        fromDay: _day(_range.start),
        toDay: _day(_range.end),
        printedAt: DateTime.now(),
        ar: ar,
      );
      await ref.read(printQueueProvider).enqueue(job);
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(ar ? 'تمت الطباعة' : 'Printed')));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareReport() async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final text = buildSalesReportText(
      identity: _identity,
      summary: _summary,
      fromDay: _day(_range.start),
      toDay: _day(_range.end),
      printedAt: DateTime.now(),
      ar: ar,
    );
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ar ? 'نُسخ التقرير' : 'Report copied')));
      }
    }
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
    // Same labels as the on-screen voucher; read before any await.
    final l = AppLocalizations.of(context)!;
    final labelExpiry = ar ? 'تاريخ الانتهاء' : 'Expiry';
    final labelReceiptNo = ar ? 'رقم العملية' : 'Receipt #';
    setState(() => _printing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
      final p = widget.recovered.product;
      final def = p.productDefinition;
      final t = def.template;
      final agentLogo = t.showAgentLogo ? await loadReceiptLogo(widget.recovered.agentLogoUrl) : null;
      final companyLogo = t.showCompanyLogo ? await loadReceiptLogo(widget.recovered.companyLogoUrl) : null;
      // CR-06: the reprint used to build ESC/POS only, so on a vendor-intent
      // terminal it threw "no printer" instead of reprinting. One job now covers
      // every transport.
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
        companyName: widget.recovered.companyName,
        categoryName: widget.recovered.categoryName ?? def.name,
        expiry: p.expiryDate,
        receiptNo: widget.recovered.receiptNo,
        labelSerial: l.posSerial,
        labelPin: l.posPin,
        labelExpiry: labelExpiry,
        labelReceiptNo: labelReceiptNo,
      );
      await ref.read(printQueueProvider).enqueue(job);
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
