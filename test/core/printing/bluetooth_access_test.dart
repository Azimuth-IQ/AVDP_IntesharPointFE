import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/core/printing/printer_target.dart';
import 'package:inteshar/core/printing/transports/spp_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B-150: on Android 12+ every bonded Bluetooth device — a paired printer, or a
/// head like the Topwise T6's — is invisible until the app holds "Nearby
/// devices" (BLUETOOTH_CONNECT), and nothing in the printer flow ever asked for
/// it. The owner's T6 lost its printer exactly that way: on, paired in Android,
/// never auto-connected, not listed by "Find my printer".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sunmiChannel = MethodChannel('inteshar/sunmi_printer');
  const rovoChannel = MethodChannel('inteshar/rovo_printer');
  const sppChannel = MethodChannel('inteshar/spp_printer');
  const usbChannel = MethodChannel('inteshar/usb_printer');
  const centermChannel = MethodChannel('inteshar/centerm_printer');
  const permissionChannel = MethodChannel('flutter.baseflow.com/permissions/methods');

  const tStatusDenied = 0;
  const tStatusGranted = 1;
  const tStatusPermanentlyDenied = 4;
  const tBluetoothConnect = 30; // Permission.bluetoothConnect.value

  /// The T6's head, as Android lists it once the app may look.
  const head = {'address': '00:11:22:33:44:55', 'name': 'InnerPrinter', 'isPrinterClass': false};

  late TestDefaultBinaryMessenger messenger;
  late int permission; // what Android currently answers for BLUETOOTH_CONNECT
  late int operatorAnswer; // what the operator taps on the system prompt
  late int prompts;
  late String radio;
  late bool sunmiPresent;
  late List<String> connects;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    permission = tStatusDenied;
    operatorAnswer = tStatusGranted;
    prompts = 0;
    radio = 'on';
    sunmiPresent = false;
    connects = [];

    messenger.setMockMethodCallHandler(sunmiChannel, (call) async =>
        call.method == 'isAvailable' ? sunmiPresent : null);
    messenger.setMockMethodCallHandler(centermChannel, (call) async =>
        call.method == 'isAvailable' ? false : null);
    messenger.setMockMethodCallHandler(rovoChannel, (call) async =>
        call.method == 'isAvailable' ? false : null);
    messenger.setMockMethodCallHandler(usbChannel, (call) async =>
        call.method == 'list' ? <Object?>[] : null);
    messenger.setMockMethodCallHandler(sppChannel, (call) async {
      final granted = permission == tStatusGranted;
      switch (call.method) {
        case 'adapterState':
          return radio;
        case 'isSupported':
          return radio == 'on' && granted;
        case 'bondedDevices':
          // Exactly what SppPrinterChannel.kt does: no grant, no list.
          return granted && radio == 'on' ? [head] : <Object?>[];
        case 'connect':
          connects.add((call.arguments as Map)['address'] as String);
          return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(permissionChannel, (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
          return permission;
        case 'requestPermissions':
          prompts++;
          permission = operatorAnswer;
          return {tBluetoothConnect: operatorAnswer};
      }
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    for (final c in [sunmiChannel, rovoChannel, sppChannel, usbChannel, centermChannel, permissionChannel]) {
      messenger.setMockMethodCallHandler(c, null);
    }
  });

  late ProviderContainer container;

  /// A POS start: the provider builds and auto-connect runs to completion.
  Future<PrinterService> posStart() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    final svc = container.read(printerServiceProvider.notifier);
    await svc.autoConnect();
    return svc;
  }

  test('the T6 case: a remembered head, the grant missing — one prompt at start, then it reconnects', () async {
    SharedPreferences.setMockInitialValues({
      'last_printer_target': const PrinterTarget(
        transport: PrinterTransport.spp,
        id: '00:11:22:33:44:55',
        name: 'InnerPrinter',
      ).encode(),
    });

    final svc = await posStart();

    expect(prompts, 1);
    expect(connects, contains('00:11:22:33:44:55'));
    expect(svc.isConnected, isTrue);
    expect(svc.target?.id, '00:11:22:33:44:55');
  });

  test('a fresh install finds the head as the single candidate once allowed', () async {
    final svc = await posStart();

    expect(prompts, 1);
    expect(svc.target?.label, 'InnerPrinter');
  });

  test('asked once per install: after a refusal, the next start does not ask again', () async {
    operatorAnswer = tStatusDenied;
    final first = await posStart();
    expect(prompts, 1);
    expect(first.target, isNull);

    final second = await posStart();
    expect(prompts, 1, reason: 'the start-up prompt is asked once, whatever the answer');
    expect(second.target, isNull);
  });

  test('never asks when a non-Bluetooth head will print (Sunmi)', () async {
    sunmiPresent = true;
    final svc = await posStart();

    expect(prompts, 0);
    expect(svc.target, PrinterTarget.sunmiInner);
  });

  test('never asks when the grant is already held, and connects as before', () async {
    permission = tStatusGranted;
    final svc = await posStart();

    expect(prompts, 0);
    expect(svc.target?.label, 'InnerPrinter');
  });

  test('the inventory says WHY the paired list is empty', () async {
    final svc = await posStart();
    // Granted by the start-up prompt above.
    expect((await svc.discover()).bluetooth, BluetoothAccess.ready);

    permission = tStatusDenied;
    expect((await svc.discover()).bluetooth, BluetoothAccess.askable);

    permission = tStatusPermanentlyDenied;
    expect((await svc.discover()).bluetooth, BluetoothAccess.blocked);

    permission = tStatusGranted;
    radio = 'off';
    expect((await svc.discover()).bluetooth, BluetoothAccess.off);

    radio = 'absent';
    expect((await svc.discover()).bluetooth, BluetoothAccess.none);
  });

  test('a lookup that fails reads as ready, never as a reason to prompt', () async {
    messenger.setMockMethodCallHandler(permissionChannel, null); // plugin missing
    final svc = await posStart();

    expect(prompts, 0);
    expect((await svc.discover()).bluetooth, BluetoothAccess.ready);
  });
}
