import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// Fraction of the viewport a modal sheet may occupy. Sheets in the app were
/// split between 0.75, 0.85 and no cap at all; 0.85 is the majority and leaves
/// enough page behind the scrim to show what you are still on top of.
const double kSheetMaxHeightFactor = 0.85;

/// The grab handle every bottom sheet gets (UX-131/132).
///
/// This 36×4 pill was copy-pasted at **nine** call sites, and six of the
/// fifteen sheets had no handle at all — which is an affordance lie, not just
/// an inconsistency: a Flutter modal sheet is drag-dismissible by default, so
/// the sheets without a handle were draggable and didn't say so, and anyone who
/// learned "no handle = must find the X" was learning a rule the app breaks.
///
/// Don't pair this with `enableDrag: false` — then the handle lies the other way.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// One shell for every modal bottom sheet: handle, title block, keyboard inset,
/// height cap, scrolling (UX-131/132).
///
/// It exists because those five things were re-decided per sheet — three
/// different max heights, titles at display 24/26/28, and a keyboard inset that
/// some sheets applied and others didn't (so a field could sit under the
/// keyboard). Use it as the direct child of `showModalBottomSheet(
/// isScrollControlled: true, builder: …)`.
///
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => SheetFrame(
///     eyebrow: ar ? 'المستخدمون' : 'Users',
///     title: entityName,
///     child: Column(mainAxisSize: MainAxisSize.min, children: [...]),
///   ),
/// );
/// ```
class SheetFrame extends StatelessWidget {
  /// The sheet body. Laid out `Flexible` under the height cap, so a long body
  /// scrolls instead of overflowing.
  final Widget child;

  /// Muted label above the title (rendered as a [SectionLabel]).
  final String? eyebrow;

  /// The sheet's one title. Rendered at display 24 — the canonical size.
  final String? title;

  /// Secondary line under the title (the entity name, a count, a warning).
  final String? subtitle;

  /// Action pinned to the end of the title row (an icon button, a chip).
  final Widget? trailing;

  /// Pinned below the scroll area — for a CTA that must stay reachable while
  /// the body scrolls.
  final Widget? footer;

  final bool handle;

  /// Set false when [child] does its own scrolling (a `ListView`, a
  /// `TabBarView`) — two nested scrollables is the bug this prevents.
  final bool scrollable;

  final double maxHeightFactor;
  final EdgeInsets padding;

  const SheetFrame({
    super.key,
    required this.child,
    this.eyebrow,
    this.title,
    this.subtitle,
    this.trailing,
    this.footer,
    this.handle = true,
    this.scrollable = true,
    this.maxHeightFactor = kSheetMaxHeightFactor,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasHeader = eyebrow != null || title != null || subtitle != null;

    return SafeArea(
      top: false,
      child: Padding(
        // The keyboard inset lives here so no sheet can forget it and bury its
        // own text field.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
          ),
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (handle) ...[
                  const SizedBox(width: double.infinity, child: SheetHandle()),
                  const SizedBox(height: 16),
                ],
                if (hasHeader) ...[
                  if (eyebrow != null) SectionLabel(eyebrow!, padding: const EdgeInsets.only(bottom: 6)),
                  if (title != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            title!,
                            style: IntesharText.display(color: cs.onSurface),
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 12),
                          trailing!,
                        ],
                      ],
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
                Flexible(
                  child: scrollable ? SingleChildScrollView(child: child) : child,
                ),
                if (footer != null) ...[
                  const SizedBox(height: 16),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
