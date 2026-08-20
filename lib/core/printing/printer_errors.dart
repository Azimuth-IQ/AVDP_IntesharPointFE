import 'package:flutter/services.dart';

/// UX-49: what to tell the operator when a receipt did not print.
///
/// Printing failures are NOT API failures: every transport throws a plain
/// `Exception`/`PlatformException` (`printer_service.dart`, the Kotlin channels
/// in `android/.../*PrinterChannel.kt`), so the app-wide `friendlyError` — which
/// keys off `ApiException.statusCode` — cannot recognise any of them and falls
/// through to its "no API error" branch, `errNetwork`
/// ("مشكلة في الاتصال — تحقق من الشبكة"). That sent an operator whose printer is
/// out of paper to check the WiFi, with a sold, unprinted code on screen.
///
/// The strings are bilingual literals rather than ARB entries on purpose: this
/// vocabulary is printer-hardware specific and lives with the transports it
/// describes.
///
/// Matching is on the native error CODE first (`PlatformException.code`, set by
/// our own Kotlin channels) and only then on message keywords, because vendor
/// SDK messages are free-form English coming off the device.
String printerErrorMessage(Object? e, {required bool ar}) {
  final code = e is PlatformException ? e.code.toUpperCase() : '';
  final raw = _text(e).toLowerCase();

  // ── Consumables and hardware state — the most common real causes ───────────
  if (_has(raw, ['no paper', 'out of paper', 'paper end', 'paperend', 'lack of paper', 'paper is out'])) {
    return ar
        ? 'لا يوجد ورق في الطابعة — ضع لفة ورق جديدة ثم أعد الطباعة.'
        : 'The printer is out of paper — load a new roll, then reprint.';
  }
  if (_has(raw, ['cover', 'lid open', 'door open'])) {
    return ar
        ? 'غطاء الطابعة مفتوح — أغلقه ثم أعد الطباعة.'
        : "The printer's cover is open — close it, then reprint.";
  }
  if (_has(raw, ['overheat', 'temperature', 'too hot', 'thermal head'])) {
    return ar
        ? 'الطابعة ساخنة — انتظر نصف دقيقة ثم أعد الطباعة.'
        : 'The printer is overheated — wait about half a minute, then reprint.';
  }
  if (_has(raw, ['battery', 'voltage', 'power low', 'low power'])) {
    return ar
        ? 'بطارية الجهاز منخفضة للطباعة — وصّل الشاحن ثم أعد الطباعة.'
        : 'Battery is too low to print — plug in the charger, then reprint.';
  }
  if (_has(raw, ['busy', 'printing in progress'])) {
    return ar
        ? 'الطابعة مشغولة بطباعة أخرى — انتظر لحظة ثم أعد الطباعة.'
        : 'The printer is busy with another job — wait a moment, then reprint.';
  }

  // ── Nothing to print to ───────────────────────────────────────────────────
  if (code == 'NO_SERVICE' ||
      code == 'NOT_FOUND' ||
      _has(raw, [
        'no printer connected',
        'not bound',
        'not available',
        'not installed',
        'no answer from',
        'not attached',
        'permission',
      ])) {
    return ar
        ? 'لا توجد طابعة متصلة — افتح إعدادات الطابعة واربطها ثم أعد الطباعة.'
        : 'No printer is connected — open printer setup, connect it, then reprint.';
  }

  // ── The link to the printer dropped mid-job ───────────────────────────────
  if (code == 'SPP_FAIL' ||
      code == 'USB_FAIL' ||
      _has(raw, [
        'socket',
        'broken pipe',
        'closed',
        'disconnect',
        'timed out',
        'timeout',
        'read failed',
        'write failed',
        'connection reset',
        'gatt',
      ])) {
    return ar
        ? 'انقطع الاتصال بالطابعة — تأكد أنها مشغّلة وقريبة، ثم أعد الطباعة.'
        : 'Lost the connection to the printer — make sure it is switched on and nearby, then reprint.';
  }

  // ── This terminal cannot render this receipt ──────────────────────────────
  if (code == 'UNSUPPORTED' ||
      e is UnsupportedError ||
      _has(raw, ['cannot print a graphical receipt', 'android-only', 'needs a tcp socket'])) {
    return ar
        ? 'هذه الطابعة لا تدعم طباعة هذا الإيصال — اختر طابعة أخرى من الإعدادات.'
        : 'This printer cannot print this receipt — pick another printer in setup.';
  }
  if (e is StateError || _has(raw, ['rasteriz', 'decode'])) {
    return ar
        ? 'تعذّر تجهيز الإيصال للطباعة — أعد الطباعة.'
        : 'The receipt could not be prepared for printing — try again.';
  }

  // Deliberately NOT a network message: the printer is the thing that failed.
  return ar
      ? 'تعذّرت الطباعة — تحقق من الطابعة (ورق، تشغيل، اتصال) ثم أعد الطباعة.'
      : 'Printing failed — check the printer (paper, power, connection), then reprint.';
}

String _text(Object? e) {
  if (e is PlatformException) return '${e.code} ${e.message ?? ''} ${e.details ?? ''}';
  return e?.toString() ?? '';
}

bool _has(String haystack, List<String> needles) =>
    needles.any(haystack.contains);
