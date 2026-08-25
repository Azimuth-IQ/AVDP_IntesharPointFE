import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/password_field.dart';

/// "Delete N users" in Arabic, which does not simply take a number and a plural:
/// two is its own dual form, 3–10 take the plural, and 11+ go back to the
/// singular accusative. Getting this wrong is small but reads as machine output
/// in a confirmation people are meant to trust.
String arDeleteUsersCount(int n) {
  if (n == 1) return 'حذف مستخدم';
  if (n == 2) return 'حذف مستخدمين';
  if (n <= 10) return 'حذف $n مستخدمين';
  return 'حذف $n مستخدماً';
}

class ManageUsersSheet extends StatefulWidget {
  final Entity entity;
  final Future<void> Function(List<EntityUser> users) onSave;
  // Manage EXISTING users in place (the tree is the single management surface):
  final Future<void> Function(String phone, String newPassword) onResetPassword;
  final Future<void> Function(String phone) onResetTotp;

  const ManageUsersSheet({
    super.key,
    required this.entity,
    required this.onSave,
    required this.onResetPassword,
    required this.onResetTotp,
  });

  @override
  State<ManageUsersSheet> createState() => _ManageUsersSheetState();
}

class _ManageUsersSheetState extends State<ManageUsersSheet> {
  late List<EntityUser> _users;
  /// Phones of existing users marked for deletion, committed only on save.
  final Set<String> _pendingRemoval = {};
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  UserRole _selectedRole = UserRole.ADMIN;
  bool _obscurePass = true;
  bool _saving = false;
  String? _addError;

