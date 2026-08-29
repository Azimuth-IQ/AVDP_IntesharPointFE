import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
import 'package:inteshar/shared/widgets/confirm_dialog.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// **The** multi-select mechanism (UX-11).
///
/// The HQ console is a set of near-identical card lists — agents, catalog,
/// batches, POS points, vouchers — and every repeated operation on them was
/// N × (open the row menu → choose → confirm → wait → reload). That is the
/// largest single multiplier on HQ's time in the product, and it was not a
/// missing checkbox on one screen: it was a missing *idea*.
///
/// One screen had already grown its own answer. The Batches tab hand-rolled a
/// `_selecting` bool, a `Set<String> _selected`, a "Select shown" button, a
/// progress block and a bulk runner — about eighty lines that the next list to
/// need selection would have had to copy, drifting on every detail that matters
/// (does a failure stay ticked? does the confirm name the count? does a partial
/// run report success?). Four copies of that would be four different answers to
/// "what happens when 7 of 10 succeed".
///
/// So the whole thing lives here:
///
/// * [SelectionState] — the state machine. Pure, immutable, no `BuildContext`;
///   a page holds one field and rebuilds from the value it is handed back.
/// * [SelectionModeButton] / [SelectionCheckbox] — the two controls a list needs
///   in its toolbar and in its rows.
/// * [SelectionBar] — the contextual action bar: live count, tri-state
///   select-all, the actions, the progress line, the confirmation, the run and
///   the reporting. A page supplies [BulkAction]s and gets all of that.
/// * [BulkOutcome] / [bulkOutcome] — what a run leaves behind. Moved here from
///   `batch_add_page.dart`, where it was written for exactly this contract and
///   was reachable only by importing a 2 300-line page.
///
/// ## Two rules this file exists to make unbreakable
///
/// **Partial failure is reported honestly.** A bulk run over independent server
/// calls does not stop at the first refusal and does not roll back — there is no
/// transaction to roll back INTO, and stopping early leaves an arbitrary prefix
/// applied while doing less work. It finishes, then says how many landed, and
/// leaves the failures SELECTED so "retry the three that failed" is one tap.
/// See [bulkOutcome].
///
/// **A destructive batch is hard to trigger.** [SelectionBar] renders
/// destructive actions LAST, behind a divider, in danger tone — never in the
/// first, closest slot. Every confirmation names the count structurally (the
/// dialog prints it itself; a caller cannot forget), and
/// [BulkSeverity.irreversible] additionally makes the operator TYPE the count
/// before the button will enable. Deleting forty rows should cost more than one
/// reflex tap.

