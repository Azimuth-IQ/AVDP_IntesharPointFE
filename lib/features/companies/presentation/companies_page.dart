import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/companies/data/company_repository.dart';
import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
import 'package:inteshar/shared/widgets/confirm_dialog.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
import 'package:inteshar/shared/widgets/loading_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// Local Arabic/English strings for the Companies admin page.
class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) => _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('Administration', 'الإدارة');
  String get title => p('Companies', 'الشركات');
  String get subtitle => p('Telecom providers and their catalog', 'شركات الاتصال وكتالوجها');
  String get newCompany => p('New Company', 'شركة جديدة');
  String get empty => p('No companies yet', 'لا توجد شركات بعد');
  String get emptyHint => p('Add a telecom provider (Asiacell, Zain…).', 'أضف شركة اتصال (آسياسيل، زين…).');
  String get name => p('Name', 'الاسم');
  // UX-74: this labels an ImageUploadField — a thumbnail and an Add button.
  // There is no text box and no URL to paste anywhere in the widget, so "Logo
  // URL" sent the operator hunting for a link they were never given.
  String get logo => p('Logo (optional)', 'الشعار (اختياري)');
  String get description => p('Description (optional)', 'الوصف (اختياري)');
  String get order => p('Display order', 'ترتيب العرض');
  String get active => p('Active', 'مفعّلة');
  String get inactive => p('Inactive', 'متوقفة');
  String get save => p('Save', 'حفظ');
  String get cancel => p('Cancel', 'إلغاء');
  String get edit => p('Edit', 'تعديل');
  String get delete => p('Delete', 'حذف');
  String get deleteTitle => p('Delete company?', 'حذف الشركة؟');
  String get deleteAnyway => p('Delete anyway', 'حذف على أي حال');
  String deleteBody(String n) => p('Remove "$n"? Its categories will be left uncategorized.',
      'إزالة "$n"؟ ستبقى فئاتها بدون تصنيف.');
  String get errName => p('Name is required', 'الاسم مطلوب');
  String get createTitle => p('New company', 'شركة جديدة');
  String get editTitle => p('Edit company', 'تعديل الشركة');
  // UX-71: the cap and the window are ONE rule. They used to be two labelled
  // boxes that never referenced each other — "Withdrawal cap per shop (0 =
  // unlimited)" truncated inside ~160px next to "Window (hours)" — and this
  // rule throttles selling at every POS on the platform, so a misread `1`
  // silently 429s every shop. It is now written as one sentence with the two
  // numbers inline, plus a plain-language readout of what was just typed.
  String get capSection => p('Selling limit per shop', 'حد البيع لكل نقطة');
  String get capLead => p('Limit each shop to', 'حدّ كل نقطة بـ');
  String get capMid => p('cards every', 'كرت كل');
  String get capTail => p('hours', 'ساعة');
  String get capUnlimited => p(
      'No limit — every shop may sell as many of this company’s cards as it holds.',
      'بلا حد — كل نقطة تبيع من كروت هذه الشركة بقدر ما لديها.');
  String capReadout(int n, int h) => p(
      'Each shop may sell at most $n card(s) of this company in any $h-hour window; the next sale is refused until the window rolls.',
      'كل نقطة تبيع $n كرت كحد أقصى من هذه الشركة خلال كل $h ساعة، ثم يُرفض البيع حتى تنتهي المدة.');
  // The rule is invisible on the list, so a shop hitting a 429 sends the admin
  // into the dialog of every company to find which one is capped.
  String capRow(int n, int h) => p('$n / $h h per shop', '$n لكل نقطة / $h س');
  String get capRowNone => p('No selling limit', 'بلا حد بيع');
  String get restrictSection => p('Restrict for agents', 'تقييد لوكلاء');
  String get restrictHint => p('Hidden for the chosen agent and everything under it.', 'يُخفى عن الوكيل المحدد وكل ما تحته.');
  String get addAgent => p('Add agent', 'إضافة وكيل');
  // UX-121: the row's `⋮` had no tooltip, so on a desktop console the only way
  // to learn what it opens was to open it. Names the menu, not the glyph.
  String get rowMenu => p('Company actions', 'إجراءات الشركة');
  String get done => p('Done', 'تم');
}

class CompaniesPage extends ConsumerStatefulWidget {
  const CompaniesPage({super.key});