  @override
  void initState() {
    super.initState();
    _users = List.of(widget.entity.users);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// UX-96: **ADMIN only, on every tier.**
  ///
  /// A shop used to offer `USER` here as well, and it was the closest thing in
  /// the app to a "create the shop's operator" button. But a POS operator is a
  /// user with `isPos == true`, and only the quota-gated POS onboarding flow can
  /// set that flag — so the account this produced could not sell, and the POS
  /// admin screen went on reporting "This shop has no POS user". The one flow
  /// that looked like POS onboarding was the one that wasn't.
  List<UserRole> get _allowedRoles => const [UserRole.ADMIN];

  /// Says where the operator account actually comes from, on the tier where
  /// someone would look for it here.
  bool get _isStore => widget.entity.type == EntityType.STORE;

  /// True when the new-user sub-form has been typed into but not committed.
  /// Creating a login is why people open this sheet, so a draft this far along
  /// is an intention, not leftovers.
  bool get _hasDraft =>
      _phoneCtrl.text.trim().isNotEmpty || _passCtrl.text.trim().isNotEmpty;

  /// Validates the sub-form and appends the user to [_users]. Returns false and
  /// leaves [_addError] set when the draft cannot be accepted, so a caller can
  /// stop rather than carry on past a half-typed login.
  bool _tryAddUser() {
    final l = AppLocalizations.of(context)!;
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (phone.isEmpty) {
      setState(() => _addError = l.manageUsersPhoneRequired);
      return false;
    }
    if (pass.isEmpty) {
      setState(() => _addError = l.manageUsersPasswordRequired);
      return false;
    }
    if (!RegExp(r'^07\d{9}$').hasMatch(phone)) {
      setState(() => _addError = l.invalidPhone);
      return false;
    }
    if (pass.length < 6) {
      setState(() => _addError = l.passwordTooShort);
      return false;
    }
    if (_users.any((u) => u.phone == phone)) {
      setState(() => _addError = l.manageUsersPhoneDuplicate);
      return false;
    }

    final id = 'u-$phone-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _users.add(
        EntityUser(id: id, phone: phone, password: pass, role: _selectedRole),
      );
      _addError = null;
    });
    _phoneCtrl.clear();
    _passCtrl.clear();
    return true;
  }

  /// True when this user already exists on the server, so dropping them is a
  /// real deletion rather than discarding an unsaved row.
  bool _isPersisted(EntityUser u) =>
      widget.entity.users.any((x) => x.phone == u.phone);

  /// The users that would exist after a save — [_users] less anything marked
  /// for removal. Everything that asks "how many users will be left" must go
  /// through this and not [_users].
  List<EntityUser> get _effectiveUsers =>
      _users.where((u) => !_pendingRemoval.contains(u.phone)).toList();

  void _removeUser(EntityUser u) {
    // A row that was never saved has no server side to delete: dropping it is
    // free and reversible by re-typing, so it just goes.
    if (!_isPersisted(u)) {
      setState(
        () => _users.removeWhere((x) => x.id == u.id && x.phone == u.phone),
      );
      return;
    }
    // A real user is only MARKED here. Vanishing on tap read as "done" while
    // the deletion actually happened later at Save, so the operator never got
    // a chance to object to something irreversible.
    setState(() => _pendingRemoval.add(u.phone));
  }

  void _undoRemove(EntityUser u) {
    setState(() => _pendingRemoval.remove(u.phone));
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resetPassword(EntityUser u) async {
    final ctrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _ar ? 'كلمة مرور جديدة لـ ${u.phone}' : 'New password for ${u.phone}',
        ),
        content: PasswordField(
          controller: ctrl,
          autofocus: true,
          label: _ar ? 'كلمة المرور' : 'Password',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(_ar ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (pass == null) return;
    if (pass.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.passwordTooShort),
          ),
        );
      }
      return;
    }
    try {
      await widget.onResetPassword(u.phone, pass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _ar ? 'تمت إعادة تعيين كلمة المرور' : 'Password reset',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    }
  }

  Future<void> _resetTotp(EntityUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_ar ? 'إعادة تعيين المصادقة الثنائية' : 'Reset 2FA'),
        content: Text(
          _ar
              ? 'سيُطلب من ${u.phone} إعادة التسجيل في المصادقة الثنائية عند الدخول التالي.'
              : '${u.phone} will re-enroll in two-factor authentication on next login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_ar ? 'إعادة تعيين' : 'Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.onResetTotp(u.phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _ar ? 'تمت إعادة تعيين المصادقة الثنائية' : '2FA reset',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;

    // A phone and password typed into the sub-form and never "registered" used
    // to be dropped on the floor: Save reported success and no login existed.
    // Filling those fields IS the request, so save folds the draft in — or
    // stops on its error rather than discarding it.
    if (_hasDraft && !_tryAddUser()) {
      _snack(_t(
        'أكمل بيانات المستخدم الجديد أو امسحها قبل الحفظ.',
        'Finish or clear the new user before saving.',
      ));
      return;
    }

    final remaining = _effectiveUsers;
    // Counts what SURVIVES the save. Checking _users would happily let the
    // operator mark every user for removal and only find out server-side.
    if (remaining.isEmpty) {
      setState(() => _addError = l.manageUsersAtLeastOne);
      return;
    }

    // Deleting a login is the one irreversible thing this sheet does, so it is
    // named out loud — phone by phone — before anything is written.
    if (_pendingRemoval.isNotEmpty) {
      final going = _users
          .map((u) => u.phone)
          .where(_pendingRemoval.contains)
          .toList();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            icon: Icon(Icons.person_remove_outlined, color: cs.error),
            title: Text(_ar
                ? '${arDeleteUsersCount(going.length)}؟'
                : (going.length == 1
                    ? 'Delete user?'
                    : 'Delete ${going.length} users?')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_ar
                    ? (going.length == 1
                        ? 'لن يعود بإمكانه تسجيل الدخول. لا يمكن التراجع.'
                        : 'لن يعود بإمكان هؤلاء تسجيل الدخول. لا يمكن التراجع.')
                    : (going.length == 1
                        ? "This person will no longer be able to sign in. This can't be undone."
                        : "These people will no longer be able to sign in. This can't be undone.")),
                const SizedBox(height: 12),
                ...going.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(p,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 13, letterSpacing: 0.4)),
                    )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_ar ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                key: const Key('confirm-user-removal'),
                style: FilledButton.styleFrom(backgroundColor: cs.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_ar ? 'حذف' : 'Delete'),
              ),
            ],
          );
        },
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(List.unmodifiable(remaining));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.manageUsersErrorSaving)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final entityName = widget.entity.meta.name.isNotEmpty
        ? widget.entity.meta.name
        : widget.entity.id;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel(l.manageUsersSectionLabel),
            Text(
              l.manageUsersTitle,
              style: IntesharType.display(26, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              entityName,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),

            // Existing users
            if (_users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l.manageUsersEmpty,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ..._users.map(
                (u) => _UserRow(
                  user: u,
                  canReset: _isPersisted(u),
                  markedForRemoval: _pendingRemoval.contains(u.phone),
                  onRemove: () => _removeUser(u),
                  onUndoRemove: () => _undoRemove(u),
                  onResetPassword: () => _resetPassword(u),
                  onResetTotp: () => _resetTotp(u),
                ),
              ),

            const SizedBox(height: 16),

            // The sub-form is boxed so its own commit button reads as belonging
            // to it and not to the sheet. Two bare buttons stacked in one column
            // both looked like "the" commit, and the wrong one was pressed.
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.manageUsersNewUser,
                    style: IntesharType.overline(color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      color: cs.onSurface,
                      letterSpacing: 0.6,
                    ),
                    decoration: InputDecoration(labelText: l.manageUsersPhone),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      color: cs.onSurface,
                      letterSpacing: 0.8,
                    ),
                    decoration: InputDecoration(
                      labelText: l.manageUsersPassword,
                      suffixIcon: IconButton(
                        // UX-150.
                        tooltip: _obscurePass
                            ? (_ar ? 'إظهار كلمة المرور' : 'Show password')
                            : (_ar ? 'إخفاء كلمة المرور' : 'Hide password'),
                        icon: Icon(
                          _obscurePass
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _selectedRole,
                    decoration: InputDecoration(labelText: l.manageUsersRole),
                    items: _allowedRoles
                        .map((r) =>
                            DropdownMenuItem(value: r, child: Text(r.name)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedRole = v);
                    },
                  ),
                  // UX-96: on a shop this is the form people reach for when they
                  // want a till operator. It cannot make one — say so here,
                  // rather than let them find out from the POS screen later.
                  if (_isStore) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 15, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _t(
                              'هذا الحساب مدير للمتجر ولا يستطيع البيع. مستخدم نقطة البيع '
                                  'يُنشأ من شاشة "نقاط البيع" فقط.',
                              'This account administers the shop and cannot sell. '
                                  'A till operator is created only from the POS points screen.',
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_addError != null) ...[
                    const SizedBox(height: 10),
                    Text(_addError!,
                        style: TextStyle(color: cs.error, fontSize: 12)),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonalIcon(
                      onPressed: () => _tryAddUser(),
                      icon: const Icon(Icons.person_add_alt, size: 16),
                      label: Text(l.manageUsersRegisterButton),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Says out loud what the two buttons do differently, since a
                  // draft left here is now folded into the save either way.
                  Text(
                    _t(
                      'يُضاف المستخدم إلى القائمة أعلاه — والحفظ بالأسفل يكتب القائمة.',
                      'Adds the user to the list above — the button below writes '
                          'the list.',
                    ),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.manageUsersSave),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final EntityUser user;
  final bool canReset;
  final bool markedForRemoval;
  final VoidCallback onRemove;
  final VoidCallback onUndoRemove;
  final VoidCallback onResetPassword;
  final VoidCallback onResetTotp;
  const _UserRow({
    required this.user,
    required this.canReset,
    required this.markedForRemoval,
    required this.onRemove,
    required this.onUndoRemove,
    required this.onResetPassword,
    required this.onResetTotp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final color = markedForRemoval
        ? cs.error
        : user.role == UserRole.ADMIN
            ? cs.onPrimaryContainer
            : IntesharColors.sage;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkCard(
        ruleColor: color,
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.person_outline, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                user.phone,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 13,
                  color: markedForRemoval ? cs.onSurfaceVariant : cs.onSurface,
                  letterSpacing: 0.4,
                  decoration:
                      markedForRemoval ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            StampPill(
              label: markedForRemoval
                  ? (ar ? 'سيُحذف' : 'Removing')
                  : user.role.name,
              color: color,
            ),
            const SizedBox(width: 4),
            // A marked row offers only the way back. Leaving the menu live
            // would let it be "removed" twice and hide the undo behind it.
            if (markedForRemoval)
              TextButton(
                key: Key('undo-remove-${user.phone}'),
                onPressed: onUndoRemove,
                child: Text(ar ? 'تراجع' : 'Undo'),
              )
            else if (canReset)
              PopupMenuButton<String>(
                key: Key('remove-${user.phone}'),
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                onSelected: (v) {
                  if (v == 'pass') {
                    onResetPassword();
                  } else if (v == 'totp') {
                    onResetTotp();
                  } else if (v == 'remove') {
                    onRemove();
                  }
                },
                itemBuilder: (ctx) {
                  return [
                    PopupMenuItem(
                      value: 'pass',
                      child: Text(
                        ar ? 'إعادة تعيين كلمة المرور' : 'Reset password',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'totp',
                      child: Text(
                        ar ? 'إعادة تعيين المصادقة الثنائية' : 'Reset 2FA',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(ar ? 'حذف المستخدم' : 'Remove user'),
                    ),
                  ];
                },
              )
            else
              // UX-150: an icon-only, unrecoverable delete with no name on it.
              IconButton(
                key: Key('remove-${user.phone}'),
                tooltip: ar ? 'حذف المستخدم' : 'Remove user',
                icon: Icon(Icons.delete_outline, color: cs.error, size: 18),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}
