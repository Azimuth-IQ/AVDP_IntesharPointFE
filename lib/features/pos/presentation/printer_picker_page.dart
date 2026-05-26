import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/printer_registry.dart';

class PrinterPickerPage extends ConsumerStatefulWidget {
  const PrinterPickerPage({super.key});

  @override
  ConsumerState<PrinterPickerPage> createState() => _PrinterPickerPageState();
}

class _PrinterPickerPageState extends ConsumerState<PrinterPickerPage> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  late BluetoothPrinterService _service;

  final _macController = TextEditingController();
  final _macFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _service = ref.read(bluetoothServiceProvider.notifier);
    _startScan();
    _loadLastPrinterId();
  }

  Future<void> _loadLastPrinterId() async {
    final id = await _service.lastPrinterId;
    if (id != null && mounted) {
      setState(() => _macController.text = id);
    }
  }

  @override
  void dispose() {
    _service.stopScan();
    _macController.dispose();
    super.dispose();
  }

  String? _validateMac(String? v) {
    if (v == null || v.isEmpty) return 'Enter a MAC address';
    final macRegex = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    if (!macRegex.hasMatch(v)) return 'Format: XX:XX:XX:XX:XX:XX';
    return null;
  }

  Future<void> _connectByAddress() async {
    if (!_macFormKey.currentState!.validate()) return;
    _service.stopScan();
    if (mounted) setState(() => _scanning = false);
    try {
      await _service.connectByAddress(_macController.text.trim().toUpperCase());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connected via manual address')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }
  }

  void _startScan() {
    setState(() {
      _scanning = true;
      _results = [];
    });
    final stream = _service.scan();
    stream.listen(
      (results) {
        if (mounted) setState(() => _results = results);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _connect(BluetoothDevice device) async {
    // Stop the scan immediately so the Android BLE adapter fully releases
    // scanner resources before we attempt a GATT connection (prevents GATT 133).
    _service.stopScan();
    if (mounted) setState(() => _scanning = false);
    try {
      await _service.connect(device);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connected to ${device.platformName}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    }
  }

  Future<void> _testPrint() async {
    try {
      final bytes = await buildTestReceipt();
      await _service.send(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test print sent!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final printerState = ref.watch(bluetoothServiceProvider);
    final isConnected = printerState.status == PrinterStatus.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Printer Setup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Supported models
          Text('Supported Printer Models', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: supportedPrinterModels.map((m) => Chip(label: Text(m.name))).toList()),
          const Divider(height: 32),

          // Connected status
          if (isConnected) ...[
            ListTile(
              leading: const Icon(Icons.print, color: Colors.green),
              title: Text(printerState.deviceName ?? 'Printer'),
              subtitle: const Text('Connected'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: _testPrint, child: const Text('Test Print')),
                  TextButton(onPressed: () => _service.disconnect(), child: const Text('Disconnect')),
                ],
              ),
            ),
            const Divider(height: 32),
          ],

          // Manual address entry
          Text('Manual Address', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Use this when the device is not visible in the scan list.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Form(
            key: _macFormKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _macController,
                    validator: _validateMac,
                    decoration: const InputDecoration(hintText: 'XX:XX:XX:XX:XX:XX', labelText: 'Bluetooth MAC address', border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 8),
                printerState.status == PrinterStatus.connecting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : FilledButton(onPressed: _connectByAddress, child: const Text('Connect')),
              ],
            ),
          ),
          const Divider(height: 32),

          // Scan section
          Row(
            children: [
              Text('Nearby Devices', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (_scanning)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton.icon(onPressed: _startScan, icon: const Icon(Icons.refresh, size: 18), label: const Text('Scan')),
            ],
          ),
          const SizedBox(height: 8),
          if (_results.isEmpty && !_scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No devices found. Make sure Bluetooth is on and the printer is powered.', textAlign: TextAlign.center),
            ),
          ..._results.map(
            (r) => ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : 'Unknown'),
              subtitle: Text(r.device.remoteId.str),
              trailing: printerState.status == PrinterStatus.connecting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton(onPressed: () => _connect(r.device), child: const Text('Connect')),
            ),
          ),
        ],
      ),
    );
  }
}
