import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/printing/auto_connect.dart';
import 'package:inteshar/core/printing/centerm_printer.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/printer_target.dart';
import 'package:inteshar/core/printing/rovo_printer.dart';
import 'package:inteshar/core/printing/sunmi_printer.dart';
import 'package:inteshar/core/printing/transports/network_printer.dart';
import 'package:inteshar/core/printing/transports/spp_printer.dart';
import 'package:inteshar/core/printing/transports/usb_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything this terminal can print to, right now, without scanning.
///
/// A BLE scan is deliberately NOT part of this: it takes eight seconds and is
/// something the operator asks for, not something the POS does on launch.
class PrinterInventory {
  final bool sunmiAvailable;
  final bool centermAvailable;
  final bool intentAvailable;
  final List<SppDevice> bondedClassic;
  final List<UsbPrinterDevice> usbDevices;
  final PrinterTarget? remembered;

  const PrinterInventory({
    this.sunmiAvailable = false,
    this.centermAvailable = false,
    this.intentAvailable = false,
    this.bondedClassic = const [],
    this.usbDevices = const [],
    this.remembered,
  });

  /// A bonded Classic device that plausibly IS a printer. Class first (when the
  /// unit bothers to declare one), name heuristic second — most cheap ESC/POS
  /// printers declare nothing useful.
  static bool isLikelyPrinter(SppDevice d) {
    // A loopback that accepts bytes and prints nothing must never be adopted —
    // it would false-confirm every sale. See isVirtualLoopbackName.
    if (isVirtualLoopbackName(d.name)) return false;
    return d.isPrinterClass || looksLikePrinterName(d.name);
  }

  /// Everything enumerable — used only to tell whether a *remembered* device is
  /// still paired/plugged in. Never used to pick a printer.
  List<PrinterTarget> get all => [
    ...bondedClassic.map((d) => d.toTarget()),
    ...usbDevices.map((d) => d.toTarget()),
  ];

  /// The subset eligible for automatic selection.
  ///
  /// USB entries need a granted permission: a device we cannot write to without
  /// throwing a system dialog is not something to adopt behind the operator's
  /// back on the sale screen.
  List<PrinterTarget> get candidates => [
    ...bondedClassic.where(isLikelyPrinter).map((d) => d.toTarget()),
    ...usbDevices
        .where((d) => d.isPrinterClass && d.hasPermission)
        .map((d) => d.toTarget()),
  ];
}

/// The app's single printer connection.
///
/// CR-06: one ESC/POS byte stream, many transports. [send] is the only place
/// that knows how bytes reach paper, so callers build a [PrintJob] and stop
/// caring what brand of terminal they are on.
class PrinterService extends Notifier<PrinterState> {
  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _writeChar;
  PrinterTarget? _target;

  static const _prefTarget = 'last_printer_target';
  // Pre-CR-06 keys: a bare BLE MAC + name. Still read (so an existing shop keeps
  // its printer across the upgrade) and still written for the MAC prefill.
  static const _prefLegacyId = 'last_printer_id';
  static const _prefLegacyName = 'last_printer_name';

  @override
  PrinterState build() {
    // Fire-and-forget: the POS must render immediately, and every failure path
    // inside just leaves the state disconnected.
    autoConnect();
    return const PrinterState();
  }

  PrinterTarget? get target => _target;

  bool get isConnected =>
      _target != null && state.status == PrinterStatus.connected;

  /// How long a re-probe may take before it is called a failure. A probe runs
  /// while an operator is looking at a voucher sheet, so it must resolve in
  /// about the time it takes to read the price — not in an RFCOMM timeout.
  static const _probeTimeout = Duration(seconds: 4);

  /// One probe at a time. Two in flight would fight over the same socket.
  bool _probing = false;

  /// True while [send] is pushing a receipt. A probe must never touch a
  /// transport mid-receipt — re-opening an RFCOMM socket under a half-written
  /// voucher would cut the customer's code in two.
  bool _sending = false;

  /// True when the active transport re-renders our content instead of printing
  /// our bytes (the vendor intent path). The UI must say so.
  bool get isApproximate => _target?.isApproximate ?? false;

  // ---------------------------------------------------------------- discovery

