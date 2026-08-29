import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_network.dart';
import 'package:inteshar/features/pos_admin/domain/pos_roles.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_admin_page.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/multi_select.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// HQ-only network oversight (B-029): every agent's POS-slot line (used/unused points),
/// with network KPIs, name search, and a Main/Sub tier filter. Tapping an agent drills
/// into that agent's POS points (reusing [PosAdminPage] in target mode).
class PosNetworkView extends ConsumerStatefulWidget {
  const PosNetworkView({super.key});

  @override
  ConsumerState<PosNetworkView> createState() => _PosNetworkViewState();
}

class _NS {
  final bool ar;
  const _NS(this.ar);
  factory _NS.of(BuildContext c) => _NS(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String a) => ar ? a : en;
  String get eyebrow => p('OVERSIGHT', 'الإشراف');
  String get title => p('POS points — all agents', 'نقاط البيع — كل الوكلاء');
  String get subtitle => p('Used and unused points across the network', 'النقاط المستخدمة والمتاحة عبر الشبكة');
  String get points => p('POS points', 'نقاط البيع');
  String get unused => p('Unused', 'المتاحة');
  String get issued => p('Issued', 'الممنوحة');
  String get agents => p('Agents', 'الوكلاء');
  String get search => p('Search agent by name…', 'بحث عن وكيل بالاسم…');
  String get all => p('All', 'الكل');
  String get main => p('Main', 'رئيسي');
  String get sub => p('Sub', 'فرعي');
  String get used => p('used', 'مستخدم');
  String get avail => p('available', 'متاح');
  String get ofTotal => p('of', 'من');
  String get empty => p('No agents match.', 'لا يوجد وكلاء مطابقون.');
  String get loadMore => p('Load more', 'تحميل المزيد');
  String get grantAny => p('Grant POS points', 'منح نقاط بيع');
  String get grantAnySubtitle => p('Give points to any main or sub agent', 'منح النقاط لأي وكيل رئيسي أو فرعي');
  String get searchAny => p('Search agent by name…', 'بحث عن وكيل بالاسم…');
  String get count => p('Number of points', 'عدد النقاط');
  String get noMatches => p('No matching agents', 'لا يوجد وكلاء مطابقون');
  String get cancel => p('Cancel', 'إلغاء');
  String get grant => p('Grant', 'منح');
  String get done => p('Done', 'تم');
  // UX-11: granting points is HQ's most-repeated act on this roster, and it was
  // one picker + one dialog PER AGENT. Onboarding a governorate meant doing it a
  // dozen times.
  static const agentUnit = BulkUnit(ar: 'وكيل', en: 'agents');
  String get grantToSelected => p('Grant to selected', 'منح للمحددين');
  String get atLeastOne => p('Enter at least 1', 'أدخل 1 على الأقل');
  String grantN(int n) =>
      p('Grant points to $n agents?', 'منح نقاط لـ $n وكيل؟');
  String grantBody(int points, int agents) => p(
      '$points POS points go to each of the $agents selected agents — $points × $agents in total.',
      'ستذهب $points نقطة بيع إلى كل وكيل من الوكلاء الـ$agents المحددين — أي $points × $agents إجمالاً.');
}

class _PosNetworkViewState extends ConsumerState<PosNetworkView> {
  PosNetworkSummary? _summary;
  final List<PosNetworkRow> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _page = 0;
  String _query = '';
  String _tier = ''; // '' = all, 'AGENT1', 'AGENT2'
  Timer? _debounce;

  /// UX-11: multi-select over the agent roster, so one grant covers a whole
  /// tier or a whole governorate's sub-agents.
  SelectionState _selection = SelectionState.off;
  bool _bulkBusy = false;

  /// How many points the pending bulk grant gives EACH selected agent. Asked by
  /// [BulkAction.prepare] before the confirmation, so the confirmation can state
  /// both numbers.
  int _grantEach = 1;