/// Inline bilingual label. Arabic is the primary locale; this file's strings are
/// few and structural, so they are resolved here rather than churning the .arb.
String _tr(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;

// ── Selection state (pure) ───────────────────────────────────────────────────

/// Where the select-all affordance stands relative to the rows on screen.
enum SelectAllState {
  /// Nothing visible is ticked.
  none,

  /// Some but not all of the visible rows are ticked.
  some,

  /// Every visible row is ticked.
  all,
}

/// Whether a list is selecting, and what is ticked.
///
/// Immutable and free of `BuildContext`, so the interesting behaviour — what
/// "select all" means when the list is filtered, what survives a reload, what a
/// half-failed run leaves behind — is testable without pumping a widget. Every
/// mutator returns a NEW state; a page stores one field and calls `setState`.
@immutable
class SelectionState {
  /// Selection mode is on: rows show checkboxes and the action bar is up.
  final bool active;

  /// The ticked row ids. Always unmodifiable — a page that mutated this
  /// directly would change state without a rebuild.
  final Set<String> ids;

  const SelectionState._(this.active, this.ids);

  /// Not selecting, nothing ticked. The starting value for every list.
  ///
  /// `final`, not `const`: a const constructor taking a `Set` is fine today, but
  /// this file's whole point is that six pages share it, and CI runs a newer
  /// Flutter than local (see [IntesharWeight.registered] for what that costs).
  static final SelectionState off = SelectionState._(false, const <String>{});

  bool get isEmpty => ids.isEmpty;
  bool get isNotEmpty => ids.isNotEmpty;

  /// The live count shown in the action bar.
  int get count => ids.length;

  bool contains(String id) => ids.contains(id);

  SelectionState _to(bool active, Set<String> next) =>
      SelectionState._(active, Set<String>.unmodifiable(next));

  /// Turn selection mode on, keeping whatever is ticked.
  SelectionState enter() => active ? this : _to(true, ids);

  /// Leave selection mode and drop every tick. Leaving must not leave rows
  /// silently armed for the next entry.
  SelectionState exit() => off;

  /// What the toolbar button does: on → off (dropping ticks), off → on.
  SelectionState toggleMode() => active ? off : _to(true, const <String>{});

  /// Tick or untick one row.
  ///
  /// This ENTERS selection mode on its own, so a long-press on a row can start a
  /// selection without a separate trip to the toolbar first.
  SelectionState toggle(String id) {
    final next = <String>{...ids};
    if (!next.remove(id)) next.add(id);
    return _to(true, next);
  }

  /// Tick every id in [visible] — the rows currently PASSING THE FILTERS, not
  /// the whole dataset. "Select all" on a filtered list must mean what the
  /// operator can see; anything else acts on rows they never looked at.
  SelectionState selectAll(Iterable<String> visible) =>
      _to(true, <String>{...ids, ...visible});

  /// Untick every id in [visible], leaving ticks on rows the filters hide.
  SelectionState deselectAll(Iterable<String> visible) {
    final drop = visible.toSet();
    return _to(true, <String>{...ids.where((id) => !drop.contains(id))});
  }

  /// One tap of the select-all affordance, given what is on screen.
  SelectionState toggleAll(Iterable<String> visible) =>
      allStateFor(visible) == SelectAllState.all
          ? deselectAll(visible)
          : selectAll(visible);

  /// Drop every tick but stay in selection mode.
  SelectionState clear() => _to(active, const <String>{});

  /// Drop ticks for rows that no longer exist.
  ///
  /// Called after a reload. Without it a deleted row stays counted, the bar says
  /// "5 selected" over four rows, and the next bulk run sends a request for an
  /// id the server has never heard of.
  SelectionState retain(Iterable<String> existing) {
    final live = existing.toSet();
    return _to(active, <String>{...ids.where(live.contains)});
  }

  /// Adopt what a finished run left behind — see [bulkOutcome].
  SelectionState applyOutcome(BulkOutcome outcome) =>
      _to(outcome.keepSelecting, outcome.stillSelected);

  /// Tri-state for the select-all control, over the rows on screen.
  SelectAllState allStateFor(Iterable<String> visible) {
    var seen = 0;
    var ticked = 0;
    for (final id in visible) {
      seen++;
      if (ids.contains(id)) ticked++;
    }
    if (seen == 0 || ticked == 0) return SelectAllState.none;
    return ticked == seen ? SelectAllState.all : SelectAllState.some;
  }

  /// Everything ticked, ordered by where [visible] puts it — so a run works
  /// down the list the operator is looking at rather than in hash order.
  ///
  /// **Everything**, not just the visible rows. [selectAll] and [deselectAll]
  /// are deliberately bounded to what is on screen, so a selection can outlive
  /// the filter that made it: tick five, then narrow the search, and two of the
  /// five are now off-screen. The bar still says "5 selected", so a run that
  /// quietly did three and then dropped the other two would be a lie told by the
  /// most load-bearing number in the whole mechanism. The count and the run are
  /// the same set; the visible order is only an ordering.
  List<String> targetsIn(Iterable<String> visible) {
    final out = <String>[];
    final taken = <String>{};
    for (final id in visible) {
      if (ids.contains(id) && taken.add(id)) out.add(id);
    }
    for (final id in ids) {
      if (taken.add(id)) out.add(id);
    }
    return out;
  }
}

// ── What a bulk run leaves behind ────────────────────────────────────────────

/// What a bulk action leaves behind (UX-11).
///
/// Extracted from widget state deliberately: this rule decides what happens
/// after a recall half-succeeded, and a rule living in widget state cannot be
/// tested without driving the page.
///
/// The rule: a bulk run over independent server calls does not stop at the first
/// refusal and does not roll back. There is no transaction to roll back INTO — a
/// "rollback" would be more mutations that can themselves fail — and stopping
/// early leaves an arbitrary prefix applied while doing less work. So it
/// finishes, then reports.
///
/// The failures stay SELECTED. That is not a convenience: it is the only record
/// of which rows still need attention, and it makes "retry the three that
/// failed" one tap instead of a hunt.
class BulkOutcome {
  /// Rows still needing attention. Empty on a clean run.
  final Set<String> stillSelected;

  /// Whether the list should remain in selection mode.
  final bool keepSelecting;

  /// How many succeeded — reported first, because a recall that moved 7 of 10
  /// HAS changed the world, and a message that only counts failures reads as
  /// "nothing happened", which is the reading that gets it run twice.
  final int succeeded;

  const BulkOutcome({
    required this.stillSelected,
    required this.keepSelecting,
    required this.succeeded,
  });

  bool get clean => stillSelected.isEmpty;
}

BulkOutcome bulkOutcome({required int attempted, required Set<String> failedIds}) =>
    BulkOutcome(
      stillSelected: {...failedIds},
      keepSelecting: failedIds.isNotEmpty,
      succeeded: attempted - failedIds.length,
    );

// ── Actions ──────────────────────────────────────────────────────────────────

/// How much a batch action can hurt, which decides how hard it is to trigger.
enum BulkSeverity {
  /// Reversible and routine (resume, grant). Standard confirmation.
  ordinary,

  /// Reversible but harmful while it lasts — pausing stock, deactivating a shop,
  /// withdrawing codes. Red confirmation, rendered away from the routine
  /// actions.
  danger,

  /// Cannot be undone. Everything [danger] does, plus the operator has to TYPE
  /// the number of rows before the confirm button will enable.
  irreversible,
}

/// The plural noun a bulk message names ("10 batches", "١٠ دفعات").
///
/// Required, not defaulted to "items": "Delete 40?" is a question about nothing.
@immutable
class BulkUnit {
  final String ar;
  final String en;
  const BulkUnit({required this.ar, required this.en});

  String of(BuildContext context) => _tr(context, ar, en);
}

/// One action offered over a selection.
@immutable
class BulkAction {
  final String label;
  final IconData icon;
  final BulkSeverity severity;

  /// The confirmation's headline, given the number of rows. The dialog prints
  /// the count itself as well (see [showBulkConfirm]), so a confirmation can
  /// never end up not naming it — but the sentence should read naturally too.
  final String Function(int count) title;

  /// What it will do, given the number of rows.
  final String Function(int count) body;

  /// Applies the action to ONE row. Throwing fails that row and the run carries
  /// on; the id is then kept selected for a retry.
  final Future<void> Function(String id) run;

  /// Asked BEFORE the confirmation, for an action that needs a parameter the
  /// selection cannot supply — "grant how many points to these twelve agents?".
  /// Return false to abort; the confirmation is then never shown.
  ///
  /// It runs first, not last, so the operator answers the question while the
  /// action is still cancellable, and the confirmation can state the answer.
  final Future<bool> Function()? prepare;

  /// Greys the action out with a reason — e.g. an action only some selections
  /// support. Null means enabled.
  final String? disabledReason;

  const BulkAction({
    required this.label,
    required this.icon,
    required this.title,
    required this.body,
    required this.run,
    this.severity = BulkSeverity.ordinary,
    this.disabledReason,
    this.prepare,
  });

  bool get destructive => severity != BulkSeverity.ordinary;
}

// ── Confirmation ─────────────────────────────────────────────────────────────

/// Latin digits for [text], so a count typed on an Arabic keyboard counts.
///
/// Maps Arabic-Indic (U+0660–0669) and Extended Arabic-Indic (U+06F0–06F9)
/// digits down, and drops grouping separators — the app formats counts with
/// `NumberFormat('#,###')`, so the number on screen may well carry commas that
/// the operator copies back.
String normalizeDigits(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + (rune - 0x0660));
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + (rune - 0x06F0));
    } else if (rune >= 0x30 && rune <= 0x39) {
      out.writeCharCode(rune);
    }
    // Everything else — separators, spaces, stray letters — is dropped.
  }
  return out.toString();
}

