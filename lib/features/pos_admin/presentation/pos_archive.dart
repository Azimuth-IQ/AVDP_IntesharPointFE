import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/files/report_export.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/entities/presentation/confirm_code_dialog.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/archived_pos.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';

bool _isAr(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';
String _t(BuildContext c, String ar, String en) => _isAr(c) ? ar : en;

/// Arabic counts days by band, not by a single plural form. Getting this wrong
/// reads as broken text to a native speaker: "3 يوم" is what a machine writes.
///   1 → يوم واحد · 2 → يومان · 3–10 → N أيام · 11+ → N يوماً
String daysLeftLabel(BuildContext context, int days) {
  if (!_isAr(context)) {
    return days == 1 ? '1 day left' : '$days days left';
  }
  if (days == 1) return 'يتبقى يوم واحد';
  if (days == 2) return 'يتبقى يومان';
  if (days >= 3 && days <= 10) return 'يتبقى $days أيام';
  return 'يتبقى $days يوماً';
}

/// Writes a shop's whole record to a spreadsheet: identity and balances, then
/// every sale, then every transfer received.
///
/// One file rather than three, because this is the operator's last chance to keep
/// the shop's history — a set of separate downloads is how one of them is missed.
/// Returns the saved name, or null if nothing was written.
Future<String?> savePosDataFile(BuildContext context, PosDataExport data) async {
  final ar = _isAr(context);
  final rows = <List<String>>[];

  rows.add([ar ? 'المبيعات' : 'SALES', '', '', '', '', '']);
  rows.add([
    ar ? 'التاريخ' : 'Date',
    ar ? 'الفئة' : 'Product',
    ar ? 'الرمز' : 'SKU',
    ar ? 'السعر' : 'Price',
    ar ? 'رقم الوصل' : 'Receipt',
    ar ? 'طُبع' : 'Printed',
  ]);
  for (final s in data.sales) {
    rows.add([
      (s['at'] ?? '').toString(),
      (s['productName'] ?? '').toString(),
      (s['sku'] ?? '').toString(),
      Formatters.money((s['soldPrice'] as num?)?.toDouble() ?? 0),
      (s['receiptNo'] ?? '').toString(),
      (s['printed'] == true) ? (ar ? 'نعم' : 'Yes') : (ar ? 'لا' : 'No'),
    ]);
  }

  rows.add(['', '', '', '', '', '']);
  rows.add([ar ? 'التحويلات المستلمة' : 'TRANSFERS RECEIVED', '', '', '', '', '']);
  rows.add([
    ar ? 'التاريخ' : 'Date',
    ar ? 'الوقت' : 'Time',
    ar ? 'من' : 'From',
    ar ? 'المبلغ' : 'Amount',
    '',
    '',
  ]);
  for (final g in data.grants) {
    rows.add([
      (g['date'] ?? '').toString(),
      (g['time'] ?? '').toString(),
      (g['sourceName'] ?? g['sourceId'] ?? '').toString(),
      Formatters.money((g['amount'] as num?)?.toDouble() ?? 0),
      '',
      '',
    ]);
  }

  final safeName = data.name.replaceAll(RegExp(r'[^\w؀-ۿ-]+'), '-');
  return exportRowsToXlsx(
    fileName: 'pos-$safeName-${DateTime.now().toIso8601String().substring(0, 10)}',
    sheetName: ar ? 'بيانات نقطة البيع' : 'POS data',
    headers: const ['', '', '', '', '', ''],
    rows: rows,
    // B-098: without provenance, two exports are indistinguishable files.
    provenance: [
      (ar ? 'نقطة البيع' : 'Point of sale', data.name),
      if ((data.ownerName ?? '').isNotEmpty) (ar ? 'المالك' : 'Owner', data.ownerName!),
      if ((data.hostName ?? '').isNotEmpty) (ar ? 'الوكيل' : 'Agent', data.hostName!),
      if ((data.operatorPhone ?? '').isNotEmpty)
        (ar ? 'هاتف المشغّل' : 'Operator phone', data.operatorPhone!),
      if ((data.address ?? '').isNotEmpty) (ar ? 'العنوان' : 'Address', data.address!),
      (ar ? 'الرصيد المتاح' : 'Balance available', Formatters.money(data.balanceAvailable)),
      (ar ? 'إجمالي المستلم' : 'Total received', Formatters.money(data.balanceReceived)),
      (ar ? 'إجمالي المصروف' : 'Total spent', Formatters.money(data.balanceSpent)),
      (ar ? 'عدد المبيعات' : 'Sales count', '${data.sales.length}'),
      (ar ? 'تاريخ التصدير' : 'Generated', DateTime.now().toString().substring(0, 19)),
    ],
  );
}

/// Confirms archiving a shop, with the data download offered FIRST.
///
/// Archiving starts a countdown to permanent deletion, so the download is put in
/// front of the operator at the moment it matters rather than left somewhere they
/// would have to know about. Returns the authenticator code to archive with, or
/// null if they backed out.
Future<String?> showArchivePosDialog(
  BuildContext context,
  WidgetRef ref, {
  required String storeId,
  required String storeName,
  required int retentionDays,
}) async {
  final repo = PosAdminRepository(ref.read(apiClientProvider));
  var downloaded = false;

  final proceed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return StatefulBuilder(builder: (ctx, setLocal) {
        var busy = false;
        return StatefulBuilder(builder: (ctx, setInner) {
          Future<void> download() async {
            setInner(() => busy = true);
            try {
              final data = await repo.exportPos(storeId);
              if (!ctx.mounted) return;
              final saved = await savePosDataFile(ctx, data);
              if (saved != null) {
                downloaded = true;
                setInner(() {});
              }
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(friendlyError(e, ctx))));
              }
            } finally {
              if (ctx.mounted) setInner(() => busy = false);
            }
          }

          return AlertDialog(
            icon: Icon(Icons.inventory_2_outlined, color: cs.error),
            title: Text(_t(ctx, 'أرشفة نقطة البيع', 'Archive point of sale')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t(
                  ctx,
                  'سيتم إيقاف "$storeName" فوراً ونقلها إلى الأرشيف. تُحفظ بياناتها '
                      '$retentionDays يوماً ثم يمكن حذفها نهائياً.',
                  '"$storeName" stops trading immediately and moves to the archive. '
                      'Its data is kept for $retentionDays days, after which it can '
                      'be deleted permanently.',
                )),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: downloaded ? cs.primaryContainer : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(
                        downloaded
                            ? Icons.check_circle_outline
                            : Icons.download_outlined,
                        size: 18,
                        color: downloaded ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        downloaded
                            ? _t(ctx, 'تم حفظ نسخة من البيانات.',
                                'A copy of the data has been saved.')
                            : _t(ctx, 'نزّل سجل المبيعات والتحويلات قبل الأرشفة.',
                                'Download the sales and transfer records first.'),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('archiveDownloadData'),
                    onPressed: busy ? null : download,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_outlined, size: 16),
                    label: Text(downloaded
                        ? _t(ctx, 'تنزيل مرة أخرى', 'Download again')
                        : _t(ctx, 'تنزيل بيانات نقطة البيع', 'Download POS data')),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_t(ctx, 'إلغاء', 'Cancel')),
              ),
              FilledButton(
                key: const Key('archiveConfirm'),
                style: FilledButton.styleFrom(backgroundColor: cs.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_t(ctx, 'أرشفة', 'Archive')),
              ),
            ],
          );
        });
      });
    },
  );

  if (proceed != true || !context.mounted) return null;
  return showConfirmCodeDialog(
    context,
    title: _t(context, 'تأكيد الأرشفة', 'Confirm archiving'),
    warning: _t(
      context,
      'سيتم إيقاف "$storeName" ونقلها إلى الأرشيف.',
      '"$storeName" will stop trading and move to the archive.',
    ),
  );
}

