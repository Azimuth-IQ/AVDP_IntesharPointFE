import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/balance_transfer/presentation/recipient_tile.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
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
/// rule); the B-040 money-movement confirmation is the arm-then-commit Send
/// button inside that dialog (B-113). Also lists the grant-ledger history.
/// B-092: which slice of the direct children the destination picker is showing.
enum _DestKind { subAgents, pos }

class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

/// Test seam: the money-button copy is worth asserting after a `\$`-escaping
/// bug shipped a literal "send \$amount to \$to" to users (B-113).
TransferStrings transferStringsFor(bool ar) => TransferStrings(ar);

typedef TransferStrings = _TS;

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
  String get takeBack => p('Take back balance', 'استرجاع رصيد');
  String takeBackFrom(String name) => p('Take back from $name', 'استرجاع من $name');
  String confirmTakeBack(String amount, String from) =>
      p('Confirm: take back $amount from $from', 'تأكيد: استرجاع $amount من $from');
  String get takenBack => p('Balance taken back', 'تم استرجاع الرصيد');
  String get takeBackHint => p(
      'Only balance the account has not spent can come back.',
      'يمكن استرجاع الرصيد غير المصروف فقط.');
  String get to => p('To', 'إلى');
  String get amount => p('Amount (IQD)', 'المبلغ (د.ع)');
  String get send => p('Send', 'إرسال');
  String confirmSend(String amount, String to) =>
      p('Confirm: send $amount to $to', 'تأكيد: إرسال $amount إلى $to');
  String get cancel => p('Cancel', 'إلغاء');
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
  Map<String, num> _childBal = const {};
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

  /// destId → current balance, for the "recipient has / will have" readout.
  /// Best-effort: the roster is VIEW_REPORTS-gated, and an agent may hold
  /// CREATE_TRANSACTIONS without it — a 403 must not break the transfer page.
  Future<Map<String, num>> _childBalances(dynamic api) async {
    try {
      final out = <String, num>{};
      var page = 0;
      while (true) {
        final res = await ReportsRepository(api)
            .balancesRoster(rootId: _myId, page: page, size: 200);
        for (final r in res.items) {
          out[r.entityId] = r.available;
        }
        if (!res.hasMore || page > 50) break;
        page++;
      }
      return out;
    } catch (_) {
      return const {};
    }
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
        _childBalances(api),
      ]);
      final grants = (results[1] as List<GrantRow>).toList()
        ..sort((a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'));
      if (!mounted) return;
      setState(() {
        _balance = results[0] as AgentBalance;
        _grants = grants;
        _children = results[2] as List<EntitySummaryRow>;
        _childBal = results[3] as Map<String, num>;
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
  /// Takes unspent balance back from a direct child.
  ///
  /// The ceiling is the CHILD's unspent balance, which this screen cannot know
  /// reliably — so it does not guess one. The server refuses and says exactly how
  /// much is reclaimable, and that message is shown as-is.
  Future<void> _takeBackDialog(_TS s) async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.noChildren)));
      return;
    }
    EntitySummaryRow? from;
    var armed = false;
    final amountCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final amt = parseAmount(amountCtrl.text) ?? 0;
        final ready = from != null && amt > 0;
        return AlertDialog(
          title: Text(s.takeBack),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<EntitySummaryRow>(
                initialValue: from,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.to),
                items: _children
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                    .toList(),
                onChanged: (v) => setD(() {
                  from = v;
                  armed = false;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: InputDecoration(labelText: s.amount),
                onChanged: (_) => setD(() => armed = false),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(s.takeBackHint,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: !ready
                  ? null
                  : () {
                      // Arm then commit, the same shape as sending.
                      if (!armed) {
                        setD(() => armed = true);
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
              child: Text(armed && ready
                  ? s.confirmTakeBack(
                      Formatters.iqd(amt.round()), from!.label)
                  : s.takeBack),
            ),
          ],
        );
      }),
    );

    final amount = parseAmount(amountCtrl.text);
    final target = from;
    if (ok != true || target == null || amount == null || amount <= 0) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PricingRepository(ref.read(apiClientProvider))
          .reclaim(destId: target.id, amount: amount);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.takenBack)));
      await _load();
    } catch (e) {
      if (mounted) {
        // The server knows the real ceiling; its wording is the useful one.
        messenger.showSnackBar(SnackBar(
            content: Text(serverReason(e) ?? friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newTransferDialog(_TS s) async {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.noChildren)));
      return;
    }
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final posCount = _children.where((e) => e.type == EntityType.STORE).length;
    final agentCount = _children.length - posCount;

    // POS points first — topping up a shop is the routine transfer; funding a
    // sub-agent is occasional. Falls back to agents when the account has no POS
    // points, so the dialog never opens on an empty list.
    var kind = posCount > 0 ? _DestKind.pos : _DestKind.subAgents;
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
        // B-128: a search spans BOTH kinds. Scoped to the selected segment, you
        // could not find an agent while POS was active — you had to guess which
        // tab a recipient lived on before you could look for it, which defeats
        // searching. The tier is on every row, so a mixed result stays readable.
        final rows = q.isEmpty
            ? byKind
            : _children
                .where((e) =>
                    e.label.toLowerCase().contains(q) ||
                    e.id.toLowerCase().contains(q))
                .toList();
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
              if (_children.length > 6)
                TextField(
                  decoration: InputDecoration(
                    hintText: ar
                        ? 'ابحث عن نقطة بيع أو وكيل…'
                        : 'Search a POS point or an agent…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setD(() { query = v; disarm(); }),
                ),
              if (_children.length > 6) const SizedBox(height: 8),
              // The list itself — visible, not behind a tap.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260), // taller: rows gained a tier line
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
                            return RecipientTile(
                              row: r,
                              selected: dest?.id == r.id,
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
              // The OTHER side of the transfer. Sending blind to a recipient whose
              // balance you can't see is how an agent double-tops-up a shop that
              // was already funded. Hidden when the roster is unavailable (the
              // feed is VIEW_REPORTS-gated) rather than showing a misleading zero.
              if (dest != null && _childBal.containsKey(dest!.id)) ...[
                const SizedBox(height: 10),
                Divider(height: 1, color: cs.outlineVariant),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(ar ? 'رصيد المستلم' : 'Recipient balance',
                      style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                  Text(Formatters.iqd(_childBal[dest!.id]!.round()),
                      style: IntesharType.mono(12.5, color: cs.onSurface)),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(ar ? 'بعد الاستلام' : 'After receiving',
                      style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                  Text(
                      Formatters.iqd((_childBal[dest!.id]! + amt).round()),
                      style: IntesharType.mono(12.5,
                          w: FontWeight.w700, color: IntesharColors.sage)),
                ]),
              ],
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

    // B-113: no second confirmation dialog. The B-040 requirement is satisfied
    // INSIDE the transfer dialog — Send arms, and a second press on a button that
    // spells out the amount and recipient commits. A further "are you sure" after
    // that is a third confirmation of the same intent, and users stop reading the
    // ones that always appear.

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
          TransferBalanceCard(
              label: s.available, amount: _balance?.available ?? 0),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _newTransferDialog(s),
              icon: const Icon(Icons.north_east, size: 18),
              label: Text(s.newTransfer),
            ),
          ),
          const SizedBox(height: 8),
          // B-034: the inverse a grant never had. Deliberately a SEPARATE action
          // rather than a mode inside the send dialog — that dialog has been the
          // subject of three regressions, and money moving the wrong way because
          // a toggle was missed is exactly the failure it keeps producing.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _takeBackDialog(s),
              icon: const Icon(Icons.south_west, size: 18),
              label: Text(s.takeBack),
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

/// The page's balance hero (B-094).
///
/// This card was the last solid-gold slab left in the app: brand gold carried a
/// whole surface, which is what B-094 demoted everywhere else (dashboard balance
/// card, POS tally, sign-in, splash). It is now a white card with a hairline
/// border, `elev1`, and a single 3px brand rule — the number is the hero, ink on
/// paper, and gold stays a ≤10% accent so it still means something.
///
/// Deliberately identical to the dashboard `_BalanceCard` treatment: the two are
/// the same object seen from two screens, so they must not read differently.
/// Extracted as a public widget so a test and the preview harness can render it
/// without a signed-in agent.
class TransferBalanceCard extends StatelessWidget {
  final String label;
  final num amount;

  const TransferBalanceCard({
    super.key,
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(IntesharRadii.lg),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: IntesharShadows.elev1,
      ),
      child: Row(children: [
        // The one flash of brand colour on the card.
        Container(
          width: 3,
          height: 40,
          decoration: BoxDecoration(
            color: context.tones.brand,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: IntesharType.overline(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              Formatters.iqd(amount.round()),
              style: TextStyle(
                fontFamily: 'CodecPro',
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
                letterSpacing: -0.8,
                height: 1,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
