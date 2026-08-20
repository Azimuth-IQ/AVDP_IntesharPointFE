import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Guarantees a minimum **hit box** without changing what the child paints.
///
/// Material's own buttons get this from `MaterialTapTargetSize.padded`, but the
/// implementation behind it (`_InputPadding`) is private, so anything we build
/// by hand out of a raw `InkWell`/`GestureDetector` silently ships whatever
/// height the caller asked for as the literal tap target. The POS "Sell"
/// button was a 36dp target on a handheld until its call site was bumped —
/// a floor in the widget is the only fix that survives the next call site.
///
/// The child is laid out at its natural size and centred; taps that land in the
/// surrounding slack are redirected to the child's centre, so the ink ripple
/// still starts inside the visible control instead of the padding.
///
/// It only ever *grows* the box: when the incoming constraints cannot fit
/// [minSize] (a caller has already pinned a smaller height) the constraint
/// wins and nothing overflows.
class MinTapTarget extends SingleChildRenderObjectWidget {
  /// The smallest interactive box. 48×48 is the Material / WCAG 2.5.5 floor and
  /// the default here; pass `Size(0, 48)` to floor the height only.
  final Size minSize;

  const MinTapTarget({
    super.key,
    this.minSize = const Size(48, 48),
    required Widget super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMinTapTarget(minSize);

  @override
  void updateRenderObject(BuildContext context, RenderMinTapTarget renderObject) {
    renderObject.minSize = minSize;
  }
}

/// Render object behind [MinTapTarget]. Public only so it can be named in a
/// `expect(find.byType(...))`-style test; use [MinTapTarget] in widget code.
class RenderMinTapTarget extends RenderShiftedBox {
  RenderMinTapTarget(this._minSize, [RenderBox? child]) : super(child);

  Size _minSize;
  Size get minSize => _minSize;
  set minSize(Size value) {
    if (_minSize == value) return;
    _minSize = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => child == null
      ? 0.0
      : math.max(child!.getMinIntrinsicWidth(height), minSize.width);

  @override
  double computeMaxIntrinsicWidth(double height) => child == null
      ? 0.0
      : math.max(child!.getMaxIntrinsicWidth(height), minSize.width);

  @override
  double computeMinIntrinsicHeight(double width) => child == null
      ? 0.0
      : math.max(child!.getMinIntrinsicHeight(width), minSize.height);

  @override
  double computeMaxIntrinsicHeight(double width) => child == null
      ? 0.0
      : math.max(child!.getMaxIntrinsicHeight(width), minSize.height);

  Size _sizeFor(BoxConstraints constraints, ChildLayouter layoutChild) {
    final target = child;
    if (target == null) return Size.zero;
    final childSize = layoutChild(target, constraints);
    return constraints.constrain(
      Size(
        math.max(childSize.width, minSize.width),
        math.max(childSize.height, minSize.height),
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _sizeFor(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _sizeFor(constraints, ChildLayoutHelper.layoutChild);
    final target = child;
    if (target != null) {
      (target.parentData! as BoxParentData).offset =
          Alignment.center.alongOffset(size - target.size as Offset);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (super.hitTest(result, position: position)) return true;
    final target = child;
    // Outside the painted child but inside our (larger) box: hand the hit to
    // the child at its centre, which is what makes the slack tappable.
    if (target == null || !size.contains(position)) return false;
    final centre = target.size.center(Offset.zero);
    return result.addWithRawTransform(
      transform: MatrixUtils.forceToPoint(centre),
      position: centre,
      hitTest: (BoxHitTestResult result, Offset probe) =>
          target.hitTest(result, position: centre),
    );
  }
}