/// The archive: retired shops, the days each has left, and — once the window has
/// passed — the button that removes it for good.
class PosArchiveView extends ConsumerStatefulWidget {
  final String? entityId;
  const PosArchiveView({super.key, this.entityId});

  @override
  ConsumerState<PosArchiveView> createState() => _PosArchiveViewState();
}

class _PosArchiveViewState extends ConsumerState<PosArchiveView> {
  List<ArchivedPos>? _rows;
  Object? _error;
  bool _loading = true;
  final Set<String> _busy = {};

  PosAdminRepository get _repo => PosAdminRepository(ref.read(apiClientProvider));

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
      final rows = await _repo.archived(entityId: widget.entityId);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _download(ArchivedPos row) async {
    setState(() => _busy.add(row.id));
    try {
      final data = await _repo.exportPos(row.id);
      if (!mounted) return;
      final saved = await savePosDataFile(context, data);
      if (saved != null && mounted) {
        _snack(_t(context, 'تم حفظ البيانات', 'Data saved'));
      }
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _busy.remove(row.id));
    }
  }

  /// Prefer the server's words — "it can be deleted permanently in 12 days" is
  /// the answer the operator needs.
  void _report(Object e) {
    if (!mounted) return;
    _snack(serverReason(e) ?? friendlyError(e, context));
  }

  /// Brings a shop back. The host's free points are fetched FIRST and shown, so
  /// the one way this can fail is visible before the operator commits rather than
  /// arriving as an error afterwards.
  Future<void> _restore(ArchivedPos row) async {
    setState(() => _busy.add(row.id));
    int? freePoints;
    try {
      if ((row.hostId ?? '').isNotEmpty) {
        freePoints = (await _repo.quota(entityId: row.hostId)).available;
      }
    } catch (_) {
      // Not fatal — the server still enforces it; we just cannot preview it.
    } finally {
      if (mounted) setState(() => _busy.remove(row.id));
    }
    if (!mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final blocked = freePoints != null && freePoints <= 0;
        return AlertDialog(
          icon: Icon(Icons.restore_outlined, color: cs.primary),
          title: Text(_t(ctx, 'إعادة تفعيل نقطة البيع', 'Restore point of sale')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t(
                ctx,
                'ستعود "${row.name}" للعمل فوراً، ويستطيع المشغّل '
                    '${row.operatorPhone ?? ''} تسجيل الدخول بنفس البيانات. '
                    'رصيدها وسجلها كما هما.',
                '"${row.name}" starts trading again and its operator '
                    '${row.operatorPhone ?? ''} can sign in with the same '
                    'credentials. Its balance and history are unchanged.',
              )),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: blocked ? cs.errorContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(blocked ? Icons.block : Icons.confirmation_number_outlined,
                      size: 18,
                      color: blocked ? cs.onErrorContainer : cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      freePoints == null
                          ? _t(ctx, 'ستستهلك نقطة بيع واحدة من ${row.hostName ?? ''}.',
                              'This uses one POS point from ${row.hostName ?? ''}.')
                          : blocked
                              ? _t(
                                  ctx,
                                  'لا توجد نقاط بيع متاحة لدى ${row.hostName ?? ''}. '
                                      'حرّر نقطة أو اطلب المزيد من الإدارة.',
                                  'No POS points free at ${row.hostName ?? ''}. '
                                      'Free one or ask headquarters for more.')
                              : _t(
                                  ctx,
                                  'ستستهلك نقطة واحدة من ${row.hostName ?? ''} '
                                      '(المتاح $freePoints).',
                                  'Uses one point from ${row.hostName ?? ''} '
                                      '($freePoints free).'),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_t(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: blocked ? null : () => Navigator.pop(ctx, true),
              child: Text(_t(ctx, 'إعادة تفعيل', 'Restore')),
            ),
          ],
        );
      },
    );
    if (proceed != true || !mounted) return;

    final code = await showConfirmCodeDialog(
      context,
      title: _t(context, 'تأكيد إعادة التفعيل', 'Confirm restore'),
      warning: _t(
        context,
        'إعادة التفعيل تُعيد تشغيل حساب الدخول والرصيد لـ "${row.name}".',
        'Restoring re-enables the login and balance for "${row.name}".',
      ),
      confirmLabel: _t(context, 'إعادة تفعيل', 'Restore'),
      destructive: false,
    );
    if (code == null || !mounted) return;

    setState(() => _busy.add(row.id));
    try {
      await _repo.restore(entityId: row.id, totp: code);
      if (!mounted) return;
      _snack(_t(context, 'تمت إعادة التفعيل', 'Restored'));
      await _load();
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _busy.remove(row.id));
    }
  }

  Future<void> _purge(ArchivedPos row) async {
    final code = await showConfirmCodeDialog(
      context,
      title: _t(context, 'حذف نهائي', 'Delete permanently'),
      warning: _t(
        context,
        'سيتم حذف "${row.name}" وكل بياناتها نهائياً. لا يمكن التراجع.',
        'This permanently deletes "${row.name}" and all of its data. '
            'It cannot be undone.',
      ),
    );
    if (code == null || !mounted) return;
    setState(() => _busy.add(row.id));
    try {
      await _repo.purge(entityId: row.id, totp: code);
      if (!mounted) return;
      _snack(_t(context, 'تم الحذف نهائياً', 'Deleted permanently'));
      await _load();
    } catch (e) {
      _report(e);
    } finally {
      if (mounted) setState(() => _busy.remove(row.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows == null) {
      return const Center(child: Padding(
          padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text(friendlyError(_error, context), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _load, child: Text(_t(context, 'إعادة المحاولة', 'Try again'))),
        ]),
      );
    }
    final rows = _rows ?? const <ArchivedPos>[];
    if (rows.isEmpty) {
      return EmptyState(
        message: _t(context, 'لا توجد نقاط بيع مؤرشفة.',
            'No archived points of sale.'),
        actionLabel: _t(context, 'تحديث', 'Refresh'),
        onAction: _load,
      );
    }
    return PosArchiveList(
      rows: rows,
      busyIds: _busy,
      onDownload: _download,
      onPurge: _purge,
      onRestore: _restore,
    );
  }
}

