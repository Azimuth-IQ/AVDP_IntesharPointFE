import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/print_operation.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

String _tr(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;

/// Operations screen: search the recorded voucher prints/sales by receipt number or
/// serial and inspect the operation (store, product, expiry, operator, timestamp).
/// HQ sees all stores; other roles are scoped server-side to their own store.
class PrintOperationsPage extends ConsumerStatefulWidget {
  const PrintOperationsPage({super.key});

  @override
  ConsumerState<PrintOperationsPage> createState() => _PrintOperationsPageState();
}

class _PrintOperationsPageState extends ConsumerState<PrintOperationsPage> {
  final _qCtrl = TextEditingController();
  List<PrintOperation>? _results;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final res = await repo.printOperations(q: _qCtrl.text.trim());
      if (mounted) {
        setState(() {
          _results = res;
          _loading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: _tr(context, 'العمليات', 'Operations'),
            title: _tr(context, 'عمليات الطباعة', 'Print operations'),
            subtitle: _tr(
                context,
                'ابحث برقم العملية أو السيريال لمراجعة عملية بيع',
                'Search by receipt number or serial to inspect a sale'),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qCtrl,
                    decoration: InputDecoration(
                      labelText: _tr(context, 'رقم العملية أو السيريال',
                          'Receipt # or serial'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _loading ? null : _search,
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(_tr(context, 'بحث', 'Search')),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _search);
    final r = _results;
    if (r == null || r.isEmpty) {
      return EmptyState(
        message: _tr(
            context,
            'لا توجد عمليات طباعة — جرّب رقم عملية أو سيريال آخر',
            'No print operations — try a different receipt number or serial'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
      itemCount: r.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _OpCard(op: r[i]),
    );
  }
}

class _OpCard extends StatelessWidget {
  final PrintOperation op;
  const _OpCard({required this.op});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget kv(String k, String v, {bool mono = false}) => Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 92,
                child: Text(k,
                    style: IntesharType.sans(12, color: cs.onSurfaceVariant))),
            Expanded(
              child: mono
                  ? monoText(v, size: 12.5, color: cs.onSurface)
                  : Text(v,
                      style: IntesharType.sans(12.5,
                          color: cs.onSurface, w: FontWeight.w600)),
            ),
          ]),
        );

    return InkCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('#${op.receiptNo}',
                  style: IntesharType.sans(16,
                      color: IntesharColors.saffronDeep, w: FontWeight.w900)),
            ),
            if (op.productName.isNotEmpty)
              Text(op.productName,
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 6),
          kv(_tr(context, 'السيريال', 'Serial'), op.serialNumber, mono: true),
          if (op.storeName.isNotEmpty)
            kv(_tr(context, 'المتجر', 'Store'), op.storeName),
          if ((op.expiryDate ?? '').isNotEmpty)
            kv(_tr(context, 'الانتهاء', 'Expiry'), op.expiryDate!, mono: true),
          if ((op.operatorPhone ?? '').isNotEmpty)
            kv(_tr(context, 'المشغّل', 'Operator'), op.operatorPhone!, mono: true),
          if (op.createdAt.isNotEmpty)
            kv(_tr(context, 'التاريخ', 'Date'),
                op.createdAt.replaceFirst('T', ' ').split('.').first),
        ],
      ),
    );
  }
}
