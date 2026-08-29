import 'package:flutter/material.dart';
import 'package:inteshar/core/printing/auto_connect.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/centerm_printer.dart';
import 'package:inteshar/core/printing/rovo_printer.dart';
import 'package:inteshar/core/printing/sunmi_printer.dart';
import 'package:inteshar/core/printing/transports/spp_printer.dart';
import 'package:inteshar/core/printing/transports/usb_printer.dart';

/// Login-free printer probe — `flutter run -t lib/main_printer_probe.dart`.
///
/// Follows the project's preview-harness convention: boot straight into the one
/// thing under test, with no backend and no session. Every transport is exercised
/// by hand and every error is printed ON THE DEVICE, because the interesting
/// failures here (a socket that opens but prints nothing) are invisible in logs.
void main() => runApp(const _ProbeApp());

class _ProbeApp extends StatelessWidget {
  const _ProbeApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Printer probe',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: const _ProbePage(),
  );
}

class _ProbePage extends StatefulWidget {
  const _ProbePage();
  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  final _log = <String>[];
  List<SppDevice> _bonded = const [];
  List<UsbPrinterDevice> _usb = const [];
  bool _sunmi = false;
  bool _centerm = false;
  bool _intent = false;
  bool _sppSupported = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _say(String s) {
    // ignore: avoid_print
    print('[PROBE] $s');
    if (mounted) setState(() => _log.insert(0, s));
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      _sunmi = await SunmiPrinter.isAvailable();
      _centerm = await CentermPrinter.isAvailable();
      _intent = await RovoPrinter.isAvailable();
      _sppSupported = await SppPrinter.isSupported();
      _bonded = await SppPrinter.bondedDevices();
      _usb = await UsbPrinter.list();
      _say('--- scan ---');
      _say('sunmi=$_sunmi  centerm=$_centerm  vendorIntent=$_intent  sppSupported=$_sppSupported');
      for (final d in _bonded) {
        _say(
          'BONDED "${d.name}" ${d.address} printerClass=${d.isPrinterClass} '
          'nameHeuristic=${looksLikePrinterName(d.name)}',
        );
      }
      if (_bonded.isEmpty) _say('BONDED: none');
      for (final d in _usb) {
        _say('USB "${d.name}" ${d.id} printerClass=${d.isPrinterClass} perm=${d.hasPermission}');
      }
      if (_usb.isEmpty) _say('USB: none');

      // What auto-connect WOULD do with exactly this hardware.
      final candidates = [
        ..._bonded.where((d) => d.isPrinterClass || looksLikePrinterName(d.name)).map((d) => d.toTarget()),
        ..._usb.where((d) => d.isPrinterClass && d.hasPermission).map((d) => d.toTarget()),
      ];
      final decision = decideAutoConnect(
        sunmiAvailable: _sunmi,
        centermAvailable: _centerm,
        intentAvailable: _intent,
        remembered: null,
        available: [..._bonded.map((d) => d.toTarget()), ..._usb.map((d) => d.toTarget())],
        candidates: candidates,
      );
      _say('AUTO-CONNECT would: ${decision.action.name} (${decision.reason.name}) → ${decision.target}');
    } catch (e) {
      _say('SCAN FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PrintJob> _job() async => buildTestPrintJob();

  Future<void> _sppTest(String address, String label) async {
    setState(() => _busy = true);
    try {
      _say('SPP connect → $label ($address) …');
      await SppPrinter.connect(address);
      _say('SPP connect OK');
      final job = await _job();
      _say('SPP write ${job.bytes.length} bytes …');
      await SppPrinter.write(address, job.bytes);
      _say('SPP write RETURNED OK — did paper come out?');
    } catch (e) {
      _say('SPP FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Raw text down the same socket. If ESC/POS produces nothing but this does,
  /// the channel is fine and the printer is rejecting our command stream.
  Future<void> _sppPlainText(String address) async {
    setState(() => _busy = true);
    try {
      await SppPrinter.connect(address);
      final bytes = <int>[
        0x1B, 0x40, // ESC @  (init)
        ...'PLAIN TEXT PROBE\n\n\n'.codeUnits,
      ];
      await SppPrinter.write(address, bytes);
      _say('SPP plain-text probe sent (${bytes.length} bytes)');
    } catch (e) {
      _say('SPP plain-text FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _centermTest() async {
    setState(() => _busy = true);
    try {
      final job = await _job();
      _say('CENTERM sendEscPrintCommand ${job.bytes.length} bytes …');
      await CentermPrinter.printRaw(job.bytes);
      _say('CENTERM returned OK — paper?');
    } catch (e) {
      _say('CENTERM FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _intentTest() async {
    setState(() => _busy = true);
    try {
      await RovoPrinter.printText('INTENT PROBE\nInteshar Point\n');
      _say('intent printText returned OK');
    } catch (e) {
      _say('intent FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sunmiTest() async {
    setState(() => _busy = true);
    try {
      final job = await _job();
      await SunmiPrinter.printRaw(job.bytes);
      _say('sunmi printRaw returned OK');
    } catch (e) {
      _say('sunmi FAILED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Printer probe'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _scan,
          tooltip: 'Rescan',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_busy) const LinearProgressIndicator(),
        Text('sunmi=$_sunmi  centerm=$_centerm  intent=$_intent  spp=$_sppSupported',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const Divider(),
        const Text('Bonded Bluetooth Classic', style: TextStyle(fontWeight: FontWeight.bold)),
        ..._bonded.map(
          (d) => Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${d.name.isEmpty ? "(no name)" : d.name}  —  ${d.address}'),
                  Text('printerClass=${d.isPrinterClass}  heuristic=${looksLikePrinterName(d.name)}',
                      style: const TextStyle(fontSize: 11)),
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _busy ? null : () => _sppTest(d.address, d.name),
                        child: const Text('ESC/POS test'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : () => _sppPlainText(d.address),
                        child: const Text('plain text'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(),
        Wrap(
          spacing: 8,
          children: [
            if (_centerm)
              ElevatedButton(onPressed: _busy ? null : _centermTest, child: const Text('CENTERM print')),
            if (_intent)
              ElevatedButton(onPressed: _busy ? null : _intentTest, child: const Text('intent print')),
            if (_sunmi)
              ElevatedButton(onPressed: _busy ? null : _sunmiTest, child: const Text('sunmi print')),
          ],
        ),
        const Divider(),
        const Text('Log (newest first)', style: TextStyle(fontWeight: FontWeight.bold)),
        ..._log.map(
          (l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(l, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ),
      ],
    ),
  );
}
