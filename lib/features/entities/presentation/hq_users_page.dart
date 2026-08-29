import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/confirm_code_dialog.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/password_field.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/sheet_frame.dart';

String _tr(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;

/// Short bilingual description of what a capability grants, shown under its
/// checkbox in the supervisor form. Returns null for caps that need no hint.
String? _capHint(BuildContext c, Capability cap) => switch (cap) {
      Capability.AGENT_ADMIN =>
        _tr(c, 'وصول كامل لكل الأقسام', 'Full access to every section'),
      Capability.MANAGE_CATALOG =>
        _tr(c, 'المنتجات والقوالب والإضافة بالجملة',
            'Products, templates & batch import'),
      Capability.MANAGE_AGENTS =>
        _tr(c, 'الوكلاء والكيانات والمتاجر', 'Agents, entities & stores'),
      Capability.MANAGE_COMPANIES => _tr(c, 'كتالوج الشركات', 'Companies catalog'),
      _ => null,
    };

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
  List<EntityUser>? _archived;
  bool _loading = true;
  Object? _error;
  String _entityId = '';

  /// UX-156: the archive is a segment of THIS screen, not a separate
  /// destination. Someone who just archived a user looks for it here.
  bool _showArchive = false;

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
      final repo = EntityRepository(ref.read(apiClientProvider));
      // Both lists every time: the segment control shows the archive count, and
      // archiving moves a row from one list to the other.
      final users = await repo.listUsers(_entityId);
      final archived = await repo.listArchivedUsers(_entityId);
      if (mounted) {
        setState(() {
          _users = users;
          _archived = archived;
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

  /// Archives a user (UX-156).
  ///
  /// The customer asked whether deleting a user moves it somewhere or cancels it
  /// for good. The dialog answers that in words before anything happens, because
  /// the previous prompt ("Remove 07…?") described an irreversible delete and
  /// performed one.
  Future<void> _archive(EntityUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.inventory_2_outlined, color: cs.error),
          title: Text(_tr(ctx, 'أرشفة المستخدم', 'Archive user')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tr(
                ctx,
                'سيتوقف ${u.phone} عن تسجيل الدخول فوراً وينتقل إلى الأرشيف. '
                    'لا يُحذف الحساب — يمكنك إعادة تفعيله لاحقاً بنفس كلمة المرور.',
                '${u.phone} stops being able to sign in immediately and moves to '
                    'the archive. The account is not deleted — you can restore it '
                    'later with the same password.',
              )),
              const SizedBox(height: IntesharSpacing.md),
              // The number staying taken is the surprise worth stating up front:
              // it is the one thing an admin will try to do next and be refused.
              Text(
                _tr(
                  ctx,
                  'يبقى رقم الهاتف محجوزاً لهذا الحساب ولا يمكن استخدامه لمستخدم جديد.',
                  'The phone number stays reserved for this account and cannot be '
                      'reused for a new user.',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_tr(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr(ctx, 'أرشفة', 'Archive')),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;

    // Same class of action as revoking a POS: it takes someone's login away.
    final code = await showConfirmCodeDialog(
      context,
      title: _tr(context, 'تأكيد الأرشفة', 'Confirm archiving'),
      warning: _tr(
        context,
        'سيتم إيقاف دخول ${u.phone} ونقله إلى الأرشيف.',
        '${u.phone} will be signed out and moved to the archive.',
      ),
      confirmLabel: _tr(context, 'أرشفة', 'Archive'),
    );
    if (code == null || !mounted) return;
    try {
      await EntityRepository(ref.read(apiClientProvider))
          .archiveUser(_entityId, u.phone, totp: code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_tr(context, 'تمت الأرشفة', 'User archived'))));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(serverReason(e) ?? friendlyError(e, context))));
      }
    }
  }

  /// Brings an archived user back into service.
  Future<void> _restore(EntityUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.restore_outlined, color: cs.primary),
          title: Text(_tr(ctx, 'إعادة تفعيل المستخدم', 'Restore user')),
          content: Text(_tr(
            ctx,
            'سيتمكن ${u.phone} من تسجيل الدخول بنفس كلمة المرور وتطبيق المصادقة '
                'كما كان، وتعود صلاحياته كما هي.',
            '${u.phone} will be able to sign in with the same password and '
                'authenticator as before, with their capabilities unchanged.',
          )),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_tr(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_tr(ctx, 'إعادة تفعيل', 'Restore'))),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await EntityRepository(ref.read(apiClientProvider))
          .restoreUser(_entityId, u.phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_tr(context, 'تمت إعادة التفعيل', 'User restored'))));
      }
      _load();
    } catch (e) {
      if (mounted) {
        // Prefer the server's words: "AGENT2 may have at most 1 user(s)" is the
        // answer, and a generic failure would leave the admin guessing.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(serverReason(e) ?? friendlyError(e, context))));
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
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
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
            child: Column(
              children: [
                if (!_showArchive)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: Text(_tr(context, 'إضافة مشرف', 'Add supervisor')),
                    ),
                  ),
                const SizedBox(height: IntesharSpacing.sm2),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        icon: const Icon(Icons.people_outline, size: 16),
                        label: Text(_tr(context, 'النشطون', 'Active')),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: const Icon(Icons.inventory_2_outlined, size: 16),
                        // The count is on the tab: an archive you cannot tell is
                        // empty is one nobody opens.
                        label: Text(_archived == null || _archived!.isEmpty
                            ? _tr(context, 'الأرشيف', 'Archived')
                            : _tr(context, 'الأرشيف (${_archived!.length})',
                                'Archived (${_archived!.length})')),
                      ),
                    ],
                    selected: {_showArchive},
                    onSelectionChanged: (v) =>
                        setState(() => _showArchive = v.first),
                  ),
                ),
              ],
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
    if (_showArchive) {
      final a = _archived ?? const <EntityUser>[];
      if (a.isEmpty) {
        return EmptyState(
            message: _tr(context, 'لا يوجد مستخدمون مؤرشفون',
                'No archived users'));
      }
      return ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
        itemCount: a.length,
        separatorBuilder: (_, _) => const SizedBox(height: IntesharSpacing.sm2),
        itemBuilder: (_, i) =>
            _ArchivedUserCard(user: a[i], onRestore: () => _restore(a[i])),
      );
    }
    final u = _users;
    if (u == null || u.isEmpty) {
      return EmptyState(
          message: _tr(context, 'لا يوجد مستخدمون بعد', 'No users yet'));
    }
    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
      itemCount: u.length,
      separatorBuilder: (_, _) => const SizedBox(height: IntesharSpacing.sm2),
      itemBuilder: (_, i) => _UserCard(
        user: u[i],
        onEdit: () => _openForm(existing: u[i]),
        onRemove: () => _archive(u[i]),
        onResetTotp: () => _resetTotp(u[i]),
      ),
    );
  }
}

