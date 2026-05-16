import 'package:flutter/material.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

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

  List<UserRole> get _allowedRoles => widget.entity.type == EntityType.STORE ? UserRole.values : [UserRole.ADMIN];

  void _tryAddUser() {
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (phone.isEmpty) {
      setState(() => _addError = 'Phone is required');
      return;
    }
    if (pass.isEmpty) {
      setState(() => _addError = 'Password is required');
      return;
    }
    if (_users.any((u) => u.phone == phone)) {
      setState(() => _addError = 'A user with this phone already exists');
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
    if (_users.isEmpty) {
      setState(() => _addError = 'At least one user is required');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(List.unmodifiable(_users));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entityName = widget.entity.meta.name.isNotEmpty ? widget.entity.meta.name : widget.entity.id;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage Users', style: theme.textTheme.titleMedium),
            Text(entityName, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),

            // Existing users list
            if (_users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No users yet — add one below.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              )
            else
              ..._users.map(
                (u) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(u.phone),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoleChip(role: u.role),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _removeUser(u),
                      ),
                    ],
                  ),
                ),
              ),

            const Divider(),
            Text('Add User', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),

            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone *'),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: 'Password *',
                suffixIcon: IconButton(icon: Icon(_obscurePass ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscurePass = !_obscurePass)),
              ),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<UserRole>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(labelText: 'Role'),
              items: _allowedRoles.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedRole = v);
              },
            ),

            if (_addError != null) ...[const SizedBox(height: 8), Text(_addError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))],

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(onPressed: _tryAddUser, icon: const Icon(Icons.person_add), label: const Text('Add')),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final UserRole role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (role) {
      UserRole.ADMIN => (cs.primaryContainer, cs.onPrimaryContainer),
      UserRole.USER => (cs.secondaryContainer, cs.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        role.name,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
