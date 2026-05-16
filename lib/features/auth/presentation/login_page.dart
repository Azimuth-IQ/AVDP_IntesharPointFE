import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/auth/application/seed_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController(text: '07705371953');
  final _passCtrl = TextEditingController(text: 'root');
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  bool _showMongoHint = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _showMongoHint = false;
    });
    try {
      await ref.read(authStateProvider.notifier).login(_phoneCtrl.text.trim(), _passCtrl.text);
    } catch (e) {
      final raw = e.toString();
      final clean = raw.replaceFirst('ApiException', '').replaceAll('(', '').replaceAll(')', '').trim();
      setState(() {
        _error = clean;
        _showMongoHint = raw.contains('401') || raw.contains('no user') || raw.contains('Could not find');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showUrlSheet() async {
    final current = await sessionStorage.getBaseUrl();
    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    final l = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.loginServerUrl, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Base URL', hintText: 'http://192.168.1.x:8080'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await sessionStorage.setBaseUrl(ctrl.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for successful auth and navigate
    ref.listen(authStateProvider, (_, next) {
      if (next.hasValue && next.value is AuthAuthenticated) {
        context.go((next.value as AuthAuthenticated).homeRoute);
      }
    });

    final l = AppLocalizations.of(context)!;
    final authState = ref.watch(authStateProvider);
    final isAuthenticated = authState.valueOrNull is AuthAuthenticated;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onLongPress: () => context.go('/diagnostics'),
                      child: Column(
                        children: [
                          Icon(Icons.store, size: 64, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(l.appTitle, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                          Text('Voucher Distribution', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.secondary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: l.loginPhone, hintText: '07701234567', prefixIcon: const Icon(Icons.phone)),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: l.loginPassword,
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(onPressed: _showUrlSheet, icon: const Icon(Icons.settings, size: 16), label: Text(l.loginServerUrl)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                      ),
                    ],
                    if (_showMongoHint) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          '${l.loginNoUsers}\n\nDefault: phone=07701234567  password=password',
                          style: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer, fontSize: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _signIn,
                      child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l.loginSignIn),
                    ),
                    if (isAuthenticated) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => ref.read(seedControllerProvider.notifier).seed(context),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l.loginSeedDemo),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
