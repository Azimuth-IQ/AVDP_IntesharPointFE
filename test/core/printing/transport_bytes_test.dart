import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/core/printing/printer_target.dart';
import 'package:inteshar/core/printing/transports/network_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// CR-06's whole point: the receipt is built once and **the same bytes** go out
/// over whichever transport is present. A transport that quietly reformatted,
/// truncated or re-encoded the stream would put a different receipt on the paper
/// in one shop than another — which is the bug this change exists to kill.
///
/// The native channels are mocked, so this pins the Dart-side contract (dispatch
/// + byte fidelity), not the Kotlin socket code, which needs hardware.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sunmiChannel = MethodChannel('inteshar/sunmi_printer');
  const rovoChannel = MethodChannel('inteshar/rovo_printer');
  const sppChannel = MethodChannel('inteshar/spp_printer');
  const usbChannel = MethodChannel('inteshar/usb_printer');
  const centermChannel = MethodChannel('inteshar/centerm_printer');

  /// A recognisable ESC/POS fragment: ESC @ (init), text, LF, GS V (cut).
  const receipt = <int>[27, 64, 80, 73, 78, 32, 49, 50, 51, 10, 29, 86, 65, 0];
  const job = PrintJob(bytes: receipt, text: 'PIN 123');

  late Map<String, List<int>> sent;
  late List<String> textSent;
  late TestDefaultBinaryMessenger messenger;

  // What the terminal "has". Default: a bare Android device with neither a Sunmi
  // head nor a vendor print app, so a test opts in to what it is exercising.
  var sunmiPresent = false;
  var vendorAppPresent = false;
  var centermPresent = false;
  var bonded = <Map<String, Object?>>[];
  var sppConnectFails = false;

  void mock(MethodChannel channel, Future<Object?>? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    sent = {};
    textSent = [];
    sunmiPresent = false;
    vendorAppPresent = false;
    centermPresent = false;
    bonded = [];
    sppConnectFails = false;
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    List<int> bytesOf(MethodCall call) =>
        List<int>.from((call.arguments as Map)['bytes'] as Uint8List);

    mock(sunmiChannel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          return sunmiPresent;
        case 'printRaw':
          sent['sunmi'] = bytesOf(call);
          return true;
      }
      return null;
    });
    mock(centermChannel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          return centermPresent;
        case 'printRaw':
          sent['centerm'] = bytesOf(call);
          return true;
      }
      return null;
    });
    mock(rovoChannel, (call) async {
      switch (call.method) {
        case 'isAvailable':
          return vendorAppPresent;
        case 'printText':
          textSent.add((call.arguments as Map)['text'] as String);
          return true;
      }
      return null;
    });
    mock(sppChannel, (call) async {
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
          return true;
        case 'write':
          sent['spp'] = bytesOf(call);
          return true;
      }
      return null;
    });
    mock(usbChannel, (call) async {
      switch (call.method) {
        case 'list':
          return <Map<String, Object?>>[];
        case 'hasPermission':
        case 'requestPermission':
          return true;
        case 'write':
          sent['usb'] = bytesOf(call);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final c in [
      sunmiChannel,
      rovoChannel,
      sppChannel,
      usbChannel,
      centermChannel,
    ]) {
      messenger.setMockMethodCallHandler(c, null);
    }
  });

  /// A service with auto-connect already settled, so a test's explicit choice is
  /// not racing detection.
  Future<PrinterService> service() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final svc = container.read(printerServiceProvider.notifier);
    await svc.autoConnect();
    return svc;
  }

  test('Sunmi, Bluetooth Classic and USB all receive the identical byte stream',
      () async {
    sunmiPresent = true;
    final svc = await service();

    await svc.use(PrinterTarget.sunmiInner);
    await svc.send(job);

    await svc.use(
      const PrinterTarget(transport: PrinterTransport.spp, id: 'AA:11', name: 'XP-58'),
    );
    await svc.send(job);

    await svc.use(
      const PrinterTarget(transport: PrinterTransport.usb, id: '1155:22339'),
    );
    await svc.send(job);

    centermPresent = true;
    await svc.use(PrinterTarget.centermInner);
    await svc.send(job);

    expect(sent.keys.toSet(), {'sunmi', 'spp', 'usb', 'centerm'});
    expect(sent['sunmi'], receipt);
    expect(sent['spp'], receipt,
        reason: 'Bluetooth Classic must not reformat the receipt');
    expect(sent['usb'], receipt, reason: 'USB must not reformat the receipt');
    expect(sent['centerm'], receipt,
        reason: 'the Rovo head gets the SAME bytes as Sunmi — that is the point');
  });

  test('a TCP printer on port 9100 receives the identical byte stream', () async {
    // A real loopback socket — the network transport is pure Dart, so it can be
    // verified end to end without any hardware.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <int>[];
    // use() probes first — that connection opens and closes without sending
    // anything, so wait for actual bytes rather than for the first socket.
    final gotBytes = Completer<void>();
    server.listen((socket) {
      socket.listen((chunk) {
        received.addAll(chunk);
        if (!gotBytes.isCompleted) gotBytes.complete();
      });
    });

    final svc = await service();
    await svc.use(PrinterTarget.tcpAt(server.address.address, server.port));
    await svc.send(job);
    await gotBytes.future.timeout(const Duration(seconds: 5));
    await server.close();

    expect(received, receipt);
  });

  test('the vendor intent path is the ONE that does not send our bytes', () async {
    vendorAppPresent = true;
    final svc = await service();
    await svc.use(PrinterTarget.vendorIntent);
    await svc.send(job);

    expect(sent, isEmpty, reason: 'the intent transport cannot take bytes at all');
    expect(textSent, ['PIN 123']);
    expect(svc.isApproximate, isTrue,
        reason: 'the UI needs this to warn that the output differs');
  });

  test('a byte-only job refuses to print on the intent path rather than printing '
      'something else', () async {
    vendorAppPresent = true;
    final svc = await service();
    await svc.use(PrinterTarget.vendorIntent);
    await expectLater(
      svc.send(const PrintJob.escPos(receipt)),
      throwsA(isA<Exception>()),
    );
    expect(textSent, isEmpty);
  });

  test('sending with nothing connected fails loudly', () async {
    final svc = await service();
    await expectLater(svc.send(job), throwsA(isA<Exception>()));
  });

  test('the connected printer is remembered, transport and all', () async {
    final svc = await service();
    const target =
        PrinterTarget(transport: PrinterTransport.spp, id: 'AA:11', name: 'XP-58');
    await svc.use(target);

    final remembered = await svc.rememberedTarget();
    expect(remembered, target);
    expect(remembered!.transport, PrinterTransport.spp,
        reason: 'reconnecting over the wrong radio would silently never print');
  });

  test('a printer remembered before CR-06 is read back as the BLE device it was',
      () async {
    SharedPreferences.setMockInitialValues({
      'last_printer_id': 'AA:BB:CC:DD:EE:FF',
      'last_printer_name': 'XP-58',
    });
    final svc = await service();
    final remembered = await svc.rememberedTarget();
    expect(remembered?.transport, PrinterTransport.ble);
    expect(remembered?.id, 'AA:BB:CC:DD:EE:FF');
    expect(remembered?.name, 'XP-58',
        reason: 'an existing shop must not be sent back to the setup screen');
  });

  test('the network transport reports an unreachable printer instead of hanging',
      () async {
    // Port 1 on loopback: nothing listens, so probe must simply say no.
    expect(
      await NetworkPrinter.probe(
        InternetAddress.loopbackIPv4.address,
        1,
        timeout: const Duration(milliseconds: 500),
      ),
      isFalse,
    );
  });

  Map<String, Object?> classic(String address, String name) =>
      {'address': address, 'name': name, 'isPrinterClass': false};

  group('auto-connect at POS start', () {
    test('one bonded printer next to a headset connects to the printer', () async {
      bonded = [classic('AA:11', 'XP-58'), classic('EE:55', 'AirPods Pro')];
      final svc = await service();
      expect(svc.target?.id, 'AA:11');
      expect(svc.isConnected, isTrue);
    });

    test('TWO bonded printers connect to NEITHER — it asks instead', () async {
      // The commercial failure this guards: silently adopting one of two paired
      // printers and putting a paid voucher on the wrong counter.
      bonded = [classic('AA:11', 'XP-58'), classic('BB:22', 'POS-9200')];
      final svc = await service();
      expect(svc.target, isNull);
      expect(svc.isConnected, isFalse);
      expect(svc.state.status, PrinterStatus.needsChoice);
      expect(svc.state.candidates.map((c) => c.id),
          unorderedEquals(<String>['AA:11', 'BB:22']));
    });

    test('only headsets are paired → nothing is connected and nothing is asked',
        () async {
      bonded = [classic('EE:55', 'AirPods Pro'), classic('FF:66', 'Car Kit')];
      final svc = await service();
      expect(svc.target, isNull);
      expect(svc.state.status, PrinterStatus.idle);
    });

    test('a paired printer that will not answer falls through to the vendor app',
        () async {
      // Rovo case: the internal head is bonded but dead. Losing the vendor
      // fallback would leave the counter unable to print at all.
      bonded = [classic('AA:11', 'XP-58')];
      sppConnectFails = true;
      vendorAppPresent = true;
      final svc = await service();
      expect(svc.target, PrinterTarget.vendorIntent);
      expect(svc.isApproximate, isTrue);
    });

    test('a dead printer with no vendor app leaves the POS disconnected, not stuck',
        () async {
      bonded = [classic('AA:11', 'XP-58')];
      sppConnectFails = true;
      final svc = await service();
      expect(svc.target, isNull);
      expect(svc.state.status, PrinterStatus.idle,
          reason: 'a failed probe at launch is not an error to alarm the shop with');
    });

    test('the Sunmi head wins over a bonded printer and is never persisted',
        () async {
      sunmiPresent = true;
      bonded = [classic('AA:11', 'XP-58')];
      final svc = await service();
      expect(svc.target, PrinterTarget.sunmiInner);
      expect(await svc.rememberedTarget(), isNull,
          reason: 'the inner head is redetected every launch; nothing to store');
    });

    test('the remembered printer is reconnected silently, even among several',
        () async {
      SharedPreferences.setMockInitialValues({
        'last_printer_target':
            const PrinterTarget(transport: PrinterTransport.spp, id: 'BB:22')
                .encode(),
      });
      bonded = [classic('AA:11', 'XP-58'), classic('BB:22', 'POS-9200')];
      final svc = await service();
      expect(svc.target?.id, 'BB:22');
      expect(svc.state.status, PrinterStatus.connected);
    });

    test('the vendor app alone is adopted but NOT remembered — it must lose to a '
        'real printer paired later', () async {
      vendorAppPresent = true;
      final svc = await service();
      expect(svc.target, PrinterTarget.vendorIntent);
      expect(await svc.rememberedTarget(), isNull);
    });
  });

  group('the Rovo VirtualBT black hole', () {
    test('is never auto-adopted, even though it claims to be a printer', () async {
      // Real device: class IMAGING, connect OK, write OK, NO PAPER. Adopting it
      // would confirm every sale as printed and hand the customer nothing.
      bonded = [
        {'address': '18:10:77:00:10:55', 'name': 'VirtualBT', 'isPrinterClass': true},
      ];
      final svc = await service();
      expect(svc.target, isNull);
      expect(svc.state.status, PrinterStatus.idle);
    });

    test('the built-in Centerm head is taken instead on that same terminal', () async {
      centermPresent = true;
      bonded = [
        {'address': '18:10:77:00:10:55', 'name': 'VirtualBT', 'isPrinterClass': true},
      ];
      final svc = await service();
      expect(svc.target, PrinterTarget.centermInner);
      expect(svc.isConnected, isTrue);
    });
  });
}
