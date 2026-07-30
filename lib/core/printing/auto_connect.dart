import 'package:inteshar/core/printing/printer_target.dart';

/// What the POS should do about printers when it starts.
enum AutoConnectAction {
  /// Adopt [AutoConnectDecision.target] without asking.
  connect,

  /// Say nothing was picked and let the operator choose. Deliberately NOT a
  /// silent guess.
  ask,

  /// Nothing to connect to and nothing to ask about.
  none,
}

/// Why the decision came out the way it did — surfaced in the UI and asserted
/// in tests, so a change of policy is visible rather than incidental.
enum AutoConnectReason {
  /// A Sunmi inner printer is present. Unambiguous and confirmed on hardware.
  sunmiBuiltIn,

  /// A Centerm/Rovo inner head is present — same standing as Sunmi: built in,
  /// exactly one, and it takes our raw bytes.
  centermBuiltIn,

  /// The transport+address that printed last time is available again.
  remembered,

  /// Exactly one plausible printer is attached; no other device could be meant.
  soleCandidate,

  /// Several plausible printers. Guessing here could print a customer's voucher
  /// on the wrong device — ask instead.
  ambiguous,

  /// No real printer, but the device ships a vendor print app. Lossy output.
  intentFallback,

  /// Nothing at all.
  nothingFound,
}

class AutoConnectDecision {
  final AutoConnectAction action;
  final PrinterTarget? target;
  final AutoConnectReason reason;

  /// Populated for [AutoConnectAction.ask] so the UI can show exactly what it
  /// could not choose between.
  final List<PrinterTarget> candidates;

  const AutoConnectDecision({
    required this.action,
    required this.reason,
    this.target,
    this.candidates = const [],
  });

  bool get isApproximate => target?.isApproximate ?? false;

  @override
  String toString() => 'AutoConnect(${action.name}, ${reason.name}, $target)';
}

/// Decides what to connect to at POS start. Pure — no plugins, no I/O — so the
/// policy can be tested without a printer in hand.
///
/// Priority, and the reasoning for it:
/// 1. **Sunmi inner printer.** It is inside the terminal, there is exactly one,
///    and it takes our raw bytes. Confirmed on hardware.
/// 2. **Centerm/Rovo inner head.** Same standing as Sunmi, and it outranks
///    anything paired for a measured reason: the only bonded device on a ROVOO
///    MTHD-M1 is `VirtualBT`, which accepts every byte and prints nothing.
/// 3. **The remembered printer.** An exact transport+address that already
///    printed for this shop can never be "the wrong device".
/// 4. **A single plausible candidate.** If only one thing on this terminal looks
///    like a printer, connecting to it is what the operator wanted anyway.
/// 5. **Several candidates → ask.** Silently picking one and printing a paid
///    voucher to a stranger's paired device is worse than one tap of setup.
/// 6. **Vendor intent app.** Only when nothing else exists, and the caller must
///    label its output approximate.
///
/// [available] is everything enumerable right now (all bonded Classic devices,
/// all attached USB devices) — used only to skip a remembered device that has
/// been unpaired or unplugged. [candidates] is the much smaller subset that
/// plausibly IS a printer; only these are eligible for rules 4 and 5.
AutoConnectDecision decideAutoConnect({
  required bool sunmiAvailable,
  required bool intentAvailable,
  bool centermAvailable = false,
  required PrinterTarget? remembered,
  required List<PrinterTarget> available,
  required List<PrinterTarget> candidates,
}) {
  if (sunmiAvailable) {
    return const AutoConnectDecision(
      action: AutoConnectAction.connect,
      target: PrinterTarget.sunmiInner,
      reason: AutoConnectReason.sunmiBuiltIn,
    );
  }

  // A built-in head beats anything paired, for the same reasons Sunmi does: it
  // is inside the terminal, there is exactly one, and it takes raw bytes.
  if (centermAvailable) {
    return const AutoConnectDecision(
      action: AutoConnectAction.connect,
      target: PrinterTarget.centermInner,
      reason: AutoConnectReason.centermBuiltIn,
    );
  }

  if (remembered != null &&
      _rememberedIsWorthTrying(
        remembered,
        available: available,
        intentAvailable: intentAvailable,
      )) {
    return AutoConnectDecision(
      action: AutoConnectAction.connect,
      target: remembered,
      reason: AutoConnectReason.remembered,
    );
  }

  // Never count the same physical printer twice (a unit can be both bonded and
  // remembered, or listed by two lookups).
  final unique = <PrinterTarget>[];
  for (final c in candidates) {
    if (!unique.contains(c)) unique.add(c);
  }

  if (unique.length == 1) {
    return AutoConnectDecision(
      action: AutoConnectAction.connect,
      target: unique.single,
      reason: AutoConnectReason.soleCandidate,
    );
  }
  if (unique.length > 1) {
    return AutoConnectDecision(
      action: AutoConnectAction.ask,
      reason: AutoConnectReason.ambiguous,
      candidates: unique,
    );
  }

  if (intentAvailable) {
    return const AutoConnectDecision(
      action: AutoConnectAction.connect,
      target: PrinterTarget.vendorIntent,
      reason: AutoConnectReason.intentFallback,
    );
  }

  return const AutoConnectDecision(
    action: AutoConnectAction.none,
    reason: AutoConnectReason.nothingFound,
  );
}

