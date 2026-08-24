import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_stats.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// UX-07 — one shop, one screen: "why can't this shop sell?".
///
/// The answer used to be spread over six screens, and the two most likely causes
/// were the two a manager could not see anywhere:
///
/// - the shop's **balance** — a draw-on-print point with none can't buy a card
///   off its parent's pool, so the POS grid is there and every sale refuses;
/// - **`locationConfirmedAt == null`** — a hard gate on selling that
///   `pos_home_page` enforces, sitting on the object the POS list already
///   fetched, rendered nowhere.
///
/// So this sheet leads with the GATES (each pass/fail, in the order the server
/// applies them), then the numbers behind them. Everything comes from feeds the
/// caller can already reach: `GET /api/entity/posStats`
/// (HQ-or-self-or-descendant) and `GET /product/sellable?entityId=` — the exact
/// list the shop's own POS renders, so "nothing to sell" here means nothing to
/// sell there.
Future<void> showPosShopSheet(
  BuildContext context,
  WidgetRef ref, {
  required Entity store,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PosShopSheet(store: store, ref: ref),
  );
}

/// One diagnostic line: a check that either passes or blocks the sale.
class _Gate {
  final String label;
  final String detail;

  /// null = not a pass/fail (informational), true = fine, false = blocks selling.
  final bool? ok;
  const _Gate(this.label, this.detail, this.ok);
}

class _PosShopSheet extends StatefulWidget {
  final Entity store;
  final WidgetRef ref;
  const _PosShopSheet({required this.store, required this.ref});

  @override
  State<_PosShopSheet> createState() => _PosShopSheetState();
}

