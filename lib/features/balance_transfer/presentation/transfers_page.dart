import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/balance_transfer/presentation/money_dialog.dart';
import 'package:inteshar/features/balance_transfer/presentation/recipient_tile.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
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

  /// UX-88: for money, the AMOUNT is the confirmation. "Balance transferred"
  /// confirmed that *something* happened to *someone* — it did not confirm the
  /// figure that was typed, the account it went to, or what is left, which is
  /// the whole reason an agent watches a transfer land. Same shape as the
  /// withdraw toast the app already gets right ("Withdrew 60 of 100 — 40 left").
  String sentDetail(String amount, String to, String left) => p(
      'Sent $amount to $to — $left left',
      'أُرسل $amount إلى $to — تبقّى $left');
  String takenBackDetail(String amount, String from, String left) => p(
      'Took back $amount from $from — $left left',
      'استُرجع $amount من $from — تبقّى $left');

  /// Same confirmations, minus the remaining balance — used when the refresh
  /// that follows the transfer failed. The transfer itself succeeded, so it
  /// must still be confirmed; quoting the PRE-transfer balance as "left" would
  /// be worse than saying nothing about it.
  String sentDetailOnly(String amount, String to) =>
      p('Sent $amount to $to', 'أُرسل $amount إلى $to');
  String takenBackDetailOnly(String amount, String from) =>
      p('Took back $amount from $from', 'استُرجع $amount من $from');
  String get takeBackHint => p(
      'Only balance the account has not spent can come back.',
      'يمكن استرجاع الرصيد غير المصروف فقط.');
  String get to => p('To', 'إلى');

  /// UX-27: the take-back picker was labelled "To" while the money moves FROM
  /// the account it names — the one field on the page whose label pointed the
  /// opposite way to the transaction.
  String get from => p('From', 'من');
  String get accountBalance => p('Account balance', 'رصيد الحساب');
  String get afterTakeBack => p('After take-back', 'بعد الاسترجاع');
  String get overChildBalance =>
      p('More than this account currently has', 'أكثر مما يملكه هذا الحساب حالياً');
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

  /// UX-47: the ledger controls. The Reports → Transfers tab has a date filter,
  /// search, paging and a total; this page rendered the SAME ledger as one
  /// unbounded card list with none of them.
  String get allDates => p('All dates', 'كل التواريخ');
  String get searchHistory =>
      p('Search an account…', 'ابحث عن حساب…');
  String get totalSent => p('Sent', 'المُرسل');
  String get totalReceived => p('Received', 'المُستلم');
  String get noMatchingTransfers =>
      p('No transfers match these filters.', 'لا توجد تحويلات مطابقة لهذه المرشحات.');
  String showingOf(int shown, int total) =>
      p('Showing $shown of $total', 'عرض $shown من $total');
  String get showMore => p('Show more', 'عرض المزيد');
  String get clearFilters => p('Clear', 'مسح');
}

class _TransfersPageState extends ConsumerState<TransfersPage> {
  AgentBalance? _balance;
  List<GrantRow> _grants = const [];
  List<EntitySummaryRow> _children = const [];
  Map<String, num> _childBal = const {};
  bool _loading = true;

  /// UX-83: which ACTION is in flight, not "is the page busy". One page-wide
  /// flag disabled both money buttons and put a spinner on neither, so the only
  /// feedback for a transfer in progress was that everything went grey. Both
  /// buttons still lock while money is moving — they are the same balance — but
  /// the one that was tapped is the one that spins.
  final Set<String> _busy = {};
  static const _kSend = 'send';
  static const _kTakeBack = 'takeBack';
  bool get _anyBusy => _busy.isNotEmpty;
  Object? _error;

  /// UX-47 — the transfer-history controls. The whole ledger is already in
  /// memory (`GET /api/balance/grants` returns it unpaged), so the date window,
  /// the search and the page size are applied here rather than round-tripped.
  DateTime? _histFrom;
  DateTime? _histTo;
  String _histQuery = '';
  static const _histPageSize = 20;
  int _histShown = _histPageSize;