/// Whether what the operator typed unlocks an [BulkSeverity.irreversible]
/// confirmation for [count] rows.
///
/// Exact match only. "About right" is not a safety gate, and an empty box must
/// never pass — that is the reflex-tap this exists to stop.
bool bulkConfirmMatches(String typed, int count) {
  final digits = normalizeDigits(typed);
  if (digits.isEmpty) return false;
  return int.tryParse(digits) == count;
}

/// Asks before running [action] over [count] rows. Returns true to proceed.
///
/// The count is printed by the dialog itself rather than being left to the
/// caller's sentence, so no batch confirmation in the app can be countless.
Future<bool> showBulkConfirm(
  BuildContext context, {
  required BulkAction action,
  required int count,
  required BulkUnit unit,
}) {
  final countLine = '$count ${unit.of(context)}';
  if (action.severity != BulkSeverity.irreversible) {
    return showConfirm(
      context,
      title: action.title(count),
      body: '$countLine\n\n${action.body(count)}',
      confirmLabel: action.label,
      destructive: action.destructive,
    );
  }
  return _showTypeCountConfirm(
    context,
    action: action,
    count: count,
    countLine: countLine,
  );
}

/// The irreversible gate: the confirm button stays dead until the operator types
/// the number of rows.
Future<bool> _showTypeCountConfirm(
  BuildContext context, {
  required BulkAction action,
  required int count,
  required String countLine,
}) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final danger = ctx.status.danger;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final unlocked = bulkConfirmMatches(controller.text, count);
          return AlertDialog(
            icon: Icon(Icons.warning_amber_rounded, color: danger),
            title: Text(action.title(count), textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(countLine, style: IntesharText.display(color: danger)),
                IntesharSpacing.gapSm,
                Text(action.body(count),
                    style: Theme.of(ctx).textTheme.bodyMedium),
                IntesharSpacing.gapLg,
                Text(
                  _tr(
                    ctx,
                    'اكتب العدد ($count) للتأكيد:',
                    'Type the number ($count) to confirm:',
                  ),
                  style: IntesharText.body(color: cs.onSurfaceVariant),
                ),
                IntesharSpacing.gapSm,
                TextField(
                  key: const Key('bulk-confirm-count-field'),
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.singleLineFormatter,
                  ],
                  textAlign: TextAlign.center,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(isDense: true),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                key: const Key('bulk-confirm-cancel'),
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_tr(ctx, 'إلغاء', 'Cancel')),
              ),
              FilledButton(
                key: const Key('bulk-confirm-confirm'),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed:
                    unlocked ? () => Navigator.pop(ctx, true) : null,
                child: Text(action.label),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return ok == true;
}