  /// What is attached right now. Cheap enough to call on every picker open.
  Future<PrinterInventory> discover() async {
    final sunmi = await _safeBool(SunmiPrinter.isAvailable);
    final centerm = await _safeBool(CentermPrinter.isAvailable);
    final intent = await _safeBool(RovoPrinter.isAvailable);
    final classic = await SppPrinter.bondedDevices();
    final usb = await UsbPrinter.list();
    classic.sort((a, b) {
      final ap = PrinterInventory.isLikelyPrinter(a) ? 0 : 1;
      final bp = PrinterInventory.isLikelyPrinter(b) ? 0 : 1;
      if (ap != bp) return ap - bp;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return PrinterInventory(
      sunmiAvailable: sunmi,
      centermAvailable: centerm,
      intentAvailable: intent,
      bondedClassic: classic,
      usbDevices: usb,
      remembered: await rememberedTarget(),
    );
  }

  static Future<bool> _safeBool(Future<bool> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------- auto-connect

  /// Pick and adopt a printer at POS start. See [decideAutoConnect] for the
  /// policy; the short version is *Sunmi → remembered → one obvious candidate →
  /// otherwise ask*.
  Future<void> autoConnect() async {
    try {
      final inv = await discover();
      // Detection is slow enough that an impatient operator can open the picker
      // and connect while it runs. Their choice wins — never reset it.
      if (_target != null) return;

      // A printer can be paired but switched off. Each failure is retired and
      // the decision retaken, so a dead remembered device falls through to the
      // one candidate present, and a dead candidate still falls through to the
      // vendor print app rather than leaving the counter with nothing.
      final failed = <PrinterTarget>{};
      for (var attempt = 0; attempt < 4; attempt++) {
        final remembered = inv.remembered;
        final decision = decideAutoConnect(
          sunmiAvailable: inv.sunmiAvailable && !failed.contains(PrinterTarget.sunmiInner),
          centermAvailable:
              inv.centermAvailable && !failed.contains(PrinterTarget.centermInner),
          intentAvailable:
              inv.intentAvailable && !failed.contains(PrinterTarget.vendorIntent),
          remembered: (remembered == null || failed.contains(remembered))
              ? null
              : remembered,
          available: inv.all,
          candidates: inv.candidates.where((c) => !failed.contains(c)).toList(),
        );

        if (decision.action == AutoConnectAction.connect) {
          if (await _adopt(decision)) return;
          failed.add(decision.target!);
          continue;
        }

        if (_target != null) return;
        if (decision.action == AutoConnectAction.ask) {
          // More than one plausible printer. Printing a paid voucher to the
          // wrong one is worse than one tap of setup, so stop here and let the
          // operator choose in the picker.
          state = PrinterState(
            status: PrinterStatus.needsChoice,
            candidates: decision.candidates,
          );
        } else {
          state = const PrinterState();
        }
        return;
      }
    } catch (_) {
      // Detection must never take the POS down with it.
    }
  }

  /// Acts on a [AutoConnectAction.connect] decision. Returns false (leaving the
  /// state disconnected rather than in an alarming error) if it did not connect.
  Future<bool> _adopt(AutoConnectDecision decision) async {
    if (decision.action != AutoConnectAction.connect) return false;
    if (_target != null) return true;
    try {
      await use(
        decision.target!,
        interactive: false,
        // Only a printer we picked ourselves is worth persisting. Persisting the
        // vendor-intent fallback would pin the shop to the lossy path forever,
        // even after they pair a real printer — rule 2 would beat rule 3.
        remember: decision.reason == AutoConnectReason.soleCandidate,
      );
      return true;
    } catch (_) {
      state = const PrinterState();
      return false;
    }
  }

  // -------------------------------------------------------------- connecting

  /// Adopt [target], connecting its transport as needed.
  ///
  /// [interactive] gates anything that can put a system dialog on screen (the
  /// USB permission prompt) — false during auto-connect.
  Future<void> use(
    PrinterTarget target, {
    bool interactive = true,
    bool remember = true,
  }) async {
    state = PrinterState(
      status: PrinterStatus.connecting,
      deviceName: target.label,
      target: target,
    );
    try {
      switch (target.transport) {
        case PrinterTransport.sunmi:
          if (!await SunmiPrinter.isAvailable()) {
            throw Exception('Sunmi printer service not available');
          }
        case PrinterTransport.centerm:
          if (!await CentermPrinter.isAvailable()) {
            throw Exception('Centerm printer service not available');
          }
        case PrinterTransport.spp:
          await SppPrinter.connect(target.id);
        case PrinterTransport.usb:
          var granted = await UsbPrinter.hasPermission(target.id);
          if (!granted && interactive) {
            granted = await UsbPrinter.requestPermission(target.id);
          }
          if (!granted) throw Exception('USB permission not granted');
        case PrinterTransport.tcp:
          if (!await NetworkPrinter.probe(target.host, target.port)) {
            throw Exception('No answer from ${target.host}:${target.port}');
          }
        case PrinterTransport.ble:
          await _connectBle(BluetoothDevice.fromId(target.id));
        case PrinterTransport.intent:
          if (!await RovoPrinter.isAvailable()) {
            throw Exception('Vendor print service not installed');
          }
      }
      _target = target;
      if (remember) await _remember(target);
      state = PrinterState(
        status: PrinterStatus.connected,
        deviceName: target.label,
        target: target,
      );
    } catch (e) {
      _target = null;
      state = const PrinterState(status: PrinterStatus.error);
      rethrow;
    }
  }

  /// Connect to a BLE peripheral picked out of a scan.
  Future<void> connectBle(BluetoothDevice device, {String? name}) async {
    final label = (name ?? device.platformName).trim();
    await use(
      PrinterTarget(
        transport: PrinterTransport.ble,
        id: device.remoteId.str,
        name: label.isNotEmpty ? label : device.remoteId.str,
      ),
    );
  }

  /// GATT connect + writable-characteristic discovery. Unchanged from the
  /// pre-CR-06 Bluetooth path.
  Future<void> _connectBle(BluetoothDevice device) async {
    // Ensure any in-progress scan is fully stopped before opening a GATT
    // connection.  On Android the BLE scanner and GATT stack share internal
    // resources; connecting while a scan is still tearing down causes the
    // infamous GATT error 133 (ANDROID_SPECIFIC_ERROR).
    await FlutterBluePlus.stopScan();
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      // mtu: null disables the automatic MTU negotiation that flutter_blue_plus
      // performs right after connect().  Many cheap ESC/POS printers have
      // minimal BLE stacks that crash when hit with an immediate MTU request,
      // causing a GATT 133 disconnect.  We use the safe default (23 bytes) and
      // rely on our own chunking in send() instead.
      await device.connect(timeout: const Duration(seconds: 10), mtu: null);
      _bleDevice = device;
      _writeChar = null;

      final services = await device.discoverServices();
      for (final s in services) {
        final svcUuid = s.serviceUuid.str.toLowerCase();
        // Skip standard BLE GATT services. flutter_blue_plus returns short UUIDs
        // (e.g. "1800") rather than the canonical full form, so we check both:
        //   - Short form: 1800 (Generic Access), 1801 (Generic Attribute)
        //   - Long form:  0000xxxx-0000-1000-8000-00805f9b34fb
        const skipServices = {'1800', '1801'};
        final isStandardShort = skipServices.contains(svcUuid);
        final isStandardLong =
            svcUuid.startsWith('0000') &&
            svcUuid.endsWith('-0000-1000-8000-00805f9b34fb');
        if (isStandardShort || isStandardLong) continue;
        for (final c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            _writeChar = c;
            break;
          }
        }
        if (_writeChar != null) break;
      }
      if (_writeChar == null) {
        throw Exception('No writable characteristic — this is not a printer');
      }
      debugPrint('[BT] writeChar=${_writeChar?.characteristicUuid.str}');
    } catch (e) {
      _bleDevice = null;
      _writeChar = null;
      try {
        await device.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final t = _target;
    if (t?.transport == PrinterTransport.spp) await SppPrinter.disconnect();
    try {
      await _bleDevice?.disconnect();
    } catch (_) {}
    _bleDevice = null;
    _writeChar = null;
    _target = null;
    state = const PrinterState(status: PrinterStatus.idle);
  }

  // ------------------------------------------------------------------ probing

  /// Re-check that the adopted printer is still actually there.
  ///
  /// UX-55: [use] validates a transport **once**, at adoption, and until now
  /// nothing ever re-checked it. A printer switched off, unplugged, out of paper
  /// on the shelf or carried out of range kept a green "connected" chip and an
  /// enabled Print button — and, worse, silenced the pre-sale "no printer
  /// connected" warning, which is the app's one chance to set expectations
  /// BEFORE an irreversible tap. The failure then surfaced only after the code
  /// had been burned.
  ///
  /// The contract, in order of importance:
  ///
  /// * **It never writes bytes.** Not a status query, not an `ESC @`, nothing
  ///   that could reach the head. A probe that prints — or that a loopback
  ///   "printer" answers happily — is worse than no probe at all.
  /// * **It never blocks a sale.** Callers fire it and forget; it self-limits
  ///   with [_probeTimeout] and it does not gate any button.
  /// * **It never adopts, drops or swaps a target.** The only thing it changes
  ///   is whether the state reads [PrinterStatus.connected] or
  ///   [PrinterStatus.unreachable] — the operator's choice of printer survives
  ///   a failed probe, because a probe can be wrong and a sold code must never
  ///   be trapped behind our guess.
  ///
  /// Returns true when the printer answered.
  Future<bool> verifyConnection() async {
    final t = _target;
    if (t == null) return false;
    // A connect is in flight; it will publish its own verdict in a moment.
    if (state.status == PrinterStatus.connecting) return false;
    // A receipt is on the wire. That IS the live proof of reachability, and
    // interrupting it is the one thing this must never do.
    if (_sending) return true;
    if (_probing) return state.status == PrinterStatus.connected;
    _probing = true;
    try {
      final ok =
          await _probe(t).timeout(_probeTimeout, onTimeout: () => false);
      // The operator may have picked a different printer while we were asking.
      if (_target != t) return ok;
      if (ok) {
        if (state.status != PrinterStatus.connected) {
          state = PrinterState(
            status: PrinterStatus.connected,
            deviceName: t.label,
            target: t,
          );
        }
      } else if (state.status != PrinterStatus.unreachable) {
        state = PrinterState(
          status: PrinterStatus.unreachable,
          deviceName: t.label,
          target: t,
        );
      }
      return ok;
    } finally {
      _probing = false;
    }
  }

  /// The per-transport reachability question, asked without printing anything.
  ///
  /// Each case is the cheapest check that can distinguish "the printer is there"
  /// from "the printer is gone", using only what the transport already exposes:
  /// no new native surface, and no byte ever reaches a print head.
  Future<bool> _probe(PrinterTarget t) async {
    try {
      switch (t.transport) {
        // The built-in heads answer through their vendor service binder. A dead
        // binder means the head is genuinely unusable; a live one cannot tell us
        // about paper, which only the print itself will.
        case PrinterTransport.sunmi:
          return await SunmiPrinter.isAvailable();
        case PrinterTransport.centerm:
          return await CentermPrinter.isAvailable();
        case PrinterTransport.intent:
          return await RovoPrinter.isAvailable();

        // The native side reuses a live RFCOMM socket and only re-opens a dead
        // one, so this is a socket check, not a print. A powered-off or
        // out-of-range printer fails the re-open and throws — which is exactly
        // the answer we came for.
        case PrinterTransport.spp:
          await SppPrinter.connect(t.id);
          return true;

        // Unplugged devices vanish from the list; a revoked permission means the
        // next write would fail on a system dialog we refuse to raise mid-sale.
        case PrinterTransport.usb:
          final attached = await UsbPrinter.list();
          if (!attached.any((d) => d.id == t.id)) return false;
          return await UsbPrinter.hasPermission(t.id);

        // Opens and immediately destroys a socket — the same check [use] runs
        // when adopting a network printer.
        case PrinterTransport.tcp:
          return await NetworkPrinter.probe(t.host, t.port);

        // GATT tells us whether the link is still up. Losing the write
        // characteristic means the connection was torn down under us.
        case PrinterTransport.ble:
          final d = _bleDevice;
          if (d == null || _writeChar == null) return false;
          return d.isConnected;
      }
    } catch (_) {
      // Any refusal, timeout or missing plugin reads as "not reachable". This is
      // deliberately not an error state: the printer is still SELECTED.
      return false;
    }
  }

  // ------------------------------------------------------------------ sending

  /// Send one receipt. The transport decides HOW; [PrintJob.bytes] decides WHAT,
  /// identically everywhere except the vendor-intent path (see [isApproximate]).
  Future<void> send(PrintJob job) async {
    final t = _target;
    if (t == null) throw Exception('No printer connected');
    // Marks the transport busy so [verifyConnection] stays off it (UX-55).
    _sending = true;
    try {
      switch (t.transport) {
        case PrinterTransport.sunmi:
          await SunmiPrinter.printRaw(job.bytes);
        case PrinterTransport.centerm:
          await CentermPrinter.printRaw(job.bytes);
        case PrinterTransport.spp:
          await SppPrinter.write(t.id, job.bytes);
        case PrinterTransport.usb:
          await UsbPrinter.write(t.id, job.bytes);
        case PrinterTransport.tcp:
          await NetworkPrinter.send(t.host, t.port, job.bytes);
        case PrinterTransport.ble:
          await _bleWrite(job.bytes);
        case PrinterTransport.intent:
          if (!job.hasText) {
            throw Exception('This printer cannot print a graphical receipt');
          }
          await RovoPrinter.printText(job.text);
      }
      // A receipt that reached the printer is the strongest possible proof of
      // reachability — stronger than any probe — so a state left amber by an
      // earlier failed probe corrects itself here.
      if (_target == t && state.status == PrinterStatus.unreachable) {
        state = PrinterState(
          status: PrinterStatus.connected,
          deviceName: t.label,
          target: t,
        );
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _bleWrite(List<int> bytes) async {
    final ch = _writeChar;
    if (ch == null) throw Exception('No printer connected');
    // Without explicit MTU negotiation the BLE ATT default is 23 bytes,
    // leaving exactly 20 bytes of payload per write.  Staying at 20 is safe
    // for all ESC/POS printers regardless of whether they negotiate a larger MTU.
    const chunkSize = 20;
    final withoutResponse = ch.properties.writeWithoutResponse;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      await ch.write(bytes.sublist(i, end), withoutResponse: withoutResponse);
      if (withoutResponse) {
        await Future.delayed(const Duration(milliseconds: 30));
      }
    }
  }

  // ------------------------------------------------------------------ BLE scan

  Stream<List<ScanResult>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults;
  }

  void stopScan() => FlutterBluePlus.stopScan();

  /// BLE peripherals the system already knows about — a separate list from the
  /// bonded **Classic** devices in [PrinterInventory.bondedClassic]. Do not merge
  /// the two in the UI: they are different radios and connect differently.
  Future<List<BluetoothDevice>> knownBleDevices() async {
    final seen = <String, BluetoothDevice>{};
    try {
      for (final d in await FlutterBluePlus.bondedDevices) {
        seen[d.remoteId.str] = d;
      }
    } catch (_) {/* unsupported platform / permission denied */}
    try {
      // 1800 = Generic Access; every GATT peripheral exposes it.
      for (final d in await FlutterBluePlus.systemDevices([Guid('1800')])) {
        seen.putIfAbsent(d.remoteId.str, () => d);
      }
    } catch (_) {}
    final out = seen.values.toList()
      ..sort((a, b) {
        final ap = looksLikePrinterName(a.platformName) ? 0 : 1;
        final bp = looksLikePrinterName(b.platformName) ? 0 : 1;
        if (ap != bp) return ap - bp;
        return a.platformName.toLowerCase().compareTo(
          b.platformName.toLowerCase(),
        );
      });
    return out;
  }

  /// The best human name available for a device.
  ///
  /// `device.platformName` is only populated once the OS has learned the name —
  /// from a bond or a GATT read. A freshly SCANNED peripheral usually carries its
  /// name ONLY in the advertisement (`advertisementData.advName`), which nothing
  /// here was reading, so every scanned row fell back to the generic label and
  /// the whole list looked nameless. Falls back to the MAC, which at least
  /// distinguishes one row from another.
  static String displayName(BluetoothDevice device, {AdvertisementData? adv}) {
    final platform = device.platformName.trim();
    if (platform.isNotEmpty) return platform;
    final advertised = adv?.advName.trim() ?? '';
    if (advertised.isNotEmpty) return advertised;
    return device.remoteId.str;
  }

  /// Whether [device] advertises a name that reads like a printer — used to mark
  /// the likely candidate in the picker so an operator isn't guessing.
  static bool looksLikePrinter(BluetoothDevice device) =>
      looksLikePrinterName(device.platformName);

  // ------------------------------------------------------------- persistence

  Future<void> _remember(PrinterTarget target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTarget, target.encode());
    // Keep the legacy keys in step so the picker's MAC prefill still works.
    if (target.transport == PrinterTransport.ble ||
        target.transport == PrinterTransport.spp) {
      await prefs.setString(_prefLegacyId, target.id);
      await prefs.setString(_prefLegacyName, target.name);
    }
  }

  /// The last printer that actually printed here, if any.
  ///
  /// Falls back to the pre-CR-06 keys, which only ever held a BLE MAC — so an
  /// existing shop keeps its printer through the upgrade instead of being sent
  /// back to the setup screen.
  Future<PrinterTarget?> rememberedTarget() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = PrinterTarget.decode(prefs.getString(_prefTarget));
      if (stored != null) return stored;
      final legacyId = prefs.getString(_prefLegacyId);
      if (legacyId == null || legacyId.trim().isEmpty) return null;
      return PrinterTarget(
        transport: PrinterTransport.ble,
        id: legacyId,
        name: prefs.getString(_prefLegacyName) ?? legacyId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> get lastPrinterId async {
    final t = await rememberedTarget();
    if (t == null) return null;
    if (t.transport == PrinterTransport.spp ||
        t.transport == PrinterTransport.ble) {
      return t.id;
    }
    return null;
  }
}

enum PrinterStatus {
  idle,
  connecting,
  connected,
  error,

  /// Several plausible printers were found and none was remembered, so nothing
  /// was connected on purpose — the operator has to say which one.
  needsChoice,

  /// A printer IS selected, but the last probe could not reach it — switched
  /// off, unplugged, out of range (UX-55). Deliberately not [error] and
  /// deliberately not [idle]: the choice of printer stands and printing is still
  /// allowed to be attempted, we simply stop promising it will work.
  unreachable,
}

class PrinterState {
  final PrinterStatus status;
  final String? deviceName;
  final PrinterTarget? target;

  /// Only populated with [PrinterStatus.needsChoice].
  final List<PrinterTarget> candidates;

  const PrinterState({
    this.status = PrinterStatus.idle,
    this.deviceName,
    this.target,
    this.candidates = const [],
  });

  /// True when what prints is NOT the byte stream we built.
  bool get isApproximate => target?.isApproximate ?? false;

  /// A printer is selected AND answered the last probe. This is the only state
  /// allowed to look green.
  bool get isReady => status == PrinterStatus.connected;

  /// A printer is selected, reachable or not. Printing is offered on this, never
  /// on [isReady]: a probe can be wrong, and an already-sold code must never be
  /// trapped behind our own guess about the hardware.
  bool get hasPrinter =>
      status == PrinterStatus.connected || status == PrinterStatus.unreachable;

  /// The last probe failed. The chip says so instead of claiming a connection.
  bool get isUnreachable => status == PrinterStatus.unreachable;

  /// Auto-connect found more than one plausible printer and deliberately picked
  /// none — a decision is WAITING for the operator. Flattening this into "no
  /// printer found" (which it is not) meant nobody was ever told (UX-55).
  bool get needsChoice => status == PrinterStatus.needsChoice;

  PrinterState copyWith({
    PrinterStatus? status,
    String? deviceName,
    PrinterTarget? target,
    List<PrinterTarget>? candidates,
  }) => PrinterState(
    status: status ?? this.status,
    deviceName: deviceName ?? this.deviceName,
    target: target ?? this.target,
    candidates: candidates ?? this.candidates,
  );
}

final printerServiceProvider =
    NotifierProvider<PrinterService, PrinterState>(PrinterService.new);
