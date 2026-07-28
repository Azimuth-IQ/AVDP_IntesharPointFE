import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// B-056 — التحويل: the agent's balance-transfer page (AGENT1 + AGENT2).
/// Shows the available balance, sends credit to a DIRECT child (server-enforced
/// rule) with the B-040 confirm dialog, and lists the grant-ledger history.
/// B-092: which slice of the direct children the destination picker is showing.
enum _DestKind { subAgents, pos }

class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TS {
  final bool ar;
  const _TS(this.ar);
  factory _TS.of(BuildContext c) =>
      _TS(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String a) => ar ? a : en;
  String get eyebrow => p('BALANCE', 'الرصيد');
  String get title => p('Transfers', 'التحويل');
  String get subtitle =>
      p('Send balance to your accounts and track every transfer',
        'إرسال الرصيد إلى حساباتك ومتابعة كل التحويلات');
  String get available => p('Available balance', 'الرصيد المتاح');
  String get newTransfer => p('New transfer', 'تحويل جديد');
  String get to => p('To', 'إلى');
  String get amount => p('Amount (IQD)', 'المبلغ (د.ع)');
  String get send => p('Send', 'إرسال');
  String confirmSend(String amount, String to) =>
      p('Confirm: send \$amount to \$to', 'تأكيد: إرسال \$amount إلى \$to');
  String get cancel => p('Cancel', 'إلغاء');
  String get confirmTitle => p('Confirm transfer', 'تأكيد التحويل');
  String confirmBody(String amount, String dest) => p(
      'You are about to transfer $amount to "$dest". This cannot be undone.',
      'سيتم تحويل $amount إلى "$dest". لا يمكن التراجع عن هذا الإجراء.');
  String get sent => p('Balance transferred', 'تم تحويل الرصيد');
  String get history => p('Transfer history', 'سجل التحويلات');
  String get empty => p('No transfers yet.', 'لا توجد تحويلات بعد.');
  String get noChildren =>
      p('No accounts under you to transfer to yet.', 'لا توجد حسابات تابعة للتحويل إليها بعد.');
  String get invalidAmount => p('Enter a valid amount', 'أدخل مبلغاً صحيحاً');
  String insufficient(String available) => p(
      'Insufficient balance (available $available)',
      'الرصيد غير كافٍ (المتاح $available)');
  String toName(String n) => p('To $n', 'إلى $n');
  String fromName(String n) => p('From $n', 'من $n');
}