// ── Controls ─────────────────────────────────────────────────────────────────

/// The toolbar switch that turns selection mode on and off.
class SelectionModeButton extends StatelessWidget {
  final SelectionState state;
  final ValueChanged<SelectionState> onChanged;

  /// Null while something else on the page owns the list (a bulk run, a load).
  final bool enabled;

  const SelectionModeButton({
    super.key,
    required this.state,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _tr(context, 'تحديد متعدد', 'Select several'),
      isSelected: state.active,
      icon: const Icon(Icons.checklist, size: 20),
      onPressed: enabled ? () => onChanged(state.toggleMode()) : null,
    );
  }
}

/// The per-row tick.
///
/// Keeps the full 48dp target on purpose: this is driven one tap per row, many
/// rows in a row, on a handheld. `VisualDensity.compact` shrinks it to ~40dp,
/// which is where mis-taps on the neighbouring row start.
class SelectionCheckbox extends StatelessWidget {
  final bool selected;
  final ValueChanged<bool>? onChanged;

  /// Announced by a screen reader — "row" alone says nothing about which one.
  final String? semanticLabel;

  const SelectionCheckbox({
    super.key,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final box = Checkbox(
      value: selected,
      onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
    );
    if (semanticLabel == null) return box;
    return Semantics(label: semanticLabel, child: box);
  }
}

// ── The contextual action bar ────────────────────────────────────────────────

/// The bar that appears above a list in selection mode.
///
/// It owns the whole batch lifecycle so that no page has to: the live count, the
/// tri-state select-all, the confirmation, the per-row loop, the progress line,
/// the outcome and the message. A page supplies [actions] and hands back the
/// [SelectionState] it is given.
class SelectionBar extends StatefulWidget {
  final SelectionState state;

