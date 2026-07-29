import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/core/printing/printer_target.dart';
import 'package:inteshar/core/printing/transports/network_printer.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// Printer setup.
///
/// CR-06: one section per **transport**, because they are genuinely different
/// things and merging them is how an operator ends up "connecting" to a headset.
/// Bonded Bluetooth **Classic** devices (what real ESC/POS printers use) are a
/// different list from BLE scan results — never the same rows.
class PrinterPickerPage extends ConsumerStatefulWidget {
  const PrinterPickerPage({super.key});

  @override
  ConsumerState<PrinterPickerPage> createState() => _PrinterPickerPageState();
}

class _PrinterPickerPageState extends ConsumerState<PrinterPickerPage> {
  PrinterInventory _inv = const PrinterInventory();
  List<ScanResult> _scanResults = [];
  bool _scanning = false;
  bool _loading = true;

  /// Target id currently connecting — drives the per-row spinner.
  String? _busyId;

  late PrinterService _service;

  final _macController = TextEditingController();
  final _macFormKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(
    text: '${NetworkPrinter.defaultPort}',
  );

  @override
  void initState() {
    super.initState();
    _service = ref.read(printerServiceProvider.notifier);
    _refresh();
  }

  @override
  void dispose() {
    _service.stopScan();
    _macController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final inv = await _service.discover();
    final lastMac = await _service.lastPrinterId;
    if (!mounted) return;
    setState(() {
      _inv = inv;
      _loading = false;
      if (lastMac != null && _macController.text.isEmpty) {
        _macController.text = lastMac;
      }
      final remembered = inv.remembered;
      if (remembered != null &&
          remembered.transport == PrinterTransport.tcp &&
          _hostController.text.isEmpty) {
        _hostController.text = remembered.host;
        _portController.text = '${remembered.port}';
      }
    });
  }

