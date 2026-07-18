import 'package:flutter/material.dart';

/// A password input with a show/hide **eye toggle**. Drop-in replacement for a
/// `TextField`/`TextFormField` on any password field. Works inside or outside a Form.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool isDense;
  final bool autofocus;
  final TextInputAction? textInputAction;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.isDense = false,
    this.autofocus = false,
    this.textInputAction,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofocus: widget.autofocus,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: widget.isDense,
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
          tooltip: _obscure ? (ar ? 'إظهار' : 'Show') : (ar ? 'إخفاء' : 'Hide'),
        ),
      ),
    );
  }
}
