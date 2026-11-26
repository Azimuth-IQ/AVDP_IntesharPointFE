import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/auth/password_rule.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/companies/data/company_repository.dart';
import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/company_portal/data/company_portal_repository.dart';
import 'package:inteshar/features/company_portal/domain/company_portal_models.dart';
import 'package:inteshar/shared/widgets/confirm_dialog.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/new_password_field.dart';

/// PROD-037: HQ › Company accounts — the telecom companies' read-only logins (Asiacell,
/// Zain). Each sees only its own company's uploaded cards. The client asked to treat them
/// as a risk: HQ switches each one off and on here (off signs it out at once) and sees
/// every request it made.
class CompanyAccountsPage extends ConsumerStatefulWidget {
  const CompanyAccountsPage({super.key});

  @override
  ConsumerState<CompanyAccountsPage> createState() => _CompanyAccountsPageState();
}

class _CompanyAccountsPageState extends ConsumerState<CompanyAccountsPage> {
  Future<List<CompanyAccount>>? _future;
  final Set<String> _busy = {};

  CompanyAccountRepository get _repo => CompanyAccountRepository(ref.read(apiClientProvider));

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    _future = CompanyAccountRepository(ref.read(apiClientProvider)).list();
  }

  void _reload() => setState(() => _future = _repo.list());

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(String id, Future<void> Function() action, String done) async {
    setState(() => _busy.add(id));
    try {
      await action();
      if (mounted) _snack(done);
      _reload();
    } catch (e) {
      if (mounted) _snack(friendlyError(e, context));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _toggle(CompanyAccount a, bool on) async {
    if (!on) {
      final ok = await showConfirm(
        context,
        title: _t('إيقاف الحساب؟', 'Switch this account off?'),
        body: _t('سيُخرج «${a.name}» من النظام فورًا ولن يستطيع الدخول حتى تعيد تشغيله.',
            '«${a.name}» is signed out at once and cannot sign in until you switch it back on.'),
        confirmLabel: _t('إيقاف', 'Switch off'),
        destructive: true,
      );
      if (!ok) return;
    }
    await _run(a.id, () => _repo.setActive(a.id, on),
        on ? _t('تم تشغيل الحساب', 'Account switched on') : _t('تم إيقاف الحساب', 'Account switched off'));
  }

  Future<void> _delete(CompanyAccount a) async {
    final ok = await showConfirm(
      context,
      title: _t('حذف الحساب؟', 'Delete this account?'),
      body: _t('يُحذف حساب «${a.name}» نهائيًا. يبقى سجل نشاطه 30 يومًا.',
          '«${a.name}» is deleted for good. Its activity log stays for 30 days.'),
      confirmLabel: _t('حذف', 'Delete'),
      destructive: true,
    );
    if (!ok) return;
    await _run(a.id, () => _repo.delete(a.id), _t('تم حذف الحساب', 'Account deleted'));
  }

  Future<void> _newPassword(CompanyAccount a) async {
    final pw = await showDialog<String>(context: context, builder: (_) => _PasswordDialog(name: a.name));
    if (pw == null) return;
    await _run(a.id, () => _repo.setPassword(a.id, pw),
        _t('تم تعيين كلمة المرور — تُغيَّر عند أول دخول', 'Password set — it must be changed at the next sign-in'));
  }

  Future<void> _add() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddAccountDialog(repo: _repo, companies: CompanyRepository(ref.read(apiClientProvider))),
    );
    if (created == true) {
      if (mounted) _snack(_t('تم إنشاء الحساب', 'Account created'));
      _reload();
    }
  }

  void _activity(CompanyAccount a) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ActivitySheet(account: a, repo: _repo),
    );
  }

  void _preview(CompanyAccount a) =>
      context.push('/hq/company-accounts/preview?companyId=${Uri.encodeComponent(a.companyId)}');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_t('حسابات الشركات', 'Company accounts'))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(_t('إضافة حساب', 'Add account')),
        onPressed: _add,
      ),
      body: FutureBuilder<List<CompanyAccount>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _reload);
          final list = snap.data ?? const [];
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(
                  _t('حساب الشركة (مثل آسيا سيل أو زين) يرى فقط الكروت المرفوعة لشركته: اليوم والمحافظة والفئة والعدد. لا يرى المبيعات ولا السحوبات ولا الوكلاء ولا نقاط البيع. يدخل من الموقع فقط، ويحتاج رمز المصادقة في كل دخول.',
                      'A company account (such as Asiacell or Zain) sees only its own company\'s uploaded cards: day, governorate, category and count. No sales, withdrawals, agents or shops. It signs in on the website only, with the authenticator code every time.'),
                  style: IntesharType.sans(13, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: IntesharSpacing.md),
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.badge_outlined,
                    message: _t('لا توجد حسابات شركات بعد', 'No company accounts yet'),
                    actionLabel: _t('إضافة حساب', 'Add account'),
                    onAction: _add,
                  )
                else
                  for (final a in list) _card(cs, a),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(ColorScheme cs, CompanyAccount a) {
    final busy = _busy.contains(a.id);
    final seen = a.lastSeenAt == null
        ? _t('لم يدخل بعد', 'Not signed in yet')
        : '${_t('آخر نشاط', 'Last seen')}: ${Formatters.dateTime(a.lastSeenAt!)}'
            '${a.lastSeenIp.isEmpty ? '' : ' · ${a.lastSeenIp}'}';
    final setup = a.mustChangePassword || !a.totpEnrolled
        ? _t('بانتظار أول دخول (تغيير كلمة المرور + رمز المصادقة)',
            'Waiting for the first sign-in (new password + authenticator)')
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: IntesharSpacing.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: IntesharType.sans(16, w: IntesharWeight.bold), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${a.companyName.isEmpty ? '—' : a.companyName} · ${a.phone}',
                    style: IntesharType.sans(13, color: cs.onSurfaceVariant)),
              ]),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Switch(value: a.active, onChanged: (v) => _toggle(a, v)),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'activity' => _activity(a),
                'preview' => _preview(a),
                'password' => _newPassword(a),
                'delete' => _delete(a),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'activity', child: Text(_t('النشاط', 'Activity'))),
                PopupMenuItem(value: 'preview', child: Text(_t('معاينة ما يراه', 'Preview what it sees'))),
                PopupMenuItem(value: 'password', child: Text(_t('كلمة مرور جديدة', 'New password'))),
                PopupMenuItem(value: 'delete', child: Text(_t('حذف', 'Delete'), style: TextStyle(color: cs.error))),
              ],
            ),
          ]),
          const SizedBox(height: IntesharSpacing.sm),
          Text(a.active ? seen : _t('متوقف — لا يستطيع الدخول', 'Switched off — cannot sign in'),
              style: IntesharType.sans(12, color: a.active ? cs.onSurfaceVariant : cs.error)),
          if (setup != null && a.active)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(setup, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.history, size: 18),
              label: Text(_t('النشاط', 'Activity')),
              onPressed: () => _activity(a),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Create a company account: which company, a name, its phone and a first password