class _PosShopSheetState extends State<_PosShopSheet> {
  PosStats? _stats;
  List<SellableSku>? _sellable;
  Object? _error;
  bool _loading = true;

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
    final api = widget.ref.read(apiClientProvider);
    try {
      final stats = await PosAdminRepository(api).stats(widget.store.id);
      // Best-effort: the sellable pool is the SECOND half of the answer, but a
      // failure here must not cost the manager the gates and the balance, which
      // are the two things they came for.
      List<SellableSku>? sellable;
      try {
        sellable = await ProductRepository(api).sellable(entityId: widget.store.id);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _sellable = sellable;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';
  String _p(String en, String ar) => _ar ? ar : en;

  /// The shop's POS operator, or null. Same strict rule as the list (B-130): a
  /// user without `isPos` is one the server refuses every operator action for.
  EntityUser? get _operator {
    for (final u in widget.store.users) {
      if (u.isPos) return u;
    }
    return null;
  }

  /// "HH:mm → HH:mm" plus the days, or '' when no window is configured.
  String _windowText(WorkingHours w) {
    final days = w.days.isEmpty
        ? _p('every day', 'كل الأيام')
        : w.days.map(_dayName).join('، ');
    return '${w.start} → ${w.end} · $days';
  }

  String _dayName(int iso) {
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const ar = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    if (iso < 1 || iso > 7) return '$iso';
    return _ar ? ar[iso - 1] : en[iso - 1];
  }

  /// Whether `now` falls inside [w]. `end < start` means the window wraps past
  /// midnight, which is the shape the model documents.
  bool _insideWindow(WorkingHours w, DateTime now) {
    int? mins(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.length != 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return h * 60 + m;
    }

    final start = mins(w.start);
    final end = mins(w.end);
    if (start == null || end == null) return true; // unparseable = don't accuse
    if (w.days.isNotEmpty && !w.days.contains(now.weekday)) return false;
    final t = now.hour * 60 + now.minute;
    return end >= start ? (t >= start && t <= end) : (t >= start || t <= end);
  }

  List<_Gate> _gates(PosStats stats) {
    final store = widget.store;
    final op = _operator;
    final confirmed = store.profile?.locationConfirmedAt;
    final wh = store.meta.workingHours;
    final sellable = _sellable;
    final affordable = sellable == null
        ? 0
        : sellable.fold<int>(0, (a, s) => a + s.affordable);
    final available = sellable == null
        ? 0
        : sellable.fold<int>(0, (a, s) => a + s.available);

    return [
      _Gate(
        _p('Account active', 'الحساب مُفعّل'),
        store.active
            ? _p('Its operator can sign in.', 'يمكن لمشغّلها تسجيل الدخول.')
            : _p('Deactivated — its operator cannot sign in at all.',
                'موقوف — لا يستطيع المشغّل تسجيل الدخول إطلاقاً.'),
        store.active,
      ),
      _Gate(
        _p('POS operator', 'مستخدم نقطة البيع'),
        op == null
            ? _p('No POS user on this shop — nobody can open the POS.',
                'لا يوجد مستخدم نقطة بيع لهذا المتجر — لا يمكن فتح نقطة البيع.')
            : op.phone,
        op != null,
      ),
      // The gate `pos_home_page` enforces before it will sell anything.
      _Gate(
        _p('Location confirmed', 'الموقع مؤكَّد'),
        confirmed ??
            _p('Not confirmed — selling is blocked until the operator confirms '
                'the location once, standing in the shop.',
                'غير مؤكَّد — البيع متوقف حتى يؤكد المشغّل الموقع مرة واحدة من داخل المتجر.'),
        confirmed != null,
      ),
      if (wh != null && wh.enabled)
        _Gate(
          _p('Working hours', 'ساعات العمل'),
          _windowText(wh),
          _insideWindow(wh, DateTime.now()),
        )
      else
        _Gate(_p('Working hours', 'ساعات العمل'),
            _p('No window — signing in is allowed at any time.',
                'بدون تحديد — الدخول متاح في أي وقت.'),
            null),
      _Gate(
        _p('Balance', 'الرصيد'),
        Formatters.iqd(stats.balanceAvailable.round()),
        stats.balanceAvailable > 0,
      ),
      // Draw-on-print: the shop sells from its PARENT's pool, so this is the
      // list its own POS grid renders. Null = the feed failed, which must not
      // be drawn as "nothing to sell".
      if (sellable != null)
        _Gate(
          _p('Cards it can sell now', 'الكروت القابلة للبيع الآن'),
          affordable > 0
              ? _p('$affordable of $available in the pool are within its balance.',
                  '$affordable من $available في المخزن ضمن رصيدها.')
              : (available > 0
                  ? _p('$available in the pool, but its balance affords none.',
                      '$available في المخزن، لكن رصيدها لا يكفي لأي منها.')
                  : _p('Nothing in the pool for this shop — check its governorate '
                      'and the parent stock.',
                      'لا يوجد شيء في المخزن لهذا المتجر — راجع محافظتها ومخزون الوكيل.')),
          affordable > 0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    final store = widget.store;
    final gov = store.meta.governorates.isNotEmpty ? store.meta.governorates.first : '';
    final name = store.meta.name.isNotEmpty ? store.meta.name : (_operator?.phone ?? '');

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: IntesharType.sans(18, color: cs.onSurface, w: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              [
                if (store.profile?.ownerName.isNotEmpty ?? false) store.profile!.ownerName,
                if (gov.isNotEmpty) governorateLabel(gov, loc),
                if (store.profile?.address.isNotEmpty ?? false) store.profile!.address,
              ].join(' · '),
              style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null) ...[
              Text(friendlyError(_error!, context),
                  style: IntesharType.sans(13, color: cs.error)),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _load, child: Text(_p('Try again', 'إعادة المحاولة'))),
            ] else ...[
              for (final g in _gates(_stats!)) _gateRow(g, cs),
              const SizedBox(height: 14),
              const Hairline(),
              const SizedBox(height: 12),
              _kv(_p('Cards sold (lifetime)', 'الكروت المباعة (الإجمالي)'),
                  Formatters.money(_stats!.printedCount), cs),
              _kv(_p('Cards held by the shop', 'الكروت لدى المتجر'),
                  Formatters.money(_stats!.availableCount), cs),
              _kv(
                _p('Last activity', 'آخر نشاط'),
                _stats!.lastSeenAt.isEmpty
                    ? _p('Never signed in', 'لم يسجّل الدخول قط')
                    : _stats!.lastSeenAt,
                cs,
              ),
              if (_stats!.lastDeviceModel.isNotEmpty)
                _kv(
                  _p('Device', 'الجهاز'),
                  [
                    _stats!.lastDeviceModel,
                    if (_stats!.lastPlatform.isNotEmpty) _stats!.lastPlatform,
                    if (_stats!.lastAppVersion.isNotEmpty) 'v${_stats!.lastAppVersion}',
                  ].join(' · '),
                  cs,
                ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _gateRow(_Gate g, ColorScheme cs) {
    // Never colour alone: each state carries its own icon (UX-144).
    final (IconData icon, Color tint) = switch (g.ok) {
      true => (Icons.check_circle_outline, IntesharColors.sage),
      false => (Icons.error_outline, cs.error),
      _ => (Icons.remove_circle_outline, cs.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: tint),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.label,
                style: IntesharType.sans(13.5,
                    color: cs.onSurface,
                    w: g.ok == false ? FontWeight.w800 : FontWeight.w600)),
            const SizedBox(height: 1),
            Text(g.detail,
                style: IntesharType.sans(12,
                    color: g.ok == false ? cs.error : cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(String label, String value, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: Text(label,
                style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w600)),
          ),
        ]),
      );
}