  /// A BLE scan is opt-in: thermal printers are almost never BLE, the scan
  /// takes eight seconds, and running the radio while opening a Classic socket
  /// is a good way to make the socket fail.
  void _startScan() {
    setState(() {
      _scanning = true;
      _scanResults = [];
    });
    _service.scan().listen(
      (results) {
        if (mounted) setState(() => _scanResults = results);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _use(PrinterTarget target) async {
    _service.stopScan();
    setState(() {
      _scanning = false;
      _busyId = target.id;
    });
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await _service.use(target);
      messenger.showSnackBar(
        SnackBar(content: Text(l.printerPickerConnectedTo(target.label))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.printerPickerConnectionFailed(e.toString())),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// A typed address is far more likely to be a Classic printer than a BLE one —
  /// that is what is printed on the label of an X-Printer or a counter unit — so
  /// try SPP first and only then GATT.
  Future<void> _connectByAddress() async {
    if (!_macFormKey.currentState!.validate()) return;
    final mac = _macController.text.trim().toUpperCase();
    _service.stopScan();
    setState(() {
      _scanning = false;
      _busyId = mac;
    });
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      try {
        await _service.use(
          PrinterTarget(transport: PrinterTransport.spp, id: mac, name: mac),
        );
      } catch (_) {
        await _service.use(
          PrinterTarget(transport: PrinterTransport.ble, id: mac, name: mac),
        );
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l.printerPickerConnectedManual)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.printerPickerConnectionFailed(e.toString())),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _connectNetwork() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;
    final port =
        int.tryParse(_portController.text.trim()) ?? NetworkPrinter.defaultPort;
    await _use(PrinterTarget.tcpAt(host, port));
  }

  Future<void> _testPrint() async {
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.send(await buildTestPrintJob());
      messenger.showSnackBar(
        SnackBar(content: Text(l.printerPickerTestPrintSent)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.printerPickerPrintError(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final printerState = ref.watch(printerServiceProvider);
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
        actions: [
          IconButton(
            tooltip: l.printerPickerRescan,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const SizedBox(height: 12),
          if (printerState.status == PrinterStatus.needsChoice)
            _noticeCard(
              cs,
              icon: Icons.help_outline,
              tint: IntesharColors.warn,
              text: l.printerPickerChooseOne,
            ),
          if (isConnected) ...[
            _connectedCard(l, cs, printerState),
            const SizedBox(height: 22),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          // 1 — built-in heads. No pairing, no address, and on a Sunmi this is
          // the only path confirmed on real hardware.
          if (_inv.sunmiAvailable || _inv.intentAvailable) ...[
            SectionLabel(l.printerPickerBuiltIn),
            if (_inv.sunmiAvailable)
              _row(
                cs,
                icon: Icons.print_outlined,
                accent: IntesharColors.sage,
                title: PrinterTarget.sunmiInner.label,
                subtitle: l.printerPickerBuiltInHint,
                target: PrinterTarget.sunmiInner,
              ),
            if (_inv.intentAvailable)
              _row(
                cs,
                icon: Icons.warning_amber_rounded,
                accent: IntesharColors.warn,
                title: PrinterTarget.vendorIntent.label,
                subtitle: l.printerPickerApproximate,
                target: PrinterTarget.vendorIntent,
              ),
            const SizedBox(height: 18),
          ],

          // 2 — Bluetooth CLASSIC. What real ESC/POS printers speak.
          SectionLabel(l.printerPickerBluetoothClassic),
          Text(
            l.printerPickerBluetoothClassicHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_inv.bondedClassic.isEmpty && !_loading)
            _emptyLine(context, l.printerPickerNoPaired)
          else
            ..._inv.bondedClassic.map((d) {
              final likely = PrinterInventory.isLikelyPrinter(d);
              return _row(
                cs,
                icon: likely ? Icons.print_outlined : Icons.bluetooth,
                accent: likely ? IntesharColors.sage : cs.onSurfaceVariant,
                title: d.toTarget().label,
                subtitle: d.address,
                target: d.toTarget(),
              );
            }),
          const SizedBox(height: 18),

          // 3 — USB (OTG).
          if (_inv.usbDevices.isNotEmpty) ...[
            SectionLabel(l.printerPickerUsb),
            ..._inv.usbDevices.map(
              (d) => _row(
                cs,
                icon: Icons.usb,
                accent: d.isPrinterClass
                    ? IntesharColors.sage
                    : cs.onSurfaceVariant,
                title: d.toTarget().label,
                subtitle: d.hasPermission
                    ? d.id
                    : l.printerPickerUsbNeedsPermission,
                target: d.toTarget(),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // 4 — Network. Nothing is discovered here on purpose: scanning a shop's
          // LAN for open port 9100 could as easily find the neighbour's printer.
          SectionLabel(l.printerPickerNetwork),
          Text(
            l.printerPickerNetworkHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _hostController,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '192.168.1.50',
                    labelText: l.printerPickerHost,
                  ),
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _portController,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                  decoration: InputDecoration(labelText: l.printerPickerPort),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              BrandCTAButton(
                label: l.printerPickerConnect,
                loading:
                    _busyId ==
                    '${_hostController.text.trim()}:${_portController.text.trim()}',
                onPressed: _busyId != null ? null : _connectNetwork,
                expand: false,
                height: 46,
                fontSize: 13,
              ),
            ],
          ),
          const SizedBox(height: 22),

          // 5 — manual address (Classic first, then LE).
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
                      _busyId != null &&
                      _busyId == _macController.text.trim().toUpperCase(),
                  onPressed: _busyId != null ? null : _connectByAddress,
                  expand: false,
                  height: 46,
                  fontSize: 13,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 6 — Bluetooth LE, last and opt-in: few thermal printers use it.
          SectionLabel(
            l.printerPickerBluetoothLe,
            trailing: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.search, size: 14),
                    label: Text(l.printerPickerScan),
                  ),
          ),
          Text(
            l.printerPickerBluetoothLeHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_scanResults.isEmpty && !_scanning)
            _emptyLine(context, l.printerPickerNoDevices),
          ..._scanResults.map((r) {
            final name = PrinterService.displayName(
              r.device,
              adv: r.advertisementData,
            );
            return _row(
              cs,
              icon: Icons.bluetooth,
              accent: cs.onSurfaceVariant,
              title: name,
              subtitle: r.device.remoteId.str,
              target: PrinterTarget(
                transport: PrinterTransport.ble,
                id: r.device.remoteId.str,
                name: name,
              ),
            );
          }),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pieces

  Widget _connectedCard(
    AppLocalizations l,
    ColorScheme cs,
    PrinterState printerState,
  ) {
    final approximate = printerState.isApproximate;
    final tint = approximate ? IntesharColors.warn : IntesharColors.sage;
    return InkCard(
      ruleColor: tint,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(IntesharRadii.xs),
                ),
                child: Icon(Icons.print, color: tint, size: 18),
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
                      style: IntesharType.overline(color: tint),
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
          // The one honest thing to say about the intent path: we hand the
          // content to another app and it decides how the paper looks.
          if (approximate) ...[
            const SizedBox(height: 10),
            Text(
              l.printerPickerApproximate,
              style: IntesharType.sans(12, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _noticeCard(
    ColorScheme cs, {
    required IconData icon,
    required Color tint,
    required String text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: IntesharType.sans(
                12.5,
                color: cs.onSurface,
                w: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyLine(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall,
      textAlign: TextAlign.center,
    ),
  );

  Widget _row(
    ColorScheme cs, {
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required PrinterTarget target,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: InkCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: _busyId == null ? () => _use(target) : null,
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: IntesharType.sans(
                    13.5,
                    color: cs.onSurface,
                    w: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_busyId == target.id)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
        ],
      ),
    ),
  );
}