/// A remembered device is only skipped when we can *prove* it is gone.
///
/// Bonded-Bluetooth and attached-USB lists are authoritative and cheap, so a
/// remembered device missing from them has been unpaired or unplugged — trying
/// it would just burn a ten-second timeout on the sale screen. A network printer
/// cannot be enumerated at all, and a BLE peripheral only appears during a scan
/// we deliberately do not run at startup, so both are simply attempted.
bool _rememberedIsWorthTrying(
  PrinterTarget remembered, {
  required List<PrinterTarget> available,
  required bool intentAvailable,
}) {
  switch (remembered.transport) {
    case PrinterTransport.sunmi:
    case PrinterTransport.centerm:
      // Only reachable when that head reported unavailable — hardware changed.
      return false;
    case PrinterTransport.intent:
      return intentAvailable;
    case PrinterTransport.spp:
    case PrinterTransport.usb:
      return available.contains(remembered);
    case PrinterTransport.ble:
    case PrinterTransport.tcp:
      return true;
  }
}

/// Name-only printer heuristic, shared by the Classic and LE lists.
///
/// Substring matches must be specific enough not to catch everyday devices: a
/// bare `rp` matches "AiRPods", which a test caught.
bool looksLikePrinterName(String name) {
  final n = name.toLowerCase();
  return n.contains('print') ||
      n.contains('rovo') ||
      n.contains('bld') ||
      n.contains('inner') ||
      n.contains('escpos') ||
      n.contains('pos-') ||
      n.contains('pos_') ||
      n.startsWith('pos') ||
      n.contains('rp-') ||
      n.startsWith('rp') ||
      // X-Printer units (the X50 in the registry) advertise as "XP-58"/"XP58",
      // which carries none of the words above.
      n.startsWith('xp') ||
      n.contains('x-print') ||
      n.contains('tm-') ||
      // Sunrise / Capa Z91 have no published SDK; if their heads present as a
      // bonded SPP device at all, these are the names reported in the field.
      n.contains('sunrise') ||
      n.contains('capa') ||
      n.startsWith('z91');
}

/// Bluetooth names that are NOT a printer even though the stack says otherwise.
///
/// Measured on a ROVOO MTHD-M1: the bonded device `VirtualBT`
/// (`18:10:77:00:10:55`) reports Bluetooth major class **IMAGING**, so it looks
/// like the obvious printer — and it is a **black hole**. The OEM patched the
/// framework `BluetoothSocket` to route that name to a loopback `LocalSocket`,
/// so `connect()` succeeds, `write()` returns success, and **nothing prints**.
/// The vendor print engine logs a job for every real print and logged none for
/// ours.
///
/// That is the worst failure this app can have: the POS would mark the voucher
/// printed, confirm it server-side, and hand the customer nothing — on every
/// sale. So these are excluded from auto-connect entirely. The same terminals
/// expose a real raw path ([PrinterTransport.centerm]), which is what auto-connect
/// picks instead.
bool isVirtualLoopbackName(String name) {
  final n = name.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  return n == 'virtualbt' || n.startsWith('virtualbt');
}