/// (the company must change it at its first sign-in).
class _AddAccountDialog extends StatefulWidget {
  final CompanyAccountRepository repo;
  final CompanyRepository companies;
  const _AddAccountDialog({required this.repo, required this.companies});

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  late final Future<List<Company>> _companies = widget.companies.readAll();
  String? _companyId;
  bool _saving = false;
  String? _error;

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.create(
        companyId: _companyId!,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        password: _password.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_t('حساب شركة جديد', 'New company account')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FutureBuilder<List<Company>>(
                future: _companies,
                builder: (context, snap) {
                  final list = snap.data ?? const <Company>[];
                  return DropdownButtonFormField<String>(
                    initialValue: _companyId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _t('الشركة', 'Company')),
                    items: [
                      for (final c in list) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                    ],
                    validator: (v) => v == null ? _t('اختر الشركة', 'Pick the company') : null,
                    onChanged: (v) => setState(() {
                      _companyId = v;
                      if (_name.text.trim().isEmpty && v != null) {
                        _name.text = list.firstWhere((c) => c.id == v).name;
                      }
                    }),
                  );
                },
              ),
              const SizedBox(height: IntesharSpacing.md),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: _t('اسم الحساب', 'Account name')),
                validator: (v) => (v ?? '').trim().isEmpty ? _t('اكتب الاسم', 'Enter a name') : null,
              ),
              const SizedBox(height: IntesharSpacing.md),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                decoration: InputDecoration(labelText: _t('رقم الهاتف (للدخول)', 'Phone (the sign-in)'), hintText: '07XXXXXXXXX'),
                validator: (v) => RegExp(r'^0\d{10}$').hasMatch((v ?? '').trim())
                    ? null
                    : _t('11 رقمًا يبدأ بـ 0', '11 digits starting with 0'),
              ),
              const SizedBox(height: IntesharSpacing.md),
              NewPasswordField(controller: _password, label: _t('كلمة المرور الأولى', 'First password')),
              const SizedBox(height: IntesharSpacing.sm),
              Text(
                _t('تُغيِّر الشركة كلمة المرور وتربط تطبيق المصادقة عند أول دخول.',
                    'The company changes this password and links an authenticator app at its first sign-in.'),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: IntesharSpacing.sm),
                  child: Text(_error!, style: IntesharType.sans(13, color: cs.error)),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: Text(_t('إلغاء', 'Cancel'))),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_t('إنشاء', 'Create')),
        ),
      ],
    );
  }
}

