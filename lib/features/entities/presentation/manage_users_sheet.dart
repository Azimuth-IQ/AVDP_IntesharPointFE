import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

class ManageUsersSheet extends StatefulWidget {
  final Entity entity;
  final Future<void> Function(List<EntityUser> users) onSave;

  const ManageUsersSheet({super.key, required this.entity, required this.onSave});

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

  List<UserRole> get _allowedRoles =>
      widget.entity.type == EntityType.STORE ? UserRole.values : [UserRole.ADMIN];

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
    if (_users.any((u) => u.phone == phone)) {
      setState(() => _addError = l.manageUsersPhoneDuplicate);
      return;
    }

    final id = 'u-$phone-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _users.add(EntityUser(id: id, phone: phone, password: pass, role: _selectedRole));
      _addError = null;
    });
    _phoneCtrl.clear();
    _passCtrl.clear();
  }

  void _removeUser(EntityUser u) {
    setState(() => _users.removeWhere((x) => x.id == u.id && x.phone == u.phone));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.manageUsersErrorSaving)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final entityName = widget.entity.meta.name.isNotEmpty ? widget.entity.meta.name : widget.entity.id;

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
                decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel(l.manageUsersSectionLabel),
            Text(
              l.manageUsersTitle,
              style: IntesharType.display(26, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(entityName, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 18),

            // Existing users
            if (_users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l.manageUsersEmpty, style: Theme.of(context).textTheme.bodySmall),
              )
            else
              ..._users.map((u) => _UserRow(user: u, onRemove: () => _removeUser(u))),

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
              style: GoogleFonts.jetBrainsMono(fontSize: 14, color: cs.onSurface, letterSpacing: 0.6),
              decoration: InputDecoration(labelText: l.manageUsersPhone),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              style: GoogleFonts.jetBrainsMono(fontSize: 14, color: cs.onSurface, letterSpacing: 0.8),
              decoration: InputDecoration(
                labelText: l.manageUsersPassword,
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off, size: 18),
                  onPressed: () => setState(() => _obscurePass = !_obscurePass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: _selectedRole,
              decoration: InputDecoration(labelText: l.manageUsersRole),
              items: _allowedRoles.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
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
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
  final VoidCallback onRemove;
  const _UserRow({required this.user, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = user.role == UserRole.ADMIN ? cs.onPrimaryContainer : IntesharColors.sage;
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
                style: GoogleFonts.jetBrainsMono(fontSize: 13, color: cs.onSurface, letterSpacing: 0.4),
              ),
            ),
            StampPill(label: user.role.name, color: color),
            const SizedBox(width: 4),
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
