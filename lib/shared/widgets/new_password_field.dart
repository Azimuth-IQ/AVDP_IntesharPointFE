import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/auth/password_rule.dart';
import 'package:inteshar/shared/widgets/password_field.dart';

/// PROD-008: the field for choosing a NEW sign-in password, used wherever one is set.
///
/// Under the field, always visible, the five points of the rule ([PasswordRule]); each one
/// turns green with a tick as the typed password meets it, so the person knows what is
/// needed before they press Save. Inside a [Form] its validator refuses a password that
/// misses any point. [allowEmpty] is for edit forms where a blank field keeps the current
/// password.
class NewPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool isDense;
  final bool autofocus;
  final bool allowEmpty;
  final TextInputAction? textInputAction;

  const NewPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.onSubmitted,
    this.isDense = false,
    this.autofocus = false,
    this.allowEmpty = false,
    this.textInputAction,
  });

  @override
  State<NewPasswordField> createState() => _NewPasswordFieldState();
}

class _NewPasswordFieldState extends State<NewPasswordField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(NewPasswordField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PasswordField(
          controller: widget.controller,
          label: widget.label,
          isDense: widget.isDense,
          autofocus: widget.autofocus,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          validator: (v) {
            if (widget.allowEmpty && (v ?? '').trim().isEmpty) return null;
            return PasswordRule.validate(v, ar: ar);
          },
        ),
        const SizedBox(height: IntesharSpacing.sm),
        PasswordRuleChecklist(value: widget.controller.text),
      ],
    );
  }
}

/// The five points of [PasswordRule], each ticked green once [value] meets it.
class PasswordRuleChecklist extends StatelessWidget {
  final String value;
  const PasswordRuleChecklist({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final met = PasswordRule.met(value);
    final good = context.status.success;
    return Container(
      key: const ValueKey('password-rule-checklist'),
      padding: const EdgeInsets.all(IntesharSpacing.sm2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            PasswordRule.heading(ar: ar),
            style: IntesharType.sans(12, color: cs.onSurface, w: IntesharWeight.bold),
          ),
          const SizedBox(height: IntesharSpacing.xs),
          for (final n in PasswordNeed.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    met.contains(n) ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: met.contains(n) ? good : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: IntesharSpacing.sm),
                  Expanded(
                    child: Text(
                      PasswordRule.label(n, ar: ar),
                      style: IntesharType.sans(
                        12,
                        color: met.contains(n) ? good : cs.onSurfaceVariant,
                        w: met.contains(n) ? IntesharWeight.semibold : IntesharWeight.regular,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
