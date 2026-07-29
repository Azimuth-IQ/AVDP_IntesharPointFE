import 'dart:convert';

/// How the receipt physically reaches the printer.
///
/// CR-06: the receipt is built **once** as ESC/POS bytes
/// (`escpos_builder.dart`) and every transport below sends *those exact bytes* —
/// which is what makes the output identical on every device. [intent] is the one
/// exception and the reason this refactor exists: it hands the *content* to
/// another app, which re-renders it with its own font and margins.
///
/// Declaration order is the tie-break order used by the picker; auto-connect
/// preference lives in `auto_connect.dart`.
enum PrinterTransport {
  /// Sunmi's built-in head via the `IWoyouService` AIDL `sendRAWData`.
  /// The ONLY path confirmed on real hardware — keep it first, keep it working.
  sunmi,

  /// Bluetooth **Classic** SPP (RFCOMM, UUID 0000_1101). What nearly every
  /// external ESC/POS thermal printer actually speaks.
  spp,

  /// USB OTG bulk transfer to a USB printer-class interface.
  usb,

  /// Raw TCP to port 9100 (the JetDirect convention) over WiFi/LAN.
  tcp,

  /// Bluetooth **LE** GATT writes. Rare for thermal printers — kept because a
  /// handful of BLE-bridged units exist and it is what shipped before.
  ble,

  /// Android `ACTION_SEND` to a vendor print app (Rovo/BLD
  /// `com.bld.settings.print`). **Lossy**: we send text, the other app decides
  /// how it looks. Last resort only.
  intent,
}

/// A specific printer we can send to: a transport plus whatever addresses it.
///
/// [id] is transport-specific and is the persistence key:
/// * [PrinterTransport.spp] / [PrinterTransport.ble] — MAC address
/// * [PrinterTransport.usb] — `vendorId:productId`
/// * [PrinterTransport.tcp] — `host:port`
/// * [PrinterTransport.sunmi] / [PrinterTransport.intent] — fixed, one per device
class PrinterTarget {
  final PrinterTransport transport;
  final String id;
  final String name;

  const PrinterTarget({
    required this.transport,
    this.id = '',
    this.name = '',
  });

  /// The Sunmi inner printer. There is exactly one per device, so it needs no id.
  static const sunmiInner = PrinterTarget(
    transport: PrinterTransport.sunmi,
    id: 'inner',
    name: 'Sunmi Printer',
  );

  /// The vendor print app (Rovo/BLD). Also exactly one per device.
  static const vendorIntent = PrinterTarget(
    transport: PrinterTransport.intent,
    id: 'com.bld.settings.print',
    name: 'Rovo Printer',
  );

  static PrinterTarget tcpAt(String host, int port, {String name = ''}) =>
      PrinterTarget(
        transport: PrinterTransport.tcp,
        id: '$host:$port',
        name: name.isNotEmpty ? name : '$host:$port',
      );

  /// What to show an operator. Falls back to the address so two nameless rows
  /// are still distinguishable.
  String get label => name.trim().isNotEmpty ? name.trim() : id;

  /// True only for [PrinterTransport.intent]: the bytes we built are NOT what
  /// prints, because a different app lays the content out. The UI must say so —
  /// an operator comparing two shops' receipts deserves to know why they differ.
  bool get isApproximate => transport == PrinterTransport.intent;

  /// A device-fixed printer needs no discovery, pairing or address.
  bool get isBuiltIn =>
      transport == PrinterTransport.sunmi || transport == PrinterTransport.intent;

  /// Host part of a [PrinterTransport.tcp] id.
  String get host {
    final i = id.lastIndexOf(':');
    return i < 0 ? id : id.substring(0, i);
  }

  /// Port part of a [PrinterTransport.tcp] id; 9100 when unparseable.
  int get port {
    final i = id.lastIndexOf(':');
    if (i < 0) return 9100;
    return int.tryParse(id.substring(i + 1)) ?? 9100;
  }

  PrinterTarget withName(String value) =>
      PrinterTarget(transport: transport, id: id, name: value);

  Map<String, dynamic> toJson() => {
    'transport': transport.name,
    'id': id,
    'name': name,
  };

  static PrinterTarget? fromJson(Map<String, dynamic> json) {
    final raw = json['transport'] as String?;
    if (raw == null) return null;
    PrinterTransport? t;
    for (final e in PrinterTransport.values) {
      if (e.name == raw) t = e;
    }
    if (t == null) return null;
    return PrinterTarget(
      transport: t,
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
    );
  }

  String encode() => jsonEncode(toJson());

  /// Reads back [encode]. Returns null on anything unparseable — a corrupt or
  /// future-version preference must never crash the POS on launch, it must just
  /// mean "nothing remembered".
  static PrinterTarget? decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Identity is transport + address. The NAME is cosmetic and changes when the
  /// OS learns a better one, so it must not affect equality or the remembered
  /// device would stop matching itself.
  @override
  bool operator ==(Object other) =>
      other is PrinterTarget && other.transport == transport && other.id == id;

  @override
  int get hashCode => Object.hash(transport, id);

  @override
  String toString() => '${transport.name}:$id ($label)';
}
