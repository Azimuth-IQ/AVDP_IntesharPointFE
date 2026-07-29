/// One receipt, ready to print.
///
/// CR-06: [bytes] is the single source of truth — the ESC/POS stream built by
/// `escpos_builder.dart`. Every raw transport (Sunmi AIDL, Bluetooth SPP, USB,
/// TCP, BLE) writes these bytes **unmodified**, so the paper looks the same
/// whatever the device.
///
/// [text] exists only for the lossy vendor-intent transport, which cannot accept
/// bytes at all: it hands a string to another app that re-renders it. Carrying
/// both on the job is what lets the POS stop branching on the printer brand —
/// it builds one job and the transport decides which field it can use.
class PrintJob {
  final List<int> bytes;
  final String text;

  const PrintJob({required this.bytes, this.text = ''});

  /// A job with no text fallback — printable on every raw transport, and on the
  /// intent transport only if [text] is supplied elsewhere.
  const PrintJob.escPos(this.bytes, {this.text = ''});

  bool get hasText => text.trim().isNotEmpty;
}
