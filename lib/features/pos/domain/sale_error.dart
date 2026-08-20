import 'package:inteshar/core/api/api_exception.dart';

/// What to tell the operator when a sale attempt (`/product/draw`,
/// `/product/draw/bulk`) did not come back with a card (UX-62).
///
/// A 402 (no withdrawal limit left), a 409 (pool empty) and a plain timeout all
/// used to render as the same red sentence, which hid the only distinction that
/// matters at the counter:
///
/// * the **server answered** — nothing was claimed, nothing was debited, the
///   card is still there and the operator can fix the cause and sell again;
/// * **no answer came back** — the draw is atomic server-side, so the card may
///   ALREADY be sold and the code is sitting in a response that never arrived.
///
/// In the second case the sheet's per-attempt `clientRef` makes a retry re-serve
/// that same sale rather than burning a second card — but nothing on screen ever
/// said so, and nothing told the operator that a card they walked away from is
/// findable in التقارير.
class PosSaleFailure {
  /// True when the request may have reached the server, so the sale's outcome is
  /// genuinely unknown to the app.
  final bool outcomeUnknown;

  /// One line naming what happened.
  final String headline;

  /// One or two lines naming what to do about it.
  final String detail;

  const PosSaleFailure({
    required this.outcomeUnknown,
    required this.headline,
    required this.detail,
  });
}

/// Classifies a failed sale attempt.
///
/// [friendly] is the app-wide `friendlyError(e, context)` text; it carries the
/// backend's own message for the statuses that have one worth showing, so it is
/// used verbatim as the headline whenever the server actually answered.
PosSaleFailure posSaleFailure(
  Object? e, {
  required bool ar,
  required String friendly,
}) {
  final status = ApiException.from(e)?.statusCode;

  // No status at all = a timeout, a dropped connection, or an unparsable
  // response: the request may well have been served. 5xx is the same story —
  // a gateway or a crash after the card was claimed looks identical from here.
  final unknown = status == null || status >= 500;

  if (!unknown) {
    return PosSaleFailure(
      outcomeUnknown: false,
      headline: friendly,
      detail: ar
          ? 'لم تُبَع أي بطاقة ولم يُخصم أي مبلغ. عالج السبب ثم أعد المحاولة.'
          : 'No card was sold and nothing was charged. Fix the cause, then try again.',
    );
  }

  return PosSaleFailure(
    outcomeUnknown: true,
    headline: ar
        ? 'لم يصل رد من الخادم — قد تكون البطاقة قد بيعت فعلاً.'
        : 'No answer from the server — the card may already be sold.',
    detail: ar
        ? 'اضغط "إعادة المحاولة": ستُعاد نفس العملية ولن تُخصم بطاقة ثانية. '
            'إذا خرجت من هذه الشاشة، ابحث عن العملية في تبويب التقارير وأعد طباعتها من هناك.'
        : 'Tap Retry: it re-serves the SAME sale — it cannot charge you twice. '
            'If you leave this screen, look the sale up in the التقارير (Reports) tab and reprint it from there.',
  );
}