  @override
  ConsumerState<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends ConsumerState<CompaniesPage> {
  List<Company> _items = [];
  bool _loading = true;
  Object? _error;

  /// Company ids with a delete in flight. UX-87: the confirm dialog closed
  /// instantly and the DELETE then ran with nothing disabled, so the row menu
  /// could fire it again — and the second call reaches a server that may still
  /// be finishing the first.
  final Set<String> _deleting = {};

  CompanyRepository get _repo => CompanyRepository(ref.read(apiClientProvider));

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
      final items = await _repo.readAll();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _openForm({Company? existing}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _CompanyDialog(existing: existing, repo: _repo),
    );
    if (ok != true) return;
    // UX-88: the dialog closed and the list quietly reloaded. On a list where
    // rows are ordered by displayOrder rather than recency, a newly added
    // company can land anywhere — so "it worked" was left to be inferred from
    // spotting it. Name what happened, and say which one.
    if (mounted) {
      final s = _S.of(context);
      showOk(
        context,
        existing == null
            ? s.p('Company added', 'تمت إضافة الشركة')
            : s.p('Saved "${existing.name}"', 'تم حفظ "${existing.name}"'),
      );
    }
    _load();
  }

  Future<void> _confirmDelete(Company c) async {
    if (_deleting.contains(c.id)) return;
    final s = _S.of(context);
    final ok = await showConfirm(
      context,
      title: s.deleteTitle,
      body: s.deleteBody(c.name),
      confirmLabel: s.delete,
      cancelLabel: s.cancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _runDelete(s, c);
  }

  /// The server refuses while the company still has categories and says how many.
  /// That count is the thing worth confirming — the generic warning above cannot
  /// know it — so the refusal becomes a second, specific prompt rather than an
  /// error the operator has to interpret.
  ///
  /// The forced retry is a loop, not recursion, so the in-flight guard can be
  /// held across both passes instead of blocking the second one.
  Future<void> _runDelete(_S s, Company c) async {
    var force = false;
    while (true) {
      setState(() => _deleting.add(c.id));
      Object? failure;
      try {
        await _repo.delete(c.id, force: force);
      } catch (e) {
        failure = e;
      }
      if (!mounted) return;
      setState(() => _deleting.remove(c.id));
      if (failure == null) {
        // UX-88: a deletion that can CASCADE (the force path below removes the
        // company's restrictions with it) must say what it took, not just make
        // a row disappear.
        if (mounted) {
          showOk(
            context,
            force
                ? s.p('Deleted "${c.name}" and its restrictions',
                    'تم حذف "${c.name}" والقيود المرتبطة بها')
                : s.p('Deleted "${c.name}"', 'تم حذف "${c.name}"'),
          );
        }
        await _load();
        return;
      }
      final reason = serverReason(failure);
      if (!force &&
          reason != null &&
          ApiException.from(failure)?.statusCode == 409) {
        final again = await showConfirm(
          context,
          title: s.deleteTitle,
          body: reason,
          confirmLabel: s.deleteAnyway,
          cancelLabel: s.cancel,
          destructive: true,
        );
        if (!again || !mounted) return;
        force = true;
        continue;
      }
      showError(context, reason ?? failure);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final authState = ref.watch(authStateProvider).valueOrNull;
    final canManage = authState is AuthAuthenticated && authState.can({Capability.MANAGE_COMPANIES});
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: s.eyebrow,
            title: s.title,
            subtitle: s.subtitle,
            trailing: canManage
                ? FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.newCompany),
                  )
                : null,
          ),
          Expanded(child: _body(s, canManage: canManage)),
        ],
      ),
    );
  }

  Widget _body(_S s, {required bool canManage}) {
    if (_loading) {
      return LoadingState(message: s.p('Loading companies…', 'جارٍ تحميل الشركات…'));
    }
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return EmptyState(message: '${s.empty}\n${s.emptyHint}', actionLabel: s.newCompany, onAction: () => _openForm());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: IntesharSpacing.sm2),
        itemBuilder: (context, i) {
          final c = _items[i];
          final cs = Theme.of(context).colorScheme;
          return InkCard(
            ruleColor: context.tones.brand,
            // UX-135: `normal` IS the 16 this card was typing by hand.
            density: CardDensity.normal,
            onTap: _deleting.contains(c.id) ? null : () => _openForm(existing: c),
            child: Row(
              children: [
                Container(
                  width: 34,
                  alignment: Alignment.center,
                  child: Text('${c.displayOrder}',
                      style: IntesharType.mono(14, color: cs.onSurfaceVariant, w: FontWeight.w700)),
                ),
                const SizedBox(width: IntesharSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w800)),
                      if (c.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(c.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
                      ],
                      // UX-71: the effective cap, on the row. It was visible
                      // nowhere but inside this company's dialog, so a shop
                      // refused with a 429 sent the admin opening companies one
                      // by one to find which rule bit.
                      const SizedBox(height: IntesharSpacing.xs),
                      Row(children: [
                        Icon(
                          c.withdrawalCap > 0
                              ? Icons.speed_outlined
                              : Icons.all_inclusive,
                          size: 13,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: IntesharSpacing.xs),
                        Flexible(
                          child: Text(
                            c.withdrawalCap > 0
                                ? s.capRow(
                                    c.withdrawalCap,
                                    c.withdrawalWindowHours > 0
                                        ? c.withdrawalWindowHours
                                        : 24)
                                : s.capRowNone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: IntesharType.sans(12,
                                color: cs.onSurfaceVariant,
                                w: c.withdrawalCap > 0
                                    ? FontWeight.w700
                                    : FontWeight.w400),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                // UX-144: `cs.outline` is a hairline BORDER token — as pill text
                // on white it is 1.22:1, so "معطّل" was effectively invisible and
                // the only signal was the absence of green. Readable neutral, and
                // an icon so the state is not carried by colour alone.
                StampPill(
                  label: c.active ? s.active : s.inactive,
                  color: c.active ? context.status.success : cs.onSurfaceVariant,
                  icon: c.active ? Icons.check_circle_outline : Icons.cancel_outlined,
                  filled: false,
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    enabled: !_deleting.contains(c.id),
                    tooltip: s.rowMenu,
                    icon: _deleting.contains(c.id)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : null,
                    onSelected: (v) => v == 'edit' ? _openForm(existing: c) : _confirmDelete(c),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(s.edit)),
                      PopupMenuItem(value: 'delete', child: Text(s.delete)),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CompanyDialog extends StatefulWidget {
  final Company? existing;
  final CompanyRepository repo;
  const _CompanyDialog({required this.existing, required this.repo});

  @override
  State<_CompanyDialog> createState() => _CompanyDialogState();
}

class _CompanyDialogState extends State<_CompanyDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _logo = TextEditingController(text: widget.existing?.logoUrl ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _order =
      TextEditingController(text: (widget.existing?.displayOrder ?? 0).toString());
  late final TextEditingController _cap =
      TextEditingController(text: (widget.existing?.withdrawalCap ?? 0).toString());
  late final TextEditingController _window =
      TextEditingController(text: (widget.existing?.withdrawalWindowHours ?? 24).toString());
  late bool _active = widget.existing?.active ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _logo.dispose();
    _desc.dispose();
    _order.dispose();
    _cap.dispose();
    _window.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = _S.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = s.errName);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final base = widget.existing ?? const Company(name: '');
    final company = base.copyWith(
      name: _name.text.trim(),
      logoUrl: _logo.text.trim(),
      description: _desc.text.trim(),
      displayOrder: int.tryParse(_order.text.trim()) ?? 0,
      active: _active,
      withdrawalCap: int.tryParse(_cap.text.trim()) ?? 0,
      withdrawalWindowHours: int.tryParse(_window.text.trim()) ?? 24,
    );
    try {
      if (widget.existing != null) {
        await widget.repo.update(company);
      } else {
        await widget.repo.create(company);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e, context);
        });
      }
    }
  }

  /// UX-71: the per-shop selling limit, written as one sentence.
  ///
  /// The two numbers are the same two fields as before — `withdrawalCap` and
  /// `withdrawalWindowHours` — but inline in the rule they belong to, so
  /// neither can be read on its own. Underneath, a readout says in words what
  /// the pair currently means, because this is the control that decides whether
  /// a live POS sale is refused with a `429`.
  ///
  /// The backend counts per DRAWING ENTITY over a rolling window
  /// (`InventoryController.enforceWithdrawalCap`), which is what "each shop"
  /// and "in any N-hour window" are saying.
  Widget _capRule(_S s) {
    final cs = Theme.of(context).colorScheme;
    final cap = int.tryParse(_cap.text.trim()) ?? 0;
    final hours = int.tryParse(_window.text.trim()) ?? 24;
    Widget numberField(TextEditingController c, double width, String hint) =>
        SizedBox(
          width: width,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: IntesharType.mono(16, color: cs.onSurface, w: FontWeight.w800),
            decoration: InputDecoration(isDense: true, hintText: hint),
            // The readout below is the point of the control, so it has to move
            // with the digits rather than after a save.
            onChanged: (_) => setState(() {}),
          ),
        );
    final labelStyle =
        IntesharType.sans(14, color: cs.onSurface, w: IntesharWeight.semibold);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(s.capSection, padding: const EdgeInsets.only(bottom: 6)),
        Wrap(
          spacing: IntesharSpacing.sm,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(s.capLead, style: labelStyle),
            numberField(_cap, 86, '0'),
            Text(s.capMid, style: labelStyle),
            numberField(_window, 72, '24'),
            Text(s.capTail, style: labelStyle),
          ],
        ),
        const SizedBox(height: IntesharSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(cap <= 0 ? Icons.all_inclusive : Icons.speed_outlined,
                size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                cap <= 0
                    ? s.capUnlimited
                    : s.capReadout(cap, hours <= 0 ? 24 : hours),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? s.createTitle : s.editTitle),
      // Scroll + a responsive width so the stacked fields (and the restriction
      // editor, when editing) never overflow / push Save off a short phone (B-073).
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: s.name)),
            const SizedBox(height: IntesharSpacing.sm2),
            ImageUploadField(
              value: _logo.text.isEmpty ? null : _logo.text,
              label: s.logo,
              kind: 'agent-branding',
              onChanged: (u) => setState(() => _logo.text = u),
            ),
            const SizedBox(height: IntesharSpacing.sm2),
            TextField(controller: _desc, decoration: InputDecoration(labelText: s.description)),
            const SizedBox(height: IntesharSpacing.sm2),
            TextField(
              controller: _order,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.order),
            ),
            const SizedBox(height: IntesharSpacing.xs),
            const SizedBox(height: IntesharSpacing.sm2),
            _capRule(s),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.active),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (widget.existing != null) ...[
              const Divider(height: 20),
              _RestrictionEditor(companyId: widget.existing!.id, repo: widget.repo, s: s),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: IntesharSpacing.sm),
                // UX-127: was an off-scale 12.5 — a half-point step no screen
                // renders as distinct from `body`.
                child: Text(_error!,
                    style: IntesharText.body(
                        color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(s.cancel)),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(s.save),
        ),
      ],
    );
  }
}

