import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

String _tr(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;

/// HQ "Supervisors" management (spec الادمن r7): the platform admin creates extra HQ
/// login users scoped to dashboard sections via capabilities. Uses the single-user
/// endpoints (add/update/remove) which avoid the full-entity-PUT childrenIds bug.
class HqUsersPage extends ConsumerStatefulWidget {
  const HqUsersPage({super.key});

  @override
  ConsumerState<HqUsersPage> createState() => _HqUsersPageState();
}

class _HqUsersPageState extends ConsumerState<HqUsersPage> {
  List<EntityUser>? _users;
  bool _loading = true;
  Object? _error;
  String _entityId = '';

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is AuthAuthenticated) {
      _entityId = auth.entity.id;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users =
          await EntityRepository(ref.read(apiClientProvider)).listUsers(_entityId);
      if (mounted) {
        setState(() {
          _users = users;
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

  Future<void> _openForm({EntityUser? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _UserFormSheet(entityId: _entityId, existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(EntityUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr(ctx, 'إزالة المستخدم', 'Remove user')),
        content: Text(_tr(ctx, 'إزالة ${u.phone}؟', 'Remove ${u.phone}?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr(ctx, 'إزالة', 'Remove'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EntityRepository(ref.read(apiClientProvider))
          .removeUser(_entityId, u.phone);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _resetTotp(EntityUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr(ctx, 'إعادة تعيين المصادقة الثنائية', 'Reset 2FA')),
        content: Text(_tr(
            ctx,
            'سيُطلب من ${u.phone} ربط تطبيق المصادقة من جديد عند تسجيل الدخول التالي.',
            'Will require ${u.phone} to re-enroll an authenticator on next login.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr(ctx, 'إعادة تعيين', 'Reset'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EntityRepository(ref.read(apiClientProvider)).resetUserTotp(u.phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                _tr(context, 'تمت إعادة تعيين المصادقة الثنائية', '2FA reset'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: _tr(context, 'الادمن', 'Admin'),
            title: _tr(context, 'المستخدمون / المشرفون', 'Users & supervisors'),
            subtitle: _tr(
                context,
                'أنشئ حسابات بصلاحيات محددة لمتابعة أقسام لوحة التحكم',
                'Create accounts scoped to specific dashboard sections'),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: Text(_tr(context, 'إضافة مشرف', 'Add supervisor')),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final u = _users;
    if (u == null || u.isEmpty) {
      return EmptyState(
          message: _tr(context, 'لا يوجد مستخدمون بعد', 'No users yet'));
    }
    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
      itemCount: u.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _UserCard(
        user: u[i],
        onEdit: () => _openForm(existing: u[i]),
        onRemove: () => _remove(u[i]),
        onResetTotp: () => _resetTotp(u[i]),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final EntityUser user;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onResetTotp;
  const _UserCard(
      {required this.user,
      required this.onEdit,
      required this.onRemove,
      required this.onResetTotp});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    final caps = user.capabilities;
    final full = caps.isEmpty || caps.contains(Capability.AGENT_ADMIN);
    return InkCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: monoText(user.phone,
                  size: 14, color: cs.onSurface, w: FontWeight.w800),
            ),
            IconButton(
                tooltip: _tr(context, 'إعادة تعيين 2FA', 'Reset 2FA'),
                onPressed: onResetTotp,
                icon: const Icon(Icons.lock_reset, size: 18)),
            IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18)),
            IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.delete_outline, size: 18, color: cs.error)),
          ]),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: full
                ? [
                    _chip(
                        context,
                        _tr(context, 'وصول كامل', 'Full access'),
                        IntesharColors.saffronDeep)
                  ]
                : caps
                    .map((c) => _chip(context, c.label(loc), cs.primary))
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext c, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: IntesharType.sans(11.5, color: color, w: FontWeight.w700)),
      );
}

class _UserFormSheet extends ConsumerStatefulWidget {
  final String entityId;
  final EntityUser? existing;
  const _UserFormSheet({required this.entityId, this.existing});

  @override
  ConsumerState<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends ConsumerState<_UserFormSheet> {
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  final _password = TextEditingController();
  late final Set<Capability> _caps = {...(widget.existing?.capabilities ?? const {})};
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = _tr(context, 'أدخل رقم الهاتف', 'Enter a phone'));
      return;
    }
    if (!_isEdit && _password.text.trim().isEmpty) {
      setState(() =>
          _error = _tr(context, 'أدخل كلمة مرور', 'Enter a password'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = EntityRepository(ref.read(apiClientProvider));
      if (_isEdit) {
        await repo.updateUser(
            phone: phone, role: UserRole.ADMIN, capabilities: _caps);
      } else {
        await repo.addUser(
          entityId: widget.entityId,
          phone: phone,
          password: _password.text.trim(),
          role: UserRole.ADMIN,
          capabilities: _caps,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit
                  ? _tr(context, 'تعديل الصلاحيات', 'Edit capabilities')
                  : _tr(context, 'مشرف جديد', 'New supervisor'),
              style: IntesharType.display(20, color: cs.onSurface, w: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              enabled: !_isEdit,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                  labelText: _tr(context, 'رقم الهاتف', 'Phone'),
                  hintText: '07700000000'),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: InputDecoration(
                    labelText: _tr(context, 'كلمة المرور المبدئية',
                        'Initial password')),
              ),
              const SizedBox(height: 4),
              Text(
                _tr(context, 'سيُطلب منه تغييرها عند أول تسجيل دخول',
                    'They will be asked to change it on first login'),
                style: IntesharType.sans(11.5, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            Text(_tr(context, 'الصلاحيات', 'Capabilities'),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: FontWeight.w700)),
            const SizedBox(height: 4),
            ...Capability.values.map((c) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _caps.contains(c),
                  title: Text(c.label(loc),
                      style: IntesharType.sans(13.5, color: cs.onSurface)),
                  subtitle: c == Capability.AGENT_ADMIN
                      ? Text(
                          _tr(context, 'وصول كامل لكل الأقسام',
                              'Full access to every section'),
                          style: IntesharType.sans(11, color: cs.onSurfaceVariant))
                      : null,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _caps.add(c);
                    } else {
                      _caps.remove(c);
                    }
                  }),
                )),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_tr(context, 'حفظ', 'Save')),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
