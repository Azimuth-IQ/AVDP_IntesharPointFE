/// B-127: how a governorate selection resolves for each agent tier.
///
/// A SUB agent covers exactly one governorate, so picking a second replaces the
/// first — the multi-select behaves like a radio group without a second widget
/// to keep in step. A MAIN agent may operate across several and is untouched.
///
/// Pure so the rule can be asserted directly. Living inside the form's
/// `onChanged` would mean the only way to test it was to drive the widget, and
/// a test that rebuilds the same set arithmetic would pass either way.
Set<String> resolveGovernorateChoice({
  required Set<String> current,
  required Set<String> next,
  required bool singleChoice,
}) {
  if (!singleChoice || next.length <= 1) return next;
  // Keep what the operator just TAPPED, not an arbitrary member: `next` is
  // unordered, so picking `next.first` could silently keep the old value and
  // look like the tap did nothing.
  final added = next.difference(current);
  return {added.isNotEmpty ? added.first : next.first};
}
