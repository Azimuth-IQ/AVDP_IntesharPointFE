import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// Whether a list screen's search box may claim focus the moment the screen
/// opens (UX-12).
///
/// The HQ console is a full-time keyboard workload and every one of its
/// directories exists to *find a row* — yet on arrival the caret was nowhere, so
/// finding an agent began with a mouse trip to a box that was already the only
/// thing on the toolbar. Autofocus fixes that for free.
///
/// It is deliberately **not** unconditional. `autofocus` on a handheld raises
/// the on-screen keyboard over the list the operator came to look at, and on the
/// POS that list is the sale itself. Both halves of this condition are load-
/// bearing:
///
/// * [kIsWeb] — the Android POS build never autofocuses anything, whatever size
///   screen it is bolted to. A Sunmi terminal has no keyboard to drive.
/// * width — the same web bundle opened on a phone browser is still a phone.
///
/// Screens whose first action is more likely to be *scrolling* (the hierarchy
/// tree, the POS sale grid) should not call this at all — see the notes at their
/// call sites.
bool desktopSearchAutofocus(BuildContext context) => kIsWeb && context.isWide;

/// **The** search box (UX-133).
///
/// The app had fifteen hand-rolled search toolbars drifting on five separate
/// axes: the magnifier at size 20 on some screens and 18 on others, `isDense`
/// set on six of fifteen, a clear button on only three, a result counter on only
/// two, and surrounding padding at 16 or 20. `pos_home_page.dart` alone carries
/// two search rows that disagree with each other — one shows its clear button
/// while `searching`, the other while `_search.isNotEmpty`, so the same box
/// behaves differently one navigation step apart.
///
/// Two of those axes are not cosmetic:
///
/// * **The clear button.** Where it was absent, the only way out of a query on a
///   POS handheld was fifteen backspaces — with the on-screen keyboard covering
///   the results the operator is trying to get back to. Where it *was* present,
///   it was drawn from `controller.text` read during the parent's build, so it
///   only appeared if the parent happened to rebuild on every keystroke. This
///   widget listens to the controller itself, so the button is correct
///   regardless of what the caller does.
/// * **The result count.** "No results" and "no results *for this filter*" look
///   identical without it. [resultCount] renders as a bare numeral chip — no
///   words, so it needs no new translation and reads the same in both locales.
///
/// Callers keep owning the [controller] and the filtering; this owns only how a
/// search box looks and how it clears.
class AppSearchField extends StatefulWidget {
  /// Owned by the caller — this widget never disposes it.
  final TextEditingController controller;

  /// Placeholder. Localized by the caller (the hints are per-screen: "Search by
  /// name, SKU, or serial…", "Filter by path…").
  final String? hintText;

  final ValueChanged<String>? onChanged;

  /// Called *after* the field has been emptied, so the caller can drop its
  /// filter. When null, clearing still empties the box and fires [onChanged]
  /// with `''` — a caller that filters in [onChanged] needs nothing else.
  final VoidCallback? onClear;

  /// Number of matches for the current query, shown as a numeral chip. Null
  /// hides it. Pass it whenever the results are not all visible at once.
  final int? resultCount;

  /// Tooltip on the clear button. Defaults to the platform's localized delete
  /// tooltip, which is what the one screen that had a tooltip already used —
  /// pass a proper "clear search" string where one exists.
  final String? clearTooltip;

  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  /// Padding around the field. Defaults to the horizontal page gutter — the old
  /// toolbars split between 16 and 20 for the same visual role.
  final EdgeInsetsGeometry padding;

  const AppSearchField({
    super.key,
    required this.controller,
    this.hintText,
    this.onChanged,
    this.onClear,
    this.resultCount,
    this.clearTooltip,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.onSubmitted,
    this.padding = const EdgeInsetsDirectional.fromSTEB(
      IntesharSpacing.lg,
      IntesharSpacing.xs,
      IntesharSpacing.lg,
      IntesharSpacing.md,
    ),
  });

  /// The one magnifier size. The app was split between 20 and 18.
  static const double iconSize = 20;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_syncHasText);
  }

  @override
  void didUpdateWidget(AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncHasText);
      widget.controller.addListener(_syncHasText);
      _syncHasText();
    }
  }

  @override
  void dispose() {
    // The controller belongs to the caller; drop only our listener.
    widget.controller.removeListener(_syncHasText);
    super.dispose();
  }

  void _syncHasText() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  void _clear() {
    widget.controller.clear();
    // Fire onChanged so a caller that filters purely from the callback drops its
    // query without needing to also wire onClear.
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final suffix = <Widget>[
      if (widget.resultCount != null) _ResultCount(count: widget.resultCount!),
      if (_hasText)
        IconButton(
          tooltip: widget.clearTooltip ??
              MaterialLocalizations.of(context).deleteButtonTooltip,
          icon: const Icon(Icons.close, size: 18),
          onPressed: _clear,
        ),
    ];

    return Padding(
      padding: widget.padding,
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: Icon(
            Icons.search,
            size: AppSearchField.iconSize,
            color: cs.onSurfaceVariant,
          ),
          suffixIcon: suffix.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...suffix,
                    if (widget.resultCount != null && !_hasText)
                      const SizedBox(width: IntesharSpacing.sm),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Bare numeral chip — no words, so it needs no translation and reads
/// identically in Arabic and English.
class _ResultCount extends StatelessWidget {
  final int count;
  const _ResultCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: IntesharSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: IntesharSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$count',
          style: IntesharText.caption(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