class _TransfersPageState extends ConsumerState<TransfersPage> {
  AgentBalance? _balance;
  List<GrantRow> _grants = const [];
  List<EntitySummaryRow> _children = const [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  String get _myId =>
      (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)
          ?.entity
          .id ??
      '';

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
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        PricingRepository(api).balance(),
        PricingRepository(api).grants(),
        _allChildren(api),
      ]);
      final grants = (results[1] as List<GrantRow>).toList()
        ..sort((a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'));
      if (!mounted) return;
      setState(() {
        _balance = results[0] as AgentBalance;
        _grants = grants;
        _children = results[2] as List<EntitySummaryRow>;
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

  /// EVERY direct child, paged to exhaustion. The server clamps `size` to 200 and
  /// sorts rows type-ascending, so an agent's own POS points (STORE sorts last) fell
  /// off the first page entirely — which is why they appeared to be missing (B-092).
  Future<List<EntitySummaryRow>> _allChildren(dynamic api) async {
    final out = <EntitySummaryRow>[];
    var page = 0;
    while (true) {
      final res = await EntityRepository(api).children(_myId, page: page, size: 200);
      out.addAll(res.items);
      if (!res.hasMore || page > 50) break; // guard: never loop forever
      page++;
    }
    return out;
  }

  /// B-105: ONE dialog. Recipient type, search, the list itself, the amount and
  /// the before→after readout are all present at once.
  ///
  /// The old flow was three dialogs and ~5 taps: new-transfer → tap "إلى" → a
  /// second picker dialog → pick → amount → send → a third confirm dialog. Worse,
  /// the "إلى" field rendered as a read-only InputDecorator that did not look
  /// tappable, so an agent's own POS points — reachable since B-092 — were
  /// effectively invisible, and the customer reported transfers as "sub-agents
  /// only". Their own reference system puts the same choice on a single form
  /// (a الوكلاء ⁄ ادارة نقاط البيع radio + dropdown + amount), so this matches it.
  ///
  /// The B-040 money-movement confirmation is kept, but folded in: Send arms, and
  /// a second press commits. Money still never moves on one mis-tap.
  Future<void> _newTransferDialog(_TS s) async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.noChildren)));
      return;
    }
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final posCount = _children.where((e) => e.type == EntityType.STORE).length;
    final agentCount = _children.length - posCount;

    // Open on whichever list the agent actually has; agents first when it has both.
    var kind = agentCount > 0 ? _DestKind.subAgents : _DestKind.pos;
    EntitySummaryRow? dest;
    var query = '';
    var armed = false; // second press commits (B-040 confirmation, inlined)
    final amountCtrl = TextEditingController();
    String? fieldError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final cs = Theme.of(ctx).colorScheme;
        final q = query.trim().toLowerCase();
        final byKind = kind == _DestKind.pos
            ? _children.where((e) => e.type == EntityType.STORE).toList()
            : _children.where((e) => e.type != EntityType.STORE).toList();
        final rows = q.isEmpty
            ? byKind
            : byKind.where((e) => e.label.toLowerCase().contains(q)).toList();
        final avail = _balance?.available ?? 0;
        final amt = parseAmount(amountCtrl.text) ?? 0;
        final after = avail - amt;
        final ready = dest != null && amt > 0 && after >= 0;

        void disarm() => armed = false;

        return AlertDialog(
          title: Text(s.newTransfer),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Recipient type — the agent's OWN POS points are a first-class
              // choice here, not something hidden behind another dialog.
              SegmentedButton<_DestKind>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                      value: _DestKind.subAgents,
                      label: Text(ar ? 'الوكلاء ($agentCount)' : 'Agents ($agentCount)')),
                  ButtonSegment(
                      value: _DestKind.pos,
                      label: Text(ar ? 'نقاط البيع ($posCount)' : 'POS ($posCount)')),
                ],
                selected: {kind},
                onSelectionChanged: (sel) => setD(() {
                  kind = sel.first;
                  dest = null; // never carry a selection across lists
                  disarm();
                }),
              ),
              const SizedBox(height: 8),
              if (byKind.length > 6)
                TextField(
                  decoration: InputDecoration(
                    hintText: ar ? 'بحث بالاسم…' : 'Search by name…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setD(() { query = v; disarm(); }),
                ),
              if (byKind.length > 6) const SizedBox(height: 8),
              // The list itself — visible, not behind a tap.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 210),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(IntesharRadii.md),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                              child: Text(ar ? 'لا توجد حسابات مطابقة' : 'No matching accounts',
                                  style: IntesharType.sans(12.5, color: cs.onSurfaceVariant))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final selected = dest?.id == r.id;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              selectedTileColor: cs.primary.withValues(alpha: 0.10),
                              leading: Icon(
                                  r.type == EntityType.STORE
                                      ? Icons.storefront_outlined
                                      : Icons.apartment_outlined,
                                  size: 18,
                                  color: selected ? cs.onSurface : cs.onSurfaceVariant),
                              title: Text(r.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: IntesharType.sans(13,
                                      color: cs.onSurface,
                                      w: selected ? FontWeight.w800 : FontWeight.w500)),
                              trailing: selected
                                  ? Icon(Icons.check_circle, size: 18, color: cs.primary)
                                  : null,
                              onTap: () => setD(() { dest = r; disarm(); }),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsInputFormatter()],
                decoration: InputDecoration(
                  labelText: s.amount,
                  isDense: true,
                  errorText: fieldError,
                ),
                onChanged: (_) => setD(() { fieldError = null; disarm(); }),
              ),
              const SizedBox(height: 12),
              // Live before → after so the sender sees the impact at decision time.
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(ar ? 'الرصيد المتاح' : 'Available',
                    style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                Text(Formatters.iqd(avail.round()),
                    style: IntesharType.mono(12.5, color: cs.onSurface)),
              ]),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(ar ? 'بعد التحويل' : 'After transfer',
                    style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                Text(Formatters.iqd(after.round()),
                    style: IntesharType.mono(12.5,
                        w: FontWeight.w700,
                        color: after < 0 ? cs.error : cs.onSurface)),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(
              onPressed: !ready
                  ? null
                  : () {
                      final n = parseAmount(amountCtrl.text);
                      if (n == null || n <= 0) {
                        setD(() => fieldError = s.invalidAmount);
                        return;
                      }
                      if (n > avail) {
                        setD(() =>
                            fieldError = s.insufficient(Formatters.iqd(avail.round())));
                        return;
                      }
                      // Arm first, commit second — the confirmation, without a
                      // third dialog.
                      if (!armed) {
                        setD(() => armed = true);
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
              child: Text(armed && ready
                  ? s.confirmSend(Formatters.iqd(amt.round()), dest!.label)
                  : s.send),
            ),
          ],
        );
      }),
    );

    final amount = parseAmount(amountCtrl.text);
    final target = dest;
    if (ok != true || amount == null || amount <= 0 || target == null) return;
    if (!mounted) return;

    // B-040: explicit confirmation before money moves.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmTitle),
        content: Text(
            s.confirmBody(Formatters.iqd(amount.round()), target.label)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(s.send)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PricingRepository(ref.read(apiClientProvider))
          .grant(destId: target.id, amount: amount);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.sent)));
      await _load();
    } catch (e) {
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _TS.of(context);
    return MaxWidthBox(
      maxWidth: 760,
      child: Column(children: [
        PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle),
        Expanded(child: _body(s)),
      ]),
    );
  }

  Widget _body(_TS s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 28),
        children: [
          // Balance card
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              color: context.tones.brand,
              borderRadius: BorderRadius.circular(IntesharRadii.lg),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.available,
                  style: IntesharType.overline(
                      color: IntesharColors.ink.withValues(alpha: 0.7))),
              const SizedBox(height: 4),
              Text(
                Formatters.iqd((_balance?.available ?? 0).round()),
                style: const TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: IntesharColors.ink,
                  height: 1,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _newTransferDialog(s),
              icon: const Icon(Icons.north_east, size: 18),
              label: Text(s.newTransfer),
            ),
          ),
          const SizedBox(height: 20),
          SectionLabel(s.history),
          const SizedBox(height: 8),
          if (_grants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: Text(s.empty,
                      style:
                          IntesharType.sans(14, color: cs.onSurfaceVariant))),
            )
          else
            for (final g in _grants) _grantCard(s, g, cs),
        ],
      ),
    );
  }

  Widget _grantCard(_TS s, GrantRow g, ColorScheme cs) {
    final sent = g.sourceId == _myId;
    final other = sent
        ? (g.destName.isNotEmpty ? g.destName : g.destId)
        : (g.sourceName.isNotEmpty ? g.sourceName : g.sourceId);
    final tint = sent ? cs.error : IntesharColors.sage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(sent ? Icons.north_east : Icons.south_west,
                size: 17, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sent ? s.toName(other) : s.fromName(other),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(13.5,
                      color: cs.onSurface, w: FontWeight.w600)),
              const SizedBox(height: 1),
              Text('${g.date} ${g.time}',
                  style: IntesharType.mono(11, color: cs.onSurfaceVariant)),
            ]),
          ),
          Text('${sent ? '−' : '+'}${Formatters.iqd(g.amount.round())}',
              style: IntesharType.mono(13.5, color: tint)),
        ]),
      ),
    );
  }
}
