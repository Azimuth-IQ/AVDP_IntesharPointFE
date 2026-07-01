import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/geo/governorate_picker.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/shared/widgets/working_hours_editor.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/stores/data/store_repository.dart';
import 'package:inteshar/features/stores/domain/pos_stats.dart';
import 'package:inteshar/features/stores/presentation/store_strings.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// Stores / POS management. Lists the STORE points under the logged-in entity and
/// drives the management actions (enable/disable, reset password, transfer balance,
/// edit, delete) + an Add-POS flow for agents. Backend authz: HQ or any ancestor.
class StoresPage extends ConsumerStatefulWidget {
  const StoresPage({super.key});

  @override
  ConsumerState<StoresPage> createState() => _StoresPageState();
}

class _StoresPageState extends ConsumerState<StoresPage> {
  List<Entity> _items = const [];
  bool _loading = true;
  Object? _error;

  StoreRepository get _repo => StoreRepository(ref.read(apiClientProvider));

  Entity? get _viewer {
    final a = ref.read(authStateProvider).valueOrNull;
    return a is AuthAuthenticated ? a.entity : null;
  }

  bool get _isHq => _viewer?.type == EntityType.INTESHAR;
  bool get _canAdd {
    final t = _viewer?.type;
    return t == EntityType.INTESHAR ||
        t == EntityType.AGENT1 ||
        t == EntityType.AGENT2;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final viewer = _viewer;
    if (viewer == null) {
      setState(() {
        _loading = false;
        _items = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stores = await _repo.listStores(viewer.id);
      if (!mounted) return;
      setState(() {
        _items = stores;
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

  Future<void> _openForm({String? editId}) async {
    final viewer = _viewer;
    if (viewer == null) return;
    Entity? existing;
    if (editId != null) {
      try {
        existing = await _repo.read(editId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
        }
        return;
      }
    }
    // An agent (AGENT1/AGENT2) parents a new POS under itself; HQ has no implicit
    // parent, so it must pick one of its descendant agents.
    List<Entity>? parentOptions;
    if (existing == null && _isHq) {
      try {
        parentOptions = await _repo.listParentAgents(viewer.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
        }
        return;
      }
      if (parentOptions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(StoreStrings.of(context).noParentAgents)),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final parentId = parentOptions?.first.id ?? existing?.parent ?? viewer.id;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StoreForm(
          parentId: parentId,
          existing: existing,
          parentOptions: parentOptions,
        ),
      ),
    );
    if (ok == true) _reload();
  }

  Future<void> _openDetail(Entity store) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StoreDetailSheet(
        store: store,
        isHq: _isHq,
        onChanged: _reload,
        onEdit: () {
          Navigator.pop(context);
          _openForm(editId: store.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreStrings.of(context);
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: s.pageEyebrow,
            title: s.pageTitle,
            subtitle: s.pageSubtitle,
            trailing: _canAdd
                ? FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.addPos),
                  )
                : null,
          ),
          Expanded(child: _buildBody(s)),
        ],
      ),
    );
  }

  Widget _buildBody(StoreStrings s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _reload);
    if (_items.isEmpty) {
      return EmptyState(
        message: '${s.empty}\n${s.emptyHint}',
        actionLabel: _canAdd ? s.addPos : null,
        onAction: _canAdd ? () => _openForm() : null,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _StoreCard(
          store: _items[i],
          s: s,
          onTap: () => _openDetail(_items[i]),
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final Entity store;
  final StoreStrings s;
  final VoidCallback onTap;
  const _StoreCard({required this.store, required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = s.ar ? 'ar' : 'en';
    final phone = store.users.isNotEmpty ? store.users.first.phone : '';
    final owner = store.profile?.ownerName ?? '';
    final govs = store.meta.governorates;
    return InkCard(
      ruleColor: store.active ? IntesharColors.saffron : cs.outline,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  store.meta.name.isEmpty ? store.id : store.meta.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(
                    17,
                    color: cs.onSurface,
                    w: FontWeight.w800,
                  ),
                ),
              ),
              StampPill(
                label: store.active ? s.active : s.disabled,
                color: store.active ? IntesharColors.sage : cs.outline,
              ),
            ],
          ),
          if (owner.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    owner,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.phone_outlined,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  phone,
                  style: IntesharType.mono(12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.place_outlined,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  govs.isEmpty
                      ? s.noRegion
                      : governorateLabel(govs.first, locale),
                  style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom-sheet detail + actions for one point.
class StoreDetailSheet extends ConsumerStatefulWidget {
  final Entity store;
  final bool isHq;
  final VoidCallback onChanged;
  final VoidCallback onEdit;
  const StoreDetailSheet({
    super.key,
    required this.store,
    required this.isHq,
    required this.onChanged,
    required this.onEdit,
  });

  @override
  ConsumerState<StoreDetailSheet> createState() => _StoreDetailSheetState();
}

class _StoreDetailSheetState extends ConsumerState<StoreDetailSheet> {
  late bool _active = widget.store.active;

  /// The signed-in viewer's entity id — the would-be granting parent.
  String get _viewerId {
    final a = ref.read(authStateProvider).valueOrNull;
    return a is AuthAuthenticated ? a.entity.id : '';
  }

  PosStats? _stats;
  bool _busy = false;

  StoreRepository get _repo => StoreRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final st = await _repo.posStats(widget.store.id);
      if (mounted) setState(() => _stats = st);
    } catch (_) {
      // Stats are best-effort; the actions still work without them.
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleActive(StoreStrings s) async {
    setState(() => _busy = true);
    try {
      final next = !_active;
      await _repo.setActive(widget.store.id, next);
      if (!mounted) return;
      setState(() {
        _active = next;
        _busy = false;
      });
      _toast(next ? s.activated : s.deactivated);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(friendlyError(e, context));
      }
    }
  }

  Future<void> _resetPassword(StoreStrings s) async {
    final phone = widget.store.users.isNotEmpty
        ? widget.store.users.first.phone
        : '';
    if (phone.isEmpty) return;
    final pass = await _promptText(
      s.resetPassword,
      s.newPassword,
      obscure: true,
    );
    if (pass == null || pass.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _repo.resetPassword(widget.store.id, phone, pass.trim());
      if (mounted) setState(() => _busy = false);
      _toast(s.passwordReset);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(friendlyError(e, context));
      }
    }
  }

  Future<void> _transfer(StoreStrings s) async {
    final raw = await _promptText(s.transfer, s.amount, number: true);
    final amount = num.tryParse(raw?.trim() ?? '');
    if (amount == null || amount <= 0) return;
    setState(() => _busy = true);
    final pricing = PricingRepository(ref.read(apiClientProvider));
    try {
      // Client-side guard: the backend grant does not debit, so cap the amount at
      // the GRANTOR's (logged-in viewer's) available balance. The transfer ADDS
      // balance to the store, so gating on the store's own balance would be wrong
      // (a zero-balance store could never be topped up).
      final auth = ref.read(authStateProvider).valueOrNull;
      final grantorId = auth is AuthAuthenticated ? auth.entity.id : null;
      final avail = grantorId != null
          ? (await pricing.balance(entityId: grantorId)).available
          : null;
      if (avail != null && amount > avail) {
        if (mounted) setState(() => _busy = false);
        _toast(s.insufficientBalance);
        return;
      }
      await pricing.grant(destId: widget.store.id, amount: amount);
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(s.transferred);
      _loadStats();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(friendlyError(e, context));
      }
    }
  }

  Future<void> _delete(StoreStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          s.deleteTitle(
            widget.store.meta.name.isEmpty
                ? widget.store.id
                : widget.store.meta.name,
          ),
        ),
        content: Text(s.deleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(widget.store.id);
      widget.onChanged();
      if (mounted) Navigator.pop(context);
      _toast(s.deleted);
    } catch (e) {
      if (mounted) _toast(friendlyError(e, context));
    }
  }

  Future<String?> _promptText(
    String title,
    String label, {
    bool obscure = false,
    bool number = false,
  }) {
    final ctrl = TextEditingController();
    final s = StoreStrings.of(context);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: obscure,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  String _fmtTs(String? iso, StoreStrings s) {
    if (iso == null || iso.isEmpty) return s.never;
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreStrings.of(context);
    final cs = Theme.of(context).colorScheme;
    final st = _stats;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.store.meta.name.isEmpty
                        ? widget.store.id
                        : widget.store.meta.name,
                    style: IntesharType.serif(
                      20,
                      color: cs.onSurface,
                      w: FontWeight.w800,
                    ),
                  ),
                ),
                StampPill(
                  label: _active ? s.active : s.disabled,
                  color: _active ? IntesharColors.sage : cs.outline,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Stat(
                  label: s.balance,
                  value: (st?.balanceAvailable ?? 0).toStringAsFixed(0),
                ),
                _Stat(label: s.available, value: '${st?.availableCount ?? 0}'),
                _Stat(label: s.sold, value: '${st?.printedCount ?? 0}'),
              ],
            ),
            const SizedBox(height: 14),
            _kv(cs, s.lastSeen, _fmtTs(st?.lastSeenAt, s)),
            if ((st?.lastDeviceModel ?? '').isNotEmpty)
              _kv(cs, s.device, st!.lastDeviceModel!),
            if ((st?.lastAppVersion ?? '').isNotEmpty)
              _kv(cs, s.appVersion, st!.lastAppVersion!),
            const SizedBox(height: 18),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _toggleActive(s),
                  icon: Icon(
                    _active ? Icons.block : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(_active ? s.deactivate : s.activate),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _resetPassword(s),
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: Text(s.resetPassword),
                ),
                // Balance grants are DIRECT-parent → DIRECT-child only (BRD): only the
                // store's immediate parent (its Sub-Agent) may transfer balance to it. For
                // an HQ/Main-Agent viewer the store is not a direct child, so this is hidden.
                if (widget.store.parent == _viewerId)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _transfer(s),
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                    ),
                    label: Text(s.transfer),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : widget.onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(s.edit),
                ),
                if (widget.isHq)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    onPressed: _busy ? null : () => _delete(s),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(s.delete),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(ColorScheme cs, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(
          '$k: ',
          style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
        ),
        Expanded(
          child: Text(
            v,
            style: IntesharType.sans(
              12.5,
              color: cs.onSurface,
              w: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: IntesharType.display(22, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(label, style: IntesharType.overline(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Create / edit a POS point. Create produces a STORE with a single operator
/// (USER) under [parentId]; edit updates name / owner / region / landmark.
class StoreForm extends ConsumerStatefulWidget {
  final String parentId;
  final Entity? existing;

  /// When non-empty (HQ creating a POS), the operator must pick the parent agent
  /// from these descendant AGENT1/AGENT2 entities; [parentId] is the default.
  final List<Entity>? parentOptions;
  const StoreForm({
    super.key,
    required this.parentId,
    this.existing,
    this.parentOptions,
  });

  @override
  ConsumerState<StoreForm> createState() => _StoreFormState();
}

class _StoreFormState extends ConsumerState<StoreForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _owner;
  late final TextEditingController _phone;
  late final TextEditingController _password;
  late final TextEditingController _landmark;
  String? _gov;
  WorkingHours? _workingHours;
  late String _parentId;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  bool get _showParentPicker =>
      !_isEdit && (widget.parentOptions?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _parentId = widget.parentId;
    final e = widget.existing;
    _name = TextEditingController(text: e?.meta.name ?? '');
    _owner = TextEditingController(text: e?.profile?.ownerName ?? '');
    _phone = TextEditingController(
      text: e != null && e.users.isNotEmpty ? e.users.first.phone : '',
    );
    _password = TextEditingController();
    _landmark = TextEditingController(text: e?.profile?.nearestLandmark ?? '');
    _gov = (e?.meta.governorates.isNotEmpty ?? false)
        ? e!.meta.governorates.first
        : null;
    _workingHours = e?.meta.workingHours;
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _phone.dispose();
    _password.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _save(StoreStrings s) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = StoreRepository(ref.read(apiClientProvider));
    final govs = _gov == null ? const <String>[] : <String>[_gov!];
    try {
      if (_isEdit) {
        final e = widget.existing!;
        final updated = e.copyWith(
          meta: e.meta.copyWith(
            name: _name.text.trim(),
            governorates: govs,
            workingHours: _workingHours,
          ),
          profile: (e.profile ?? const EntityProfile()).copyWith(
            ownerName: _owner.text.trim(),
            nearestLandmark: _landmark.text.trim(),
          ),
        );
        await repo.update(updated);
      } else {
        final store = Entity(
          id: 'store-${DateTime.now().millisecondsSinceEpoch}',
          type: EntityType.STORE,
          parent: _parentId,
          meta: EntityMeta(
            name: _name.text.trim(),
            governorates: govs,
            workingHours: _workingHours,
          ),
          profile: EntityProfile(
            ownerName: _owner.text.trim(),
            nearestLandmark: _landmark.text.trim(),
            contactPhone: _phone.text.trim(),
          ),
          users: [
            EntityUser(
              phone: _phone.text.trim(),
              password: _password.text,
              role: UserRole.USER,
            ),
          ],
        );
        await repo.createStore(store);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_isEdit ? s.updated : s.created)));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = StoreStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? s.formEditTitle : s.formNewTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_showParentPicker) ...[
              DropdownButtonFormField<String>(
                initialValue: _parentId,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.parentAgent),
                items: widget.parentOptions!
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.id,
                        child: Text(
                          '${a.meta.name.isEmpty ? a.id : a.meta.name} (${a.type.label})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _parentId = v ?? _parentId),
                validator: (v) => (v == null || v.isEmpty) ? s.required : null,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: s.shopName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? s.required : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _owner,
              decoration: InputDecoration(labelText: s.ownerName),
            ),
            const SizedBox(height: 14),
            if (!_isEdit) ...[
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: InputDecoration(labelText: s.loginPhone),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return s.required;
                  if (!RegExp(r'^07\d{9}$').hasMatch(t)) {
                    return s.ar
                        ? 'رقم هاتف غير صحيح (مثال 07XXXXXXXXX)'
                        : 'Invalid phone (e.g. 07XXXXXXXXX)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: s.password),
                validator: (v) {
                  if (v == null || v.isEmpty) return s.required;
                  if (v.length < 6) {
                    return s.ar
                        ? 'كلمة المرور 6 أحرف على الأقل'
                        : 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
            ],
            GovernorateDropdown(
              value: _gov,
              labelText: s.region,
              noneLabel: s.noRegion,
              onChanged: (v) => setState(() => _gov = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _landmark,
              decoration: InputDecoration(labelText: s.landmark),
            ),
            const SizedBox(height: 20),
            WorkingHoursEditor(
              value: _workingHours,
              onChanged: (v) => setState(() => _workingHours = v),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : () => _save(s),
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(s.save),
            ),
          ],
        ),
      ),
    );
  }
}
