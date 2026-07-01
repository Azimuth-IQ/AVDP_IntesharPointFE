import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

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

  List<UserRole> get _allowedRoles => widget.entity.type == EntityType.STORE
      ? UserRole.values
      : [UserRole.ADMIN];

  void _tryAddUser() {
    final l = AppLocalizations.of(context)!;
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (phone.isEmpty) {
      setState(() => _addError = l.manageUsersPhoneRequired);
      return;
    }
    if (pass.isEmpty) {
      setState(() => _addError = l.manageUsersPasswordRequired);
      return;
    }
    if (!RegExp(r'^07\d{9}$').hasMatch(phone)) {
      setState(() => _addError = l.invalidPhone);
      return;
    }
    if (pass.length < 6) {
      setState(() => _addError = l.passwordTooShort);
      return;
    }
    if (_users.any((u) => u.phone == phone)) {
      setState(() => _addError = l.manageUsersPhoneDuplicate);
      return;
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
  }

  void _removeUser(EntityUser u) {
    setState(
      () => _users.removeWhere((x) => x.id == u.id && x.phone == u.phone),
    );
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  Future<void> _resetPassword(EntityUser u) async {
    final ctrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _ar ? 'كلمة مرور جديدة لـ ${u.phone}' : 'New password for ${u.phone}',
        ),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _ar ? 'كلمة المرور' : 'Password',
          ),
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
    if (_users.isEmpty) {
      setState(() => _addError = l.manageUsersAtLeastOne);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(List.unmodifiable(_users));
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
                  canReset: widget.entity.users.any((x) => x.phone == u.phone),
                  onRemove: () => _removeUser(u),
                  onResetPassword: () => _resetPassword(u),
                  onResetTotp: () => _resetTotp(u),
                ),
              ),

            const SizedBox(height: 16),
            Container(height: 1, color: cs.outline),
            const SizedBox(height: 16),

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
                  icon: Icon(
                    _obscurePass ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: _selectedRole,
              decoration: InputDecoration(labelText: l.manageUsersRole),
              items: _allowedRoles
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedRole = v);
              },
            ),
            if (_addError != null) ...[
              const SizedBox(height: 10),
              Text(_addError!, style: TextStyle(color: cs.error, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                onPressed: _tryAddUser,
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: Text(l.manageUsersRegisterButton),
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
  final VoidCallback onRemove;
  final VoidCallback onResetPassword;
  final VoidCallback onResetTotp;
  const _UserRow({
    required this.user,
    required this.canReset,
    required this.onRemove,
    required this.onResetPassword,
    required this.onResetTotp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = user.role == UserRole.ADMIN
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
                  color: cs.onSurface,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            StampPill(label: user.role.name, color: color),
            const SizedBox(width: 4),
            if (canReset)
              PopupMenuButton<String>(
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
                  final ar = Localizations.localeOf(ctx).languageCode == 'ar';
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
              IconButton(
                icon: Icon(Icons.delete_outline, color: cs.error, size: 18),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}