/// B-058: per-agent restriction editor embedded in the company dialog. Lists the
/// agents this company is restricted for (each hides it for that agent + subtree),
/// with add (searchable AGENT1/AGENT2 picker) and remove.
class _RestrictionEditor extends ConsumerStatefulWidget {
  const _RestrictionEditor({required this.companyId, required this.repo, required this.s});
  final String companyId;
  final CompanyRepository repo;
  final _S s;

  @override
  ConsumerState<_RestrictionEditor> createState() => _RestrictionEditorState();
}

class _RestrictionEditorState extends ConsumerState<_RestrictionEditor> {
  List<String> _ids = const [];
  Map<String, String> _names = const {};
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ids = await widget.repo.restrictions(widget.companyId);
      final names = <String, String>{};
      final entRepo = EntityRepository(ref.read(apiClientProvider));
      for (final id in ids) {
        try {
          names[id] = (await entRepo.read(id)).meta.name;
        } catch (_) {
          names[id] = id;
        }
      }
      if (mounted) setState(() { _ids = ids; _names = names; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final picked = await showEntitySearchPicker(
      context,
      repository: EntityRepository(ref.read(apiClientProvider)),
      title: widget.s.addAgent,
      types: const [EntityType.AGENT1, EntityType.AGENT2],
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repo.setRestricted(companyId: widget.companyId, entityId: picked.id, restricted: true);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String id) async {
    setState(() => _busy = true);
    try {
      await widget.repo.setRestricted(companyId: widget.companyId, entityId: id, restricted: false);
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.s.restrictSection, style: IntesharType.sans(12, color: cs.onSurface, w: FontWeight.w700)),
      Text(widget.s.restrictHint, style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      if (_loading)
        const Padding(padding: EdgeInsets.all(6), child: LinearProgressIndicator())
      else ...[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in _ids)
              InputChip(
                label: Text(_names[id] ?? id, overflow: TextOverflow.ellipsis),
                onDeleted: _busy ? null : () => _remove(id),
              ),
          ],
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.block, size: 16),
          label: Text(widget.s.addAgent),
        ),
      ],
    ]);
  }
}