  /// The ids of the rows currently ON SCREEN (after search and filters).
  /// Select-all and the run order both come from this, never from the full set.
  final List<String> visibleIds;

  final ValueChanged<SelectionState> onChanged;
  final List<BulkAction> actions;

  /// What the rows are called in the confirmations and messages.
  final BulkUnit unit;

  /// Re-fetch the list. Awaited after every run — clean or not — because even a
  /// half-failed run changed rows.
  final Future<void> Function()? onCompleted;

  /// Fires when a run starts and ends, so the page can make its rows inert.
  final ValueChanged<bool>? onBusyChanged;

  const SelectionBar({
    super.key,
    required this.state,
    required this.visibleIds,
    required this.onChanged,
    required this.actions,
    required this.unit,
    this.onCompleted,
    this.onBusyChanged,
  });

  @override
  State<SelectionBar> createState() => _SelectionBarState();
}

class _SelectionBarState extends State<SelectionBar> {
  /// The label of the action in flight, or null when idle.
  String? _running;
  int _done = 0;
  int _total = 0;

  bool get _busy => _running != null;

  Future<void> _run(BulkAction action) async {
    if (_busy) return;
    final targets = widget.state.targetsIn(widget.visibleIds);
    if (targets.isEmpty) return;

    final prepare = action.prepare;
    if (prepare != null) {
      final proceed = await prepare();
      if (!proceed || !mounted) return;
    }

    final ok = await showBulkConfirm(
      context,
      action: action,
      count: targets.length,
      unit: widget.unit,
    );
    if (!ok || !mounted) return;

    setState(() {
      _running = action.label;
      _done = 0;
      _total = targets.length;
    });
    widget.onBusyChanged?.call(true);

    // The ids that refused. Kept rather than counted, because they are what the
    // operator does next: they stay ticked, so "which three failed?" is answered
    // by the list itself and one more tap retries exactly those.
    final failed = <String>{};
    Object? lastError;
    for (final id in targets) {
      try {
        await action.run(id);
      } catch (e) {
        failed.add(id);
        lastError = e;
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (!mounted) return;

    final outcome =
        bulkOutcome(attempted: targets.length, failedIds: failed);
    setState(() {
      _running = null;
      _done = 0;
      _total = 0;
    });
    widget.onBusyChanged?.call(false);
    widget.onChanged(widget.state.applyOutcome(outcome));

    await widget.onCompleted?.call();
    if (!mounted) return;

    final unit = widget.unit.of(context);
    if (outcome.clean) {
      showOk(
        context,
        _tr(
          context,
          'تم على ${targets.length} $unit',
          'Done on ${targets.length} $unit',
        ),
      );
    } else {
      // Lead with what DID happen. A message that only says "3 failed" reads as
      // "nothing happened" — which is the reading that gets it run twice.
      final why = friendlyError(lastError!, context);
      showError(
        context,
        _tr(
          context,
          'تم على ${outcome.succeeded} من ${targets.length}. '
              'بقيت ${failed.length} محددة لإعادة المحاولة: $why',
          'Done on ${outcome.succeeded} of ${targets.length}. '
              'The ${failed.length} that failed stay selected to retry: $why',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.state.active) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final selected = widget.state.count;
    final allState = widget.state.allStateFor(widget.visibleIds);

    // Destructive actions go LAST, behind a divider. The first slot is the one
    // a hurried thumb lands in; it must not be able to delete forty rows.
    final ordered = <BulkAction>[
      ...widget.actions.where((a) => !a.destructive),
      ...widget.actions.where((a) => a.destructive),
    ];
    final firstDestructive = ordered.indexWhere((a) => a.destructive);

    return InkCard(
      ruleColor: context.tones.brandInk,
      density: CardDensity.dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _tr(context, 'محدد: $selected', '$selected selected'),
                  style: IntesharText.bodyLg(
                      color: cs.onSurface, w: IntesharWeight.heavy),
                ),
              ),
              IconButton(
                tooltip: _tr(context, 'إنهاء التحديد', 'Exit selection'),
                icon: const Icon(Icons.close, size: 20),
                onPressed:
                    _busy ? null : () => widget.onChanged(widget.state.exit()),
              ),
            ],
          ),
          Wrap(
            spacing: IntesharSpacing.sm,
            runSpacing: IntesharSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _selectAll(allState),
              for (var i = 0; i < ordered.length; i++) ...[
                if (i == firstDestructive && i > 0)
                  // A `Wrap` gives its children loose constraints, so a bare
                  // vertical `Hairline` would measure zero high and the divider
                  // that separates "harmless" from "destructive" would not be
                  // drawn at all. The box is what gives it a height.
                  const SizedBox(
                    height: 32,
                    child: Hairline(axis: Axis.vertical, indent: 4, endIndent: 4),
                  ),
                _actionButton(ordered[i], selected),
              ],
            ],
          ),
          if (_busy) ...[
            IntesharSpacing.gapMd,
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
                minHeight: 6,
              ),
            ),
            IntesharSpacing.gapSm,
            Text(
              _tr(
                context,
                '$_running — $_done من $_total',
                '$_running — $_done of $_total',
              ),
              style: IntesharText.body(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  /// Tri-state select-all over the rows on screen. The label says which way it
  /// will go, so it is never a coin flip.
  Widget _selectAll(SelectAllState allState) {
    final cs = Theme.of(context).colorScheme;
    final everything = allState == SelectAllState.all;
    final label = everything
        ? _tr(context, 'إلغاء تحديد المعروض', 'Clear shown')
        : _tr(context, 'تحديد المعروض', 'Select shown');
    final enabled = !_busy && widget.visibleIds.isNotEmpty;
    void toggle() =>
        widget.onChanged(widget.state.toggleAll(widget.visibleIds));

    return InkWell(
      key: const Key('selection-select-all'),
      onTap: enabled ? toggle : null,
      borderRadius: BorderRadius.circular(IntesharRadii.sm),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: IntesharSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              tristate: true,
              value: switch (allState) {
                SelectAllState.all => true,
                SelectAllState.none => false,
                SelectAllState.some => null,
              },
              onChanged: enabled ? (_) => toggle() : null,
            ),
            Text(label, style: IntesharText.bodyLg(color: cs.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(BulkAction action, int selected) {
    final tone = action.destructive ? context.status.danger : null;
    final enabled =
        !_busy && selected > 0 && action.disabledReason == null;
    final button = OutlinedButton.icon(
      onPressed: enabled ? () => _run(action) : null,
      style: tone == null
          ? null
          : OutlinedButton.styleFrom(foregroundColor: tone),
      icon: Icon(action.icon, size: 16),
      label: Text(action.label),
    );
    final reason = action.disabledReason;
    if (reason == null) return button;
    return Tooltip(message: reason, child: button);
  }
}
