import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/pos/presentation/pos_brand.dart';

/// The POS app-bar title: the owning agent's logo and the shop's own name.
///
/// PROD-011: the client found the bar untidy ("what is this text under the shop name?") and the
/// name cut to "العقل …" on a Sunmi V2. The second line ("العداد المباشر · حُدّث الآن", a freshness
/// stamp) is gone — a failed refresh still shows its own banner on the page — and the name may use
/// two lines, so a normal shop name is shown in full on a 5" screen.
class PosAppBarTitle extends StatelessWidget {
  const PosAppBarTitle({
    super.key,
    required this.shopName,
    this.leading = const PosBrandMark(size: 26),
    this.onLongPress,
  });

  final String shopName;

  /// White-label: the owning agent's logo (falls back to the shop's initial), never the Inteshar
  /// star (B-083). Replaceable so the title can be tested without the session providers.
  final Widget leading;

  /// Long-press opens diagnostics (support's way in on a locked-down terminal).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          // Expanded so the name wraps and then ellipsises inside the bar instead of overflowing.
          Expanded(
            child: Text(
              shopName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IntesharType.codec(
                size: 17,
                w: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.2,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