  PosAdminRepository get _repo => PosAdminRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// UX-84: [silent] refreshes the rows in place.
  ///
  /// `_loading = true` makes `_body` return a full-screen spinner, so
  /// pull-to-refresh deleted the KPI strip, the filters and the roster — and a
  /// debounced search tore down the very TextField being typed into, closing
  /// the keyboard mid-word. Only the first load blanks.
  Future<void> _reload({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final summary = await _repo.networkSummary();
      final pageData = await _repo.network(q: _query, tier: _tier, page: 0, size: 20);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _rows
          ..clear()
          ..addAll(pageData.items);
        _hasMore = pageData.hasMore;
        _page = 0;
        _loading = false;
        // A tier filter or a search replaces the roster; ticks on rows that are
        // no longer here must not survive into the next run.
        _selection = _selection.retain(pageData.items.map((r) => r.entityId));
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final pageData = await _repo.network(q: _query, tier: _tier, page: next, size: 20);
      if (!mounted) return;
      setState(() {
        _rows.addAll(pageData.items);
        _hasMore = pageData.hasMore;
        _page = next;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = v.trim();
      _reload(silent: true);
    });
  }

  void _setTier(String t) {
    if (t == _tier) return;
    setState(() => _tier = t);
    _reload(silent: true);
  }

  Future<void> _openAgent(PosNetworkRow r) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PosAdminPage(targetEntityId: r.entityId, targetName: r.name),
    ));
    _reload(silent: true); // reflect any grant/onboard/revoke done in the drill
  }

  /// HQ grants POS points directly to any AGENT — main or sub (B-043), skipping
  /// the intermediate tier. Server-searched picker (B-023: no more downloading
  /// every entity), then a count prompt for the chosen agent.
  Future<void> _grantAnyDialog(_NS s) async {
    // Recipients are the tiers that can actually SPEND a point by onboarding a
    // shop. Stores used to be offered here, but a store is itself a POS point:
    // the server refuses to onboard under one, so points granted to a store
    // were unspendable — while still counting as "issued" in the KPIs above.
    final picked = await showEntitySearchPicker(
      context,
      repository: EntityRepository(ref.read(apiClientProvider)),
      title: s.grantAny,
      types: kPosPointHolderTypes,
    );
    if (picked == null || !mounted) return;
    final countCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.grantAny),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(picked.label, overflow: TextOverflow.ellipsis),
            subtitle: Text(picked.type.label,
                style: IntesharType.sans(
                    12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: countCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: s.count, isDense: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.grant)),
        ],
      ),
    );
    final n = int.tryParse(countCtrl.text.trim()) ?? 0;
    if (ok != true || n <= 0) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.grantSlots(destId: picked.id, count: n);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(s.done)));
      _reload(silent: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
  }

  // ── UX-11: grant to a whole selection ──────────────────────────────────────

  /// Asks how many points EACH selected agent gets, before the confirmation.
  ///
  /// A per-agent number rather than a pot to divide: that is what the single
  /// grant has always meant, and quietly changing the unit at the moment the
  /// operation gets bigger is how "grant 10" turns into 10 agents with 1 point.
  Future<bool> _askGrantEach(_NS s) async {
    final countCtrl = TextEditingController(text: '$_grantEach');
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.grantToSelected),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: TextFormField(
            controller: countCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: s.count, isDense: true),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              // UX-73: an empty or zero count used to close the dialog and grant
              // nothing, silently. In bulk that silence would cover N agents.
              return (n == null || n < 1) ? s.atLeastOne : null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(s.grant),
          ),
        ],
      ),
    );
    final n = int.tryParse(countCtrl.text.trim()) ?? 0;
    countCtrl.dispose();
    if (ok != true || n < 1) return false;
    _grantEach = n;
    return true;
  }

  List<BulkAction> _bulkActions(_NS s) => [
        BulkAction(
          label: s.grant,
          icon: Icons.card_giftcard,
          prepare: () => _askGrantEach(s),
          title: s.grantN,
          body: (n) => s.grantBody(_grantEach, n),
          run: (id) => _repo.grantSlots(destId: id, count: _grantEach),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final s = _NS.of(context);
    return MaxWidthBox(
      maxWidth: 860,
      child: Column(
        children: [
          PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(_NS s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _reload);
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => _reload(silent: true),
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 28),
        children: [
          if (_summary != null) _kpiStrip(s, _summary!),
          const SizedBox(height: 12),
          // B-043: HQ is the sole distributor of POS points — grant to ANY account
          // (agent or store), so a store isn't stranded now that agents can't grant.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _grantAnyDialog(s),
              icon: const Icon(Icons.card_giftcard, size: 18),
              label: Text(s.grantAny),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                enabled: !_bulkBusy,
                decoration: InputDecoration(
                  labelText: s.search,
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
                onChanged: _onSearch,
              ),
            ),
            SelectionModeButton(
              state: _selection,
              enabled: !_bulkBusy,
              onChanged: (v) => setState(() => _selection = v),
            ),
          ]),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: '', label: Text(s.all)),
              ButtonSegment(value: 'AGENT1', label: Text(s.main)),
              ButtonSegment(value: 'AGENT2', label: Text(s.sub)),
            ],
            selected: {_tier},
            showSelectedIcon: false,
            onSelectionChanged: _bulkBusy ? null : (v) => _setTier(v.first),
          ),
          if (_selection.active) ...[
            const SizedBox(height: 10),
            SelectionBar(
              state: _selection,
              visibleIds: [for (final r in _rows) r.entityId],
              onChanged: (v) => setState(() => _selection = v),
              onBusyChanged: (b) => setState(() => _bulkBusy = b),
              onCompleted: () => _reload(silent: true),
              unit: _NS.agentUnit,
              actions: _bulkActions(s),
            ),
          ],
          const SizedBox(height: 14),
          if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text(s.empty, style: IntesharType.sans(14, color: cs.onSurfaceVariant))),
            )
          else
            for (final r in _rows) _agentCard(s, r, cs),
          if (_hasMore) ...[
            const SizedBox(height: 8),
            Center(
              child: _loadingMore
                  ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : OutlinedButton(onPressed: _loadMore, child: Text(s.loadMore)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiStrip(_NS s, PosNetworkSummary q) => BrandKpiStrip(stats: [
        (s.points, '${q.totalUsed}'),
        (s.unused, '${q.unused}'),
        (s.issued, '${q.totalIssued}'),
        (s.agents, '${q.agents}'),
      ]);



  Widget _agentCard(_NS s, PosNetworkRow r, ColorScheme cs) {
    final isSub = r.tier == 'AGENT2';
    final selecting = _selection.active;
    final selected = _selection.contains(r.entityId);
    void toggle() =>
        setState(() => _selection = _selection.toggle(r.entityId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkCard(
        density: CardDensity.dense,
        ruleColor: selected ? context.tones.brand : null,
        onTap: selecting ? toggle : () => _openAgent(r),
        child: Row(children: [
          if (selecting) ...[
            SelectionCheckbox(
              selected: selected,
              semanticLabel: r.name.isNotEmpty ? r.name : r.entityId,
              onChanged: _bulkBusy ? null : (_) => toggle(),
            ),
            const SizedBox(width: IntesharSpacing.xs),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(r.name.isNotEmpty ? r.name : r.entityId, style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                StampPill(label: isSub ? s.sub : s.main, color: isSub ? context.status.success : context.tones.brandInk),
              ]),
              if (isSub && (r.parentName ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(r.parentName!, style: IntesharType.sans(12, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              Text('${Formatters.money(r.used)} ${s.used} · ${Formatters.money(r.available)} ${s.avail} ${s.ofTotal} ${Formatters.money(r.total)}',
                  style: IntesharType.mono(12, color: cs.onSurfaceVariant)),
            ]),
          ),
          // UX-130: NOT a FigureBlock — the label sits UNDER the figure and the
          // pair is end-aligned against the row's chevron, neither of which
          // FigureBlock offers, and inverting it here would leave this card
          // reading differently from every other figure on the screen for the
          // sake of the migration. What it did need was to stop hand-rolling
          // the numeral: the raw `TextStyle(fontFamily: 'CodecPro', 24, w900)`
          // bypassed the display helper and with it the Arabic tracking guard.
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(Formatters.money(r.used),
                style: IntesharText.display(
                    color: cs.onSurface, w: IntesharWeight.black)),
            Text(s.points, style: IntesharType.overline(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(width: 6),
          // In selection mode the card ticks rather than drills in, so the
          // chevron would be promising a hop that no longer happens.
          if (!selecting)
            Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left : Icons.chevron_right, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}