  bool get _histFiltered =>
      _histFrom != null || _histTo != null || _histQuery.trim().isNotEmpty;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The ledger after the date window and the search. `GrantRow.date` is an ISO
  /// `yyyy-MM-dd`, so a string compare IS the date compare.
  List<GrantRow> get _visibleGrants {
    final q = _histQuery.trim().toLowerCase();
    final from = _histFrom == null ? null : _ymd(_histFrom!);
    final to = _histTo == null ? null : _ymd(_histTo!);
    return _grants.where((g) {
      if (from != null && g.date.compareTo(from) < 0) return false;
      if (to != null && g.date.compareTo(to) > 0) return false;
      if (q.isEmpty) return true;
      return g.destName.toLowerCase().contains(q) ||
          g.sourceName.toLowerCase().contains(q) ||
          g.destId.toLowerCase().contains(q) ||
          g.sourceId.toLowerCase().contains(q);
    }).toList();
  }

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

  /// UX-84: [silent] refreshes in place instead of blanking the page.
  ///
  /// `_loading = true` makes `_body` return a full-screen spinner, so
  /// pull-to-refresh deleted the balance card, the two money buttons and the
  /// whole ledger — losing scroll position and any history filter the agent had
  /// just set. After a transfer it also hid the one thing worth watching: the
  /// balance moving and the new row landing at the top. Only the first load and
  /// an explicit retry blank.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
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