/// HQ types a new password; the company must change it at its next sign-in.
class _PasswordDialog extends StatefulWidget {
  final String name;
  const _PasswordDialog({required this.name});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return AlertDialog(
      title: Text(ar ? 'كلمة مرور جديدة — ${widget.name}' : 'New password — ${widget.name}'),
      content: SizedBox(
        width: 420,
        child: NewPasswordField(controller: _pw, label: ar ? 'كلمة المرور' : 'Password', autofocus: true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(ar ? 'إلغاء' : 'Cancel')),
        ListenableBuilder(
          listenable: _pw,
          builder: (context, _) => FilledButton(
            onPressed: PasswordRule.isStrong(_pw.text) ? () => Navigator.of(context).pop(_pw.text) : null,
            child: Text(ar ? 'تعيين' : 'Set'),
          ),
        ),
      ],
    );
  }
}

/// Every request the account made, newest first (the server keeps 30 days).
class _ActivitySheet extends StatefulWidget {
  final CompanyAccount account;
  final CompanyAccountRepository repo;
  const _ActivitySheet({required this.account, required this.repo});

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  late Future<List<CompanyActivity>> _future = widget.repo.activity(widget.account.id);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            ar ? 'نشاط «${widget.account.name}» — آخر 30 يومًا' : '«${widget.account.name}» activity — last 30 days',
            style: IntesharType.sans(16, w: IntesharWeight.bold),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<CompanyActivity>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ErrorState(
                    error: snap.error!,
                    onRetry: () => setState(() => _future = widget.repo.activity(widget.account.id)));
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return EmptyState(icon: Icons.history, message: ar ? 'لا يوجد نشاط بعد' : 'No activity yet', dense: true);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant),
                itemBuilder: (_, i) {
                  final a = list[i];
                  final color = a.refused ? cs.error : null;
                  final meta = [
                    if (a.at != null) Formatters.dateTime(a.at!),
                    if (a.ip.isNotEmpty) a.ip,
                    if (a.platform.isNotEmpty) a.platform,
                  ].join(' · ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a.refused ? Icons.block : Icons.check_circle_outline, color: color ?? cs.onSurfaceVariant),
                    title: Text(a.describe(ar: ar), style: IntesharType.sans(14, color: color)),
                    subtitle: Text(
                      [meta, if (a.query.isNotEmpty) a.query, if (a.device.isNotEmpty) a.device].join('\n'),
                      style: IntesharType.sans(12, color: cs.onSurfaceVariant),
                    ),
                    isThreeLine: a.query.isNotEmpty || a.device.isNotEmpty,
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