/// The archive rows with no I/O, so the states can be previewed and pumped.
class PosArchiveList extends StatelessWidget {
  final List<ArchivedPos> rows;
  final Set<String> busyIds;
  final ValueChanged<ArchivedPos> onDownload;
  final ValueChanged<ArchivedPos> onPurge;
  final ValueChanged<ArchivedPos> onRestore;

  const PosArchiveList({
    super.key,
    required this.rows,
    required this.busyIds,
    required this.onDownload,
    required this.onPurge,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _row(context, rows[i]),
    );
  }

  Widget _row(BuildContext context, ArchivedPos row) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final busy = busyIds.contains(row.id);
    final subtitle = [
      if ((row.hostName ?? '').isNotEmpty)
        _t(context, 'تحت ${row.hostName}', 'under ${row.hostName}'),
      if ((row.governorate ?? '').isNotEmpty)
        governorateLabel(row.governorate!, locale),
      if ((row.operatorPhone ?? '').isNotEmpty) row.operatorPhone!,
    ].join(' · ');

    return InkCard(
      ruleColor: row.purgeable ? cs.error : cs.outline,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(row.name,
                style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w800)),
          ),
          // The countdown is the server's, never recomputed here — a local clock
          // would eventually offer a delete the server refuses.
          StampPill(
            label: row.purgeable
                ? _t(context, 'جاهزة للحذف', 'Ready to delete')
                : daysLeftLabel(context, row.daysRemaining),
            color: row.purgeable ? cs.error : cs.onSurfaceVariant,
            fontSize: 10,
          ),
        ]),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          // Restore leads: it is the reason most people open this screen, and it
          // is available for the whole retention window — the countdown is a
          // deadline for deletion, not for changing your mind.
          FilledButton.icon(
            key: Key('restore-${row.id}'),
            onPressed: busy ? null : () => onRestore(row),
            icon: const Icon(Icons.restore_outlined, size: 16),
            label: Text(_t(context, 'إعادة تفعيل', 'Restore')),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => onDownload(row),
            icon: busy
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 16),
            label: Text(_t(context, 'تنزيل البيانات', 'Download data')),
          ),
          FilledButton.icon(
            key: Key('purge-${row.id}'),
            style: FilledButton.styleFrom(
              backgroundColor: row.purgeable ? cs.error : cs.surfaceContainerHighest,
              foregroundColor: row.purgeable ? cs.onError : cs.onSurfaceVariant,
            ),
            // Disabled with the countdown visible above, rather than hidden: the
            // operator can see the action exists and when it becomes available.
            onPressed: (!row.purgeable || busy) ? null : () => onPurge(row),
            icon: const Icon(Icons.delete_forever_outlined, size: 16),
            label: Text(_t(context, 'حذف نهائي', 'Delete permanently')),
          ),
        ]),
      ]),
    );
  }
}