  /// UX-88: refresh, then report the balance the SERVER now holds — or null if
  /// the refresh didn't land.
  ///
  /// The confirmation quotes "what's left", and the only honest source for that
  /// is a figure read back after the transfer. `_load` swallows its own errors
  /// (it renders an ErrorState instead), so a failed refresh would otherwise
  /// leave `_balance` at its PRE-transfer value and the toast would confirm a
  /// number that was never true. Null means "say the amount and the recipient,
  /// but claim nothing about the remainder".
  Future<num?> _reloadForConfirmation() async {
    await _load(silent: true);
    if (!mounted || _error != null) return null;
    return _balance?.available;
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
    final ar = Localizations.localeOf(context).languageCode == 'ar';

    // UX-26: presented full-screen on a phone, scrollable everywhere else —
    // the amount field and the before→after readout must survive the keyboard.
    final ok = await showMoneyDialog(
      context: context,
      title: s.takeBack,
      width: 420,
      body: (ctx, setD) {
        final cs = Theme.of(ctx).colorScheme;
        final amt = parseAmount(amountCtrl.text) ?? 0;
        // UX-27: the ceiling was discovered by submitting and reading the
        // server's refusal — while the child's balance was already loaded into
        // _childBal and never consulted. Shown when known; the server stays the
        // authority (it knows what is actually unspent), so an over-amount is
        // flagged, not blocked.
        final known = from != null && _childBal.containsKey(from!.id);
        final childBal = known ? _childBal[from!.id]! : 0;
        final after = childBal - amt;
        return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              DropdownButtonFormField<EntitySummaryRow>(
                initialValue: from,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.from),
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
              if (known) ...[
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(s.accountBalance,
                      style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                  Text(Formatters.iqd(childBal.round()),
                      style: IntesharType.mono(12.5, color: cs.onSurface)),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(s.afterTakeBack,
                      style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                  Text(Formatters.iqd(after.round()),
                      style: IntesharType.mono(12.5,
                          w: FontWeight.w700,
                          color: after < 0 ? ctx.status.danger : cs.onSurface)),
                ]),
                if (after < 0) ...[
                  const SizedBox(height: 4),
                  Text(s.overChildBalance,
                      style: IntesharType.sans(11.5,
                          color: ctx.status.danger, w: FontWeight.w600)),
                ],
              ] else if (from != null) ...[
                const SizedBox(height: 12),
                Text(
                  ar
                      ? 'رصيد هذا الحساب غير متاح لك — سيحدد الخادم الحد الأقصى.'
                      : "This account's balance isn't visible to you — the server sets the ceiling.",
                  style: IntesharType.sans(11.5, color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(s.takeBackHint,
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
            ]);
      },
      actions: (ctx, setD) {
        final amt = parseAmount(amountCtrl.text) ?? 0;
        final ready = from != null && amt > 0;
        return [
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
            child: Text(
              armed && ready
                  ? s.confirmTakeBack(Formatters.iqd(amt.round()), from!.label)
                  : s.takeBack,
              textAlign: TextAlign.center,
            ),
          ),
        ];
      },
    );

    final amount = parseAmount(amountCtrl.text);
    final target = from;
    if (ok != true || target == null || amount == null || amount <= 0) return;
    if (!mounted) return;

    setState(() => _busy.add(_kTakeBack));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PricingRepository(ref.read(apiClientProvider))
          .reclaim(destId: target.id, amount: amount);
      if (!mounted) return;
      // UX-88: reload FIRST so "left" is the balance the server actually holds,
      // not a locally-subtracted guess — a take-back the server partially
      // refused would otherwise be confirmed with a figure that never existed.
      final fresh = await _reloadForConfirmation();
      if (!mounted) return;
      showOk(
        context,
        fresh == null
            ? s.takenBackDetailOnly(
                Formatters.iqd(amount.round()), target.label)
            : s.takenBackDetail(Formatters.iqd(amount.round()), target.label,
                Formatters.iqd(fresh.round())),
      );
    } catch (e) {
      if (mounted) {
        // The server knows the real ceiling; its wording is the useful one.
        messenger.showSnackBar(SnackBar(
            content: Text(serverReason(e) ?? friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(_kTakeBack));
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
    // UX-31: a two-way control is only worth a row when both ways lead somewhere.
    final showKind = posCount > 0 && agentCount > 0;
    EntitySummaryRow? dest;
    var query = '';
    var armed = false; // second press commits (B-040 confirmation, inlined)
    final amountCtrl = TextEditingController();
    String? fieldError;

    // UX-26: this form is ~550-600dp tall. On a phone with the keyboard open it
    // had ~320dp and silently lost its bottom — the amount field and the
    // before→after readout. Full-screen on mobile, scrollable elsewhere.
    final ok = await showMoneyDialog(
      context: context,
      title: s.newTransfer,
      width: 460,
      body: (ctx, setD) {
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

        void disarm() => armed = false;

        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Recipient type — the agent's OWN POS points are a first-class
              // choice here, not something hidden behind another dialog.
              //
              // UX-31: only when there is actually a choice to make. A Sub
              // Agent's children are ALL shops, so this control permanently read
              // "الوكلاء (0) | نقاط البيع (N)" — a tappable segment whose only
              // effect was to empty the list, costing a row in a dialog that
              // already overflows on a phone (UX-26). With one kind present the
              // list below IS that kind and needs no filter above it.
              if (showKind) ...[
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
              ],
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
                        color: after < 0 ? ctx.status.danger : cs.onSurface)),
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
                          w: FontWeight.w700, color: ctx.status.success)),
                ]),
              ],
            ]);
      },
      actions: (ctx, setD) {
        final avail = _balance?.available ?? 0;
        final amt = parseAmount(amountCtrl.text) ?? 0;
        final ready = dest != null && amt > 0 && (avail - amt) >= 0;
        return [
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
            child: Text(
              armed && ready
                  ? s.confirmSend(Formatters.iqd(amt.round()), dest!.label)
                  : s.send,
              textAlign: TextAlign.center,
            ),
          ),
        ];
      },
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

    setState(() => _busy.add(_kSend));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PricingRepository(ref.read(apiClientProvider))
          .grant(destId: target.id, amount: amount);
      if (!mounted) return;
      // UX-88: see [_TS.sentDetail] — reload before confirming so the remaining
      // balance quoted is the server's, not this screen's arithmetic.
      final fresh = await _reloadForConfirmation();
      if (!mounted) return;
      showOk(
        context,
        fresh == null
            ? s.sentDetailOnly(Formatters.iqd(amount.round()), target.label)
            : s.sentDetail(Formatters.iqd(amount.round()), target.label,
                Formatters.iqd(fresh.round())),
      );
    } catch (e) {
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(_kSend));
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
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 28),
        children: [
          TransferBalanceCard(
              label: s.available, amount: _balance?.available ?? 0),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _anyBusy ? null : () => _newTransferDialog(s),
              icon: _busy.contains(_kSend)
                  ? const _BtnSpinner()
                  : const Icon(Icons.north_east, size: 18),
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
              onPressed: _anyBusy ? null : () => _takeBackDialog(s),
              icon: _busy.contains(_kTakeBack)
                  ? const _BtnSpinner()
                  : const Icon(Icons.south_west, size: 18),
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
            ..._history(s, cs),
        ],
      ),
    );
  }

  /// UX-47 — the same four controls the Reports → Transfers tab has: a date
  /// window, a search, running totals for what is on screen, and paging. This
  /// page used to render the entire ledger as one unbounded card list, so two
  /// views of ONE ledger behaved completely differently.
  List<Widget> _history(_TS s, ColorScheme cs) {
    final rows = _visibleGrants;
    final sent = rows
        .where((g) => g.sourceId == _myId)
        .fold<num>(0, (a, g) => a + g.amount);
    final received = rows
        .where((g) => g.destId == _myId)
        .fold<num>(0, (a, g) => a + g.amount);
    final shown = rows.take(_histShown).toList();
    final rangeLabel = (_histFrom != null && _histTo != null)
        ? '${_ymd(_histFrom!)} → ${_ymd(_histTo!)}'
        : s.allDates;

    return [
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickHistoryRange(),
            icon: const Icon(Icons.date_range_outlined, size: 16),
            label: Text(rangeLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        if (_histFiltered) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => setState(() {
              _histFrom = null;
              _histTo = null;
              _histQuery = '';
              _histShown = _histPageSize;
            }),
            child: Text(s.clearFilters),
          ),
        ],
      ]),
      const SizedBox(height: 8),
      TextField(
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: s.searchHistory,
        ),
        onChanged: (v) => setState(() {
          _histQuery = v;
          _histShown = _histPageSize;
        }),
      ),
      const SizedBox(height: 10),
      // Totals for exactly what the filters selected — the figure the agent is
      // actually looking for when they open the history at all.
      Row(children: [
        Expanded(
          child: _HistoryTotal(
            label: s.totalSent,
            amount: sent,
            // UX-128: money you SENT is the product working — brand, not error.
            tint: context.status.brand,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _HistoryTotal(
            label: s.totalReceived,
            amount: received,
            tint: context.status.success,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
              child: Text(s.noMatchingTransfers,
                  textAlign: TextAlign.center,
                  style: IntesharType.sans(14, color: cs.onSurfaceVariant))),
        )
      else ...[
        for (final g in shown) _grantCard(s, g, cs),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Row(children: [
            Expanded(
              child: Text(s.showingOf(shown.length, rows.length),
                  style: IntesharType.sans(11.5, color: cs.onSurfaceVariant)),
            ),
            if (shown.length < rows.length)
              TextButton(
                onPressed: () =>
                    setState(() => _histShown += _histPageSize),
                child: Text(s.showMore),
              ),
          ]),
        ),
      ],
    ];
  }

  Future<void> _pickHistoryRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: (_histFrom != null && _histTo != null)
          ? DateTimeRange(start: _histFrom!, end: _histTo!)
          : null,
    );
    if (range == null || !mounted) return;
    setState(() {
      _histFrom = range.start;
      _histTo = range.end;
      _histShown = _histPageSize;
    });
  }

  Widget _grantCard(_TS s, GrantRow g, ColorScheme cs) {
    final sent = g.sourceId == _myId;
    final other = sent
        ? (g.destName.isNotEmpty ? g.destName : g.destId)
        : (g.sourceName.isNotEmpty ? g.sourceName : g.sourceId);
    // UX-128: an outgoing transfer is not a failure. `brand` for what left,
    // `success` for what arrived — red stays available for things that broke.
    final tint = sent ? context.status.brand : context.status.success;
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
              borderRadius: BorderRadius.circular(IntesharRadii.sm),
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

/// One half of the transfer-history total strip (UX-47). Reads over the FILTERED
/// ledger, so the number always answers "in this window, for this search".
class _HistoryTotal extends StatelessWidget {
  final String label;
  final num amount;
  final Color tint;
  const _HistoryTotal({
    required this.label,
    required this.amount,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // UX-126: an `InkCard`, not a second hand-rolled card recipe painted in the
    // page's own colour.
    return InkCard(
      bordered: true,
      elevated: false,
      borderRadius: BorderRadius.circular(IntesharRadii.md),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: IntesharType.overline(color: cs.onSurfaceVariant)),
        const SizedBox(height: 3),
        Text(Formatters.iqd(amount.round()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IntesharType.mono(14, w: FontWeight.w700, color: tint)),
      ]),
    );
  }
}

/// An icon-sized spinner that sits in a button's icon slot, so the control that
/// was tapped is the one showing progress (UX-83).
class _BtnSpinner extends StatelessWidget {
  const _BtnSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
}

/// The page's balance hero (B-094).
///
/// This card was the last solid-gold slab left in the app: brand gold carried a
/// whole surface, which is what B-094 demoted everywhere else (dashboard balance
/// card, POS tally, sign-in, splash). It is now a card with a hairline border,
/// `elev1`, and a single 3px brand rule — the number is the hero, ink on paper,
/// and gold stays a ≤10% accent so it still means something.
///
/// UX-126: it is now literally an `InkCard(bordered: true)` rather than a
/// second card recipe filled with `cs.surface` — which IS the page background,
/// so the "card" was only ever a rectangle of border.
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
    return InkCard(
      bordered: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(children: [
        // The one flash of brand colour on the card.
        BrandRule(width: 3, height: 40),
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
