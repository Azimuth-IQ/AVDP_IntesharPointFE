import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/printer_registry.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

class PrinterPickerPage extends ConsumerStatefulWidget {
  const PrinterPickerPage({super.key});

  @override
  ConsumerState<PrinterPickerPage> createState() => _PrinterPickerPageState();
}

class _PrinterPickerPageState extends ConsumerState<PrinterPickerPage> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  String?
  _connectingId; // the device id currently being connected (per-row spinner)
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

  Future<void> _connectByAddress() async {
    if (!_macFormKey.currentState!.validate()) return;
    final mac = _macController.text.trim().toUpperCase();
    _service.stopScan();
    if (mounted) {
      setState(() {
        _scanning = false;
        _connectingId = mac;
      });
    }
    try {
      await _service.connectByAddress(mac);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.printerPickerConnectedManual)));
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.printerPickerConnectionFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingId = null);
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
    _service.stopScan();
    if (mounted) {
      setState(() {
        _scanning = false;
        _connectingId = device.remoteId.str;
      });
    }
    try {
      await _service.connect(device);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.printerPickerConnectedTo(device.platformName)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.printerPickerConnectionFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingId = null);
    }
  }

  Future<void> _testPrint() async {
    try {
      final bytes = await buildTestReceipt();
      await _service.send(bytes);
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.printerPickerTestPrintSent)));
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.printerPickerPrintError(e.toString()))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final printerState = ref.watch(bluetoothServiceProvider);
    final isConnected = printerState.status == PrinterStatus.connected;
    final cs = Theme.of(context).colorScheme;

    String? validateMac(String? v) {
      if (v == null || v.isEmpty) return l.printerPickerEnterMac;
      final macRegex = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
      if (!macRegex.hasMatch(v)) return l.printerPickerMacFormat;
      return null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.printerPickerTitle,
          style: Theme.of(context).appBarTheme.titleTextStyle,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          SectionLabel(l.aboutSupportedPrinters),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: supportedPrinterModels
                .map(
                  (m) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.name,
                          style: TextStyle(
                            fontFamily: 'CodecPro',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${m.paperMm}mm',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          // Connected status
          if (isConnected) ...[
            InkCard(
              ruleColor: IntesharColors.sage,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: IntesharColors.sage.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(IntesharRadii.xs),
                    ),
                    child: const Icon(
                      Icons.bluetooth_connected,
                      color: IntesharColors.sage,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          printerState.deviceName ?? l.printerPickerUnknown,
                          style: IntesharType.serif(
                            18,
                            color: cs.onSurface,
                            w: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l.printerPickerConnected,
                          style: IntesharType.overline(
                            color: IntesharColors.sage,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _testPrint,
                    child: Text(l.printerPickerTestPrint),
                  ),
                  TextButton(
                    onPressed: _service.disconnect,
                    child: Text(l.printerPickerDisconnect),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          SectionLabel(l.printerPickerManualAddress),
          Text(
            l.printerPickerManualHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Form(
            key: _macFormKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _macController,
                    validator: validateMac,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      color: cs.onSurface,
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: 'XX:XX:XX:XX:XX:XX',
                      labelText: l.printerPickerMacLabel,
                    ),
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 10),
                BrandCTAButton(
                  label: l.printerPickerPair,
                  loading:
                      _connectingId != null &&
                      _connectingId == _macController.text.trim().toUpperCase(),
                  onPressed: _connectingId != null ? null : _connectByAddress,
                  expand: false,
                  height: 46,
                  fontSize: 13,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SectionLabel(
            l.printerPickerNearbyDevices,
            trailing: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: Text(l.printerPickerRescan),
                  ),
          ),
          if (_results.isEmpty && !_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                l.printerPickerNoDevices,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ..._results.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.device.platformName.isNotEmpty
                                ? r.device.platformName
                                : l.printerPickerUnknown,
                            style: IntesharType.serif(
                              16,
                              color: cs.onSurface,
                              w: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.device.remoteId.str,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    BrandCTAButton(
                      label: l.printerPickerPair,
                      loading: _connectingId == r.device.remoteId.str,
                      onPressed: _connectingId != null
                          ? null
                          : () => _connect(r.device),
                      expand: false,
                      height: 40,
                      fontSize: 12.5,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
