import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/core/printing/printer_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UX-55: "connected" used to be a claim made once, at adoption, and never
/// re-checked — so a printer switched off or carried out of range kept a green
/// chip, an enabled Print button, and (worst of all) silenced the pre-sale
/// "no printer connected" warning. The failure then surfaced only after a
/// voucher had been burned.
///
/// These tests pin the two properties that make the re-probe safe to run on the
/// sale screen: it changes only what the UI is allowed to CLAIM, and it never
/// puts a byte on the wire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sunmiChannel = MethodChannel('inteshar/sunmi_printer');
  const rovoChannel = MethodChannel('inteshar/rovo_printer');
  const sppChannel = MethodChannel('inteshar/spp_printer');
  const usbChannel = MethodChannel('inteshar/usb_printer');
  const centermChannel = MethodChannel('inteshar/centerm_printer');

  const job = PrintJob(bytes: <int>[27, 64, 79, 75, 10], text: 'OK');

  late TestDefaultBinaryMessenger messenger;

  /// Every method any transport was asked to perform, in order. A probe is only
  /// allowed to appear in here as a lookup — never as a write.
  late List<String> calls;

  var sunmiPresent = false;
  var sppConnectFails = false;
  var bonded = <Map<String, Object?>>[];
  var usbAttached = <Map<String, Object?>>[];

  void mock(MethodChannel channel, Future<Object?>? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    calls = [];
    sunmiPresent = false;
    sppConnectFails = false;
    bonded = [];
    usbAttached = [];
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    mock(sunmiChannel, (call) async {
      calls.add('sunmi.${call.method}');
      return switch (call.method) {
        'isAvailable' => sunmiPresent,
        'printRaw' => true,
        _ => null,
      };
    });
    mock(centermChannel, (call) async {
      calls.add('centerm.${call.method}');
      return call.method == 'isAvailable' ? false : null;
    });
    mock(rovoChannel, (call) async {
      calls.add('rovo.${call.method}');
      return call.method == 'isAvailable' ? false : null;
    });
    mock(sppChannel, (call) async {
      calls.add('spp.${call.method}');
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'bondedDevices':
          return bonded;
        case 'connect':
          if (sppConnectFails) {
            throw PlatformException(code: 'SPP_FAIL', message: 'printer is off');
          }
          return true;
        case 'disconnect':
        case 'write':
          return true;
      }
      return null;
    });
    mock(usbChannel, (call) async {
      calls.add('usb.${call.method}');
      return switch (call.method) {
        'list' => usbAttached,
        'hasPermission' => true,
        'requestPermission' => true,
        'write' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final c in [sunmiChannel, rovoChannel, sppChannel, usbChannel, centermChannel]) {
      messenger.setMockMethodCallHandler(c, null);
    }
  });

  /// The service plus a live read of its published state — `Notifier.state` is
  /// protected, so a test asks the container the way the UI does.
  late ProviderContainer container;
  PrinterState published() => container.read(printerServiceProvider);

  Future<PrinterService> service() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    final svc = container.read(printerServiceProvider.notifier);
    await svc.autoConnect();
    return svc;
  }

  /// The rule that makes a probe safe to run while a voucher sheet is open.
  bool wroteBytes(List<String> calls) => calls.any((c) =>
      c.endsWith('.write') || c.endsWith('.printRaw') || c.endsWith('.printText'));

  test('a probe never writes bytes, on any transport', () async {
    sunmiPresent = true;
    bonded = [
      {'address': 'AA:BB:CC:DD:EE:FF', 'name': 'XP-58', 'isPrinterClass': true},
    ];
    usbAttached = [
      {
        'id': '1155:22339',
        'name': 'POS-80',
        'vendorId': 1155,
        'productId': 22339,
        'isPrinterClass': true,
        'hasPermission': true,
      },
    ];
    final svc = await service();

    for (final target in [
      PrinterTarget.sunmiInner,
      const PrinterTarget(transport: PrinterTransport.spp, id: 'AA:BB:CC:DD:EE:FF'),
      const PrinterTarget(transport: PrinterTransport.usb, id: '1155:22339'),
    ]) {
      await svc.use(target);
      calls.clear();
      await svc.verifyConnection();
      expect(wroteBytes(calls), isFalse,
          reason: 'probing ${target.transport.name} put bytes on the wire — '
              'a probe that can print is worse than no probe');
      expect(calls, isNotEmpty, reason: 'the probe asked the transport nothing at all');
    }
  });

  test('a printer that stops answering goes amber, and stays selected', () async {
    sunmiPresent = true;
    final svc = await service();
    await svc.use(PrinterTarget.sunmiInner);
    expect(published().isReady, isTrue);

    // The head is gone (device swapped, service died).
    sunmiPresent = false;
    expect(await svc.verifyConnection(), isFalse);

    expect(published().isReady, isFalse,
        reason: 'the chip may no longer claim a working printer');
    expect(published().isUnreachable, isTrue);
    expect(published().hasPrinter, isTrue,
        reason: 'the operator\'s choice of printer must survive a failed probe, '
            'so an already-sold code is never trapped behind our own guess');
    expect(svc.target, PrinterTarget.sunmiInner);
  });

  test('a Bluetooth printer that is switched off fails its probe', () async {
    bonded = [
      {'address': 'AA:BB:CC:DD:EE:FF', 'name': 'XP-58', 'isPrinterClass': true},
    ];
    final svc = await service();
    await svc.use(
      const PrinterTarget(transport: PrinterTransport.spp, id: 'AA:BB:CC:DD:EE:FF'),
    );
    expect(published().isReady, isTrue);

    sppConnectFails = true;
    expect(await svc.verifyConnection(), isFalse);
    expect(published().isUnreachable, isTrue);
  });

  test('a receipt that actually printed clears the amber state', () async {
    // A probe can be wrong; paper cannot. The strongest evidence wins.
    sunmiPresent = true;
    final svc = await service();
    await svc.use(PrinterTarget.sunmiInner);
    sunmiPresent = false;
    await svc.verifyConnection();
    expect(published().isUnreachable, isTrue);

    await svc.send(job);
    expect(published().isReady, isTrue);
  });

  test('"two printers found, pick one" is not the same state as "none found"',
      () async {
    // Auto-connect deliberately refuses to guess between two plausible printers;
    // that decision is WAITING for the operator and used to be reported to them
    // as "no printer found".
    bonded = [
      {'address': 'AA:11:22:33:44:55', 'name': 'XP-58', 'isPrinterClass': true},
      {'address': 'BB:11:22:33:44:55', 'name': 'POS-80 Printer', 'isPrinterClass': true},
    ];
    await service();

    expect(published().needsChoice, isTrue);
    expect(published().hasPrinter, isFalse);
    expect(published().candidates.length, 2);
  });
}