/// A retired account: who it was, when it was archived and by whom, and the one
/// action that applies to it.
class _ArchivedUserCard extends StatelessWidget {
  final EntityUser user;
  final VoidCallback onRestore;
  const _ArchivedUserCard({required this.user, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final when = user.archivedAt?.toLocal().toString().substring(0, 16) ?? '';
    return InkCard(
      ruleColor: cs.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: monoText(user.phone,
                  size: 14, color: cs.onSurfaceVariant, w: FontWeight.w800),
            ),
            // UX-127: this asked for 10, which is on no scale — and StampPill
            // has clamped to its 12 floor since UX-142, so the argument only
            // ever misdescribed what shipped.
            StampPill(
              label: _tr(context, 'مؤرشف', 'Archived'),
              color: cs.onSurfaceVariant,
            ),
          ]),
          if (when.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              user.archivedBy.isEmpty
                  ? _tr(context, 'أُرشف في $when', 'Archived $when')
                  : _tr(context, 'أُرشف في $when بواسطة ${user.archivedBy}',
                      'Archived $when by ${user.archivedBy}'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: IntesharSpacing.sm2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: Key('restore-user-${user.phone}'),
              onPressed: onRestore,
              icon: const Icon(Icons.restore_outlined, size: 16),
              label: Text(_tr(context, 'إعادة تفعيل', 'Restore')),
            ),
          ),
        ],
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
            // UX-150: three bare glyphs in a row, one of them an unrecoverable
            // delete, and only the first was named. A tooltip is the only label
            // an icon-only control ever gets.
            IconButton(
                tooltip: _tr(context, 'تعديل المستخدم', 'Edit user'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18)),
            IconButton(
                tooltip: _tr(context, 'أرشفة المستخدم', 'Archive user'),
                onPressed: onRemove,
                icon: Icon(Icons.inventory_2_outlined, size: 18, color: cs.error)),
          ]),
          const SizedBox(height: IntesharSpacing.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: full
                ? [
                    _chip(
                        context,
                        _tr(context, 'وصول كامل', 'Full access'),
                        context.tones.brandInk)
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
        padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.sm2, vertical: IntesharSpacing.xs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(IntesharRadii.pill),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: IntesharType.sans(12, color: color, w: FontWeight.w700)),
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
          _error = friendlyError(e, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    // UX-131: this sheet had NO grab handle while still being drag-dismissible,
    // and hand-rolled its own title, keyboard inset and (missing) height cap.
    return SheetFrame(
      title: _isEdit
          ? _tr(context, 'تعديل الصلاحيات', 'Edit capabilities')
          : _tr(context, 'مشرف جديد', 'New supervisor'),
      footer: SizedBox(
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
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _phone,
              enabled: !_isEdit,
              keyboardType: TextInputType.phone,
              // UX-12: Enter moves to the password instead of doing nothing.
              // Deliberately NOT a submit: the capability toggles come after
              // this pair, and saving from here would create the supervisor
              // before anyone had chosen what they may do.
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: _tr(context, 'رقم الهاتف', 'Phone'),
                hintText: '07700000000',
                // A greyed-out field with no reason reads as a bug. It is also
                // not merely "locked": the phone identifies the stored user, so
                // editing it would strand the account's credentials.
                helperText: _isEdit
                    ? _tr(
                        context,
                        'رقم الهاتف هو اسم الدخول ولا يمكن تغييره.',
                        'The phone is the login and cannot be changed.',
                      )
                    : null,
                helperMaxLines: 2,
              ),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: IntesharSpacing.md),
              // Masked: this is typed in an office, frequently with the new
              // supervisor (or anyone else) standing over the shoulder.
              PasswordField(
                controller: _password,
                label: _tr(context, 'كلمة المرور المبدئية', 'Initial password'),
              ),
              const SizedBox(height: IntesharSpacing.xs),
              Text(
                _tr(context, 'سيُطلب منه تغييرها عند أول تسجيل دخول',
                    'They will be asked to change it on first login'),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: IntesharSpacing.lg),
            Text(_tr(context, 'الصلاحيات', 'Capabilities'),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: FontWeight.w700)),
            const SizedBox(height: IntesharSpacing.xs),
            ...Capability.values.map((c) {
              final hint = _capHint(context, c);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _caps.contains(c),
                title: Text(c.label(loc),
                    style: IntesharType.sans(14, color: cs.onSurface)),
                subtitle: hint == null
                    ? null
                    : Text(hint,
                        style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _caps.add(c);
                  } else {
                    _caps.remove(c);
                  }
                }),
              );
            }),
            if (_error != null) ...[
              const SizedBox(height: IntesharSpacing.sm),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ],
        ),
    );
  }
}
