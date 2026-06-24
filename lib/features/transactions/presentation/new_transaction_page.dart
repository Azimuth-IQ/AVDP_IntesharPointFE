import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

class NewTransactionPage extends ConsumerStatefulWidget {
  const NewTransactionPage({super.key});

  @override
  ConsumerState<NewTransactionPage> createState() => _NewTransactionPageState();
}

class _NewTransactionPageState extends ConsumerState<NewTransactionPage> {
  Entity? _currentEntity;
  List<Entity> _children = [];
  List<ProductDefinition> _defs = [];

  Entity? _destination;
  final List<_LineItem> _lines = [];

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  AppTransaction? _result;

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

      _currentEntity = auth.entity;
      final api = ref.read(apiClientProvider);
      final entityRepo = EntityRepository(api);
      final defRepo = DefinitionRepository(api);

      final children = await entityRepo.readDirectChildren(_currentEntity!.id);
      final defs = await defRepo.readAll();

      if (mounted) {
        setState(() {
          _children = children;
          _defs = defs;
          if (children.isNotEmpty) _destination = children.first;
          if (defs.isNotEmpty && _lines.isEmpty) {
            _lines.add(_LineItem(def: defs.first, amount: 1));
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_destination == null || _lines.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final txRepo = TransactionRepository(api);
      final now = DateTime.now();

      final lines = _lines
          .where((l) => l.amount > 0)
          .map(
            (l) => TransactionLine(
              id: 'line_${DateTime.now().millisecondsSinceEpoch}',
              sku: l.def.sku,
              amount: l.amount.toString(),
              price: l.price ?? l.def.defaultPrice,
              lineTotal: _lineTotal(l),
            ),
          )
          .toList();

      if (lines.isEmpty) throw Exception('Add at least one line item');

      final tx = AppTransaction(
        date: Formatters.date(now),
        time: Formatters.time(now),
        sourceId: _currentEntity!.id,
        destinationId: _destination!.id,
        lines: lines,
      );

      AppTransaction created = await txRepo.create(tx);

      int polls = 0;
      while (polls < 15 &&
          created.status != TransactionStatus.COMPLETED &&
          created.status != TransactionStatus.FAILED) {
        await Future.delayed(const Duration(seconds: 1));
        created = await txRepo.read(created.id);
        polls++;
      }

      if (mounted) {
        setState(() {
          _result = created;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  String _lineTotal(_LineItem l) {
    final price = int.tryParse(l.price ?? l.def.defaultPrice) ?? 0;
    return (price * l.amount).toString();
  }

  int get _grandTotal => _lines.fold(0, (s, l) => s + (int.tryParse(_lineTotal(l)) ?? 0));
  int get _totalUnits => _lines.fold(0, (s, l) => s + l.amount);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Text(l.newTxnTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _result != null
              ? _ResultView(result: _result!)
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return MaxWidthBox(
      maxWidth: 900,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.newTxnIssueStock,
              style: IntesharType.display(32, color: cs.onSurface, w: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              l.newTxnIssueStockHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            // Source/Destination paired cards
            _RouteRow(
              currentEntity: _currentEntity!,
              children: _children,
              destination: _destination,
              onDestinationChanged: (v) => setState(() => _destination = v),
            ),
            const SizedBox(height: 10),
            _DeliveryHint(destination: _destination),
            const SizedBox(height: 24),
            // Lines header
            SectionLabel(
              l.newTxnManifestLines,
              trailing: TextButton.icon(
                onPressed: _defs.isEmpty
                    ? null
                    : () => setState(() => _lines.add(_LineItem(def: _defs.first, amount: 1))),
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.newTxnAddLine),
              ),
            ),
            ..._lines.asMap().entries.map((entry) {
              final i = entry.key;
              final line = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _LineCard(
                  index: i,
                  line: line,
                  defs: _defs,
                  total: _lineTotal(line),
                  onChanged: (l) => setState(() => _lines[i] = l),
                  onRemove: _lines.length > 1 ? () => setState(() => _lines.removeAt(i)) : null,
                ),
              );
            }),
            const SizedBox(height: 18),
            // Grand total bar — brand yellow band.
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                color: IntesharColors.saffron,
                borderRadius: BorderRadius.circular(IntesharRadii.lg),
              ),
              child: Row(
                children: [
                  Text(
                    l.newTxnGrandTotal,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 14,
                      color: IntesharColors.ink.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l.newTxnUnitsCount(_totalUnits),
                    style: IntesharType.mono(12, color: IntesharColors.ink.withValues(alpha: 0.65)),
                  ),
                  const Spacer(),
                  Text(
                    Formatters.iqd(_grandTotal),
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: IntesharColors.ink,
                      letterSpacing: -0.8,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(IntesharRadii.sm),
                  border: Border.all(color: cs.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: cs.error),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: TextStyle(color: cs.onSurface))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            BrandCTAButton(
              label: _submitting ? l.newTxnPosting : l.newTxnSubmit,
              leading: _submitting ? null : Icons.send,
              loading: _submitting,
              onPressed: (_submitting || _destination == null || _lines.isEmpty) ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Route row ───────────────────────────────────────────────────────────────

class _RouteRow extends StatelessWidget {
  final Entity currentEntity;
  final List<Entity> children;
  final Entity? destination;
  final ValueChanged<Entity?> onDestinationChanged;
  const _RouteRow({
    required this.currentEntity,
    required this.children,
    required this.destination,
    required this.onDestinationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (ctx, c) {
        final stacked = c.maxWidth < 620;
        final source = _RouteEndpoint(
          eyebrow: l.newTxnSource,
          accent: cs.error,
          name: currentEntity.meta.name,
          subtitle: currentEntity.id,
          badge: RoleBadge(type: currentEntity.type),
        );
        final dest = _DestPicker(
          children: children,
          destination: destination,
          onChanged: onDestinationChanged,
        );
        if (stacked) {
          return Column(
            children: [
              source,
              const SizedBox(height: 10),
              Center(child: Icon(Icons.south, color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              dest,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: source),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.east, color: cs.onSurfaceVariant),
            ),
            Expanded(child: dest),
          ],
        );
      },
    );
  }
}

class _RouteEndpoint extends StatelessWidget {
  final String eyebrow;
  final Color accent;
  final String name;
  final String subtitle;
  final Widget? badge;
  final Widget? child;
  const _RouteEndpoint({
    required this.eyebrow,
    required this.accent,
    required this.name,
    required this.subtitle,
    this.badge,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      ruleColor: accent,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(eyebrow.toUpperCase(), style: IntesharType.overline(color: accent)),
              const Spacer(),
              ?badge,
            ],
          ),
          const SizedBox(height: 12),
          if (child != null) child! else ...[
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IntesharType.sans(20, color: cs.onSurface, w: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            SelectableText(
              subtitle,
              style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _DestPicker extends StatelessWidget {
  final List<Entity> children;
  final Entity? destination;
  final ValueChanged<Entity?> onChanged;
  const _DestPicker({required this.children, required this.destination, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (children.isEmpty) {
      return _RouteEndpoint(
        eyebrow: l.newTxnDestination,
        accent: cs.outline,
        name: l.newTxnNoChildren,
        subtitle: l.newTxnNoChildrenHint,
      );
    }
    final d = destination ?? children.first;
    return _RouteEndpoint(
      eyebrow: l.newTxnDestination,
      accent: IntesharColors.sage,
      name: d.meta.name,
      subtitle: d.id,
      badge: RoleBadge(type: d.type),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Entity>(
              initialValue: d,
              isExpanded: true,
              icon: const Icon(Icons.unfold_more, size: 18),
              decoration: InputDecoration(
                labelText: l.newTxnChooseEntity,
              ),
              items: children
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text('${e.meta.name} (${e.type.label})'),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            SelectableText(
              d.id,
              style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Line card ───────────────────────────────────────────────────────────────

class _LineCard extends StatelessWidget {
  final int index;
  final _LineItem line;
  final List<ProductDefinition> defs;
  final String total;
  final ValueChanged<_LineItem> onChanged;
  final VoidCallback? onRemove;
  const _LineCard({
    required this.index,
    required this.line,
    required this.defs,
    required this.total,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      padding: const EdgeInsets.all(14),
      ruleColor: cs.outline,
      child: Column(
        children: [
          Row(
            children: [
              // Index tile
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(IntesharRadii.xs),
                  border: Border.all(color: cs.outline),
                ),
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: IntesharType.mono(12, color: cs.onSurfaceVariant, w: FontWeight.w700, letterSpacing: 0.4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<ProductDefinition>(
                  initialValue: line.def,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.newTxnProduct, isDense: true),
                  items: defs
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('${d.name} (${d.sku})'),
                          ))
                      .toList(),
                  onChanged: (d) {
                    if (d != null) onChanged(line.copyWith(def: d));
                  },
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 110,
                child: TextFormField(
                  initialValue: line.amount.toString(),
                  keyboardType: TextInputType.number,
                  style: IntesharType.mono(14, color: cs.onSurface),
                  decoration: InputDecoration(labelText: l.newTxnQty, isDense: true),
                  onChanged: (v) => onChanged(line.copyWith(amount: int.tryParse(v) ?? 1)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: line.price ?? line.def.defaultPrice,
                  keyboardType: TextInputType.number,
                  style: IntesharType.mono(14, color: cs.onSurface),
                  decoration: InputDecoration(labelText: l.newTxnUnitPrice, isDense: true),
                  onChanged: (v) => onChanged(line.copyWith(price: v)),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(IntesharRadii.xs),
                  border: Border.all(color: cs.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(l.newTxnLineTotal, style: IntesharType.overline(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.iqd(total),
                      style: IntesharType.mono(13, color: cs.onSurface, w: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Result view ─────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final AppTransaction result;
  const _ResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final success = result.status == TransactionStatus.COMPLETED;
    final tone = success ? IntesharColors.sage : cs.error;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: InkCard(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(success ? Icons.check : Icons.close, size: 32, color: tone),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  success ? l.newTxnPostedToLedger : l.newTxnDeclined,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    fontSize: 22,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    success ? l.newTxnResultPosted : l.newTxnResultDeclined,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 12,
                      color: tone,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    l.newTxnRef(result.id),
                    style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.2),
                  ),
                ),
                if (result.processMessage.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(IntesharRadii.md),
                      border: Border.all(color: cs.outline),
                    ),
                    child: Text(
                      result.processMessage,
                      style: IntesharType.mono(12, color: cs.onSurface, letterSpacing: 0).copyWith(height: 1.5),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                BrandCTAButton(
                  label: l.newTxnReturnToTransactions,
                  trailing: Icons.arrow_forward,
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Delivery (geo-lock) hint ─────────────────────────────────────────────────

class _DeliveryHint extends StatelessWidget {
  final Entity? destination;
  const _DeliveryHint({required this.destination});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final d = destination;
    if (d == null) return const SizedBox.shrink();
    final loc = Localizations.localeOf(context).languageCode;
    final govs = d.meta.governorates;
    final coverage = govs.isEmpty
        ? l.newTxnNoRegionRestriction
        : govs.map((c) => governorateLabel(c, loc)).join('، ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.public, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.newTxnDeliverableHint(coverage),
              style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItem {
  final ProductDefinition def;
  final int amount;
  final String? price;

  const _LineItem({required this.def, required this.amount, this.price});

  _LineItem copyWith({ProductDefinition? def, int? amount, String? price}) =>
      _LineItem(def: def ?? this.def, amount: amount ?? this.amount, price: price ?? this.price);
}
