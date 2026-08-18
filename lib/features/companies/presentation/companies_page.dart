import 'package:flutter/material.dart';
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
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
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
  String get logo => p('Logo URL (optional)', 'رابط الشعار (اختياري)');
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
  String get cap => p('Withdrawal cap per shop (0 = unlimited)', 'حد السحب لكل نقطة (0 = بلا حد)');
  String get window => p('Window (hours)', 'المدة (ساعات)');
  String get restrictSection => p('Restrict for agents', 'تقييد لوكلاء');
  String get restrictHint => p('Hidden for the chosen agent and everything under it.', 'يُخفى عن الوكيل المحدد وكل ما تحته.');
  String get addAgent => p('Add agent', 'إضافة وكيل');
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
    if (ok == true) _load();
  }

  Future<void> _confirmDelete(Company c) async {
    final s = _S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTitle),
        content: Text(s.deleteBody(c.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runDelete(s, c, force: false);
  }

  /// The server refuses while the company still has categories and says how many.
  /// That count is the thing worth confirming — the generic warning above cannot
  /// know it — so the refusal becomes a second, specific prompt rather than an
  /// error the operator has to interpret.
  Future<void> _runDelete(_S s, Company c, {required bool force}) async {
    try {
      await _repo.delete(c.id, force: force);
      _load();
    } catch (e) {
      if (!mounted) return;
      final reason = serverReason(e);
      if (!force && reason != null && ApiException.from(e)?.statusCode == 409) {
        final again = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.deleteTitle),
            content: Text(reason),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(s.cancel)),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.deleteAnyway),
              ),
            ],
          ),
        );
        if (again == true) await _runDelete(s, c, force: true);
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(reason ?? friendlyError(e, context))));
      }
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return EmptyState(message: '${s.empty}\n${s.emptyHint}', actionLabel: s.newCompany, onAction: () => _openForm());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final c = _items[i];
          final cs = Theme.of(context).colorScheme;
          return InkCard(
            ruleColor: context.tones.brand,
            padding: const EdgeInsets.all(16),
            onTap: () => _openForm(existing: c),
            child: Row(
              children: [
                Container(
                  width: 34,
                  alignment: Alignment.center,
                  child: Text('${c.displayOrder}',
                      style: IntesharType.mono(13, color: cs.onSurfaceVariant, w: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
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
                            style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                StampPill(
                  label: c.active ? s.active : s.inactive,
                  color: c.active ? IntesharColors.sage : cs.outline,
                  filled: false,
                ),
                if (canManage)
                  PopupMenuButton<String>(
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
            const SizedBox(height: 10),
            ImageUploadField(
              value: _logo.text.isEmpty ? null : _logo.text,
              label: s.logo,
              kind: 'agent-branding',
              onChanged: (u) => setState(() => _logo.text = u),
            ),
            const SizedBox(height: 10),
            TextField(controller: _desc, decoration: InputDecoration(labelText: s.description)),
            const SizedBox(height: 10),
            TextField(
              controller: _order,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.order),
            ),
            const SizedBox(height: 4),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cap,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: s.cap),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _window,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: s.window),
                ),
              ),
            ]),
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
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5)),
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
      Text(widget.s.restrictSection, style: IntesharType.sans(12.5, color: cs.onSurface, w: FontWeight.w700)),
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
