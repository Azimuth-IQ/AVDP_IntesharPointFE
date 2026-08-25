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
/// UX-63: this page is reached at the worst possible moment — mid-shift, by a
/// cashier whose printer just died, with a customer waiting. It used to open on
/// transport taxonomy ("Bluetooth Classic" vs "Bluetooth LE"), a MAC-address
/// field with a hex validator and a host/port pair defaulting to 9100: an
/// engineer's page, shown to someone who wants one thing to work again.
///
/// So it now leads with **one action — "find my printer" — and the printers this
/// terminal can actually reach**. Addresses, ports and USB permissions still
/// exist, unchanged, behind an "advanced" disclosure for the one shop in a
/// hundred that needs them.
///
/// CR-06 still holds underneath: bonded Bluetooth **Classic** devices (what real
/// ESC/POS printers use) are a different list from BLE scan results and are never
/// merged into the same rows — that is how an operator ends up "connecting" to a
/// headset.
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

  /// The one button a cashier should ever need.
  ///
  /// UX-63: re-discovers what is attached, lets auto-connect adopt it when the
  /// answer is unambiguous, and only falls back to a BLE scan when nothing else
  /// turned up. Nothing here writes bytes to a print head.
  Future<void> _findMyPrinter() async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final messenger = ScaffoldMessenger.of(context);
    await _refresh();
    if (!mounted) return;

    // Already holding a printer: re-check it rather than hunting for another.
    if (_service.target != null) {
      final ok = await _service.verifyConnection();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? (ar ? 'الطابعة متصلة وتستجيب.' : 'The printer is connected and responding.')
            : (ar
                ? 'الطابعة لا تستجيب — تأكد أنها مشغّلة وقريبة، أو اختر طابعة أخرى.'
                : 'The printer is not responding — check it is on and nearby, or pick another.')),
      ));
      return;
    }

    // Let the ordinary start-up policy do the choosing (built-in head →
    // remembered → the single obvious candidate → ask).
    await _service.autoConnect();
    if (!mounted) return;
    if (_service.target != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(ar
            ? 'تم الاتصال بـ ${_service.target!.label}'
            : 'Connected to ${_service.target!.label}'),
      ));
      return;
    }
    if (ref.read(printerServiceProvider).needsChoice) {
      messenger.showSnackBar(SnackBar(
        content: Text(ar
            ? 'وُجدت أكثر من طابعة — اختر طابعة هذا الكاونتر من القائمة.'
            : 'Several printers were found — pick this counter\'s one from the list.'),
      ));
      return;
    }
    // Nothing paired, nothing built in: the LE scan is the last thing worth
    // trying, and now it is the app asking for it rather than the operator
    // having to know that "LE" is a thing.
    _startScan();
    messenger.showSnackBar(SnackBar(
      content: Text(ar
          ? 'لم يتم العثور على طابعة مقترنة — جارٍ البحث عن أجهزة قريبة.'
          : 'No paired printer found — searching for nearby devices.'),
    ));
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
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final printerState = ref.watch(printerServiceProvider);
    final hasPrinter = printerState.hasPrinter;
    final cs = Theme.of(context).colorScheme;

    String? validateMac(String? v) {
      if (v == null || v.isEmpty) return l.printerPickerEnterMac;
      final macRegex = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
      if (!macRegex.hasMatch(v)) return l.printerPickerMacFormat;
      return null;
    }

    // Everything a cashier could plausibly want to tap, in one list: the built-in
    // head first (no pairing, no address, and on a Sunmi the only path confirmed
    // on hardware), then paired devices that look like printers, then attached
    // USB printers, then anything a scan turned up. Paired NON-printers (a
    // headset, a phone) are not offered here — they are in "advanced", because
    // offering them is how a voucher gets "printed" to a car kit.
    final builtIn = <Widget>[
      if (_inv.sunmiAvailable)
        _row(
          cs,
          icon: Icons.print_outlined,
          accent: context.status.success,
          title: PrinterTarget.sunmiInner.label,
          subtitle: l.printerPickerBuiltInHint,
          target: PrinterTarget.sunmiInner,
        ),
      // The Centerm/Rovo inner head takes our raw bytes exactly like Sunmi's, and
      // it was missing from this page entirely: auto-connect could adopt it but an
      // operator could never pick it back after switching away.
      if (_inv.centermAvailable)
        _row(
          cs,
          icon: Icons.print_outlined,
          accent: context.status.success,
          title: PrinterTarget.centermInner.label,
          subtitle: l.printerPickerBuiltInHint,
          target: PrinterTarget.centermInner,
        ),
      if (_inv.intentAvailable)
        _row(
          cs,
          icon: Icons.warning_amber_rounded,
          accent: context.status.warn,
          title: PrinterTarget.vendorIntent.label,
          subtitle: l.printerPickerApproximate,
          target: PrinterTarget.vendorIntent,
        ),
    ];

    final likelyPaired = _inv.bondedClassic.where(PrinterInventory.isLikelyPrinter).toList();
    final otherPaired =
        _inv.bondedClassic.where((d) => !PrinterInventory.isLikelyPrinter(d)).toList();

    final found = <Widget>[
      ...builtIn,
      ...likelyPaired.map((d) => _row(
            cs,
            icon: Icons.print_outlined,
            accent: context.status.success,
            title: d.toTarget().label,
            subtitle: d.address,
            target: d.toTarget(),
          )),
      ..._inv.usbDevices.where((d) => d.isPrinterClass).map((d) => _row(
            cs,
            icon: Icons.usb,
            accent: context.status.success,
            title: d.toTarget().label,
            subtitle: d.hasPermission ? d.id : l.printerPickerUsbNeedsPermission,
            target: d.toTarget(),
          )),
      ..._scanResults.map((r) {
        final name = PrinterService.displayName(r.device, adv: r.advertisementData);
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
    ];

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
          if (printerState.needsChoice)
            _noticeCard(
              cs,
              icon: Icons.help_outline,
              tint: context.status.warn,
              text: l.printerPickerChooseOne,
            ),
          if (hasPrinter) ...[
            _connectedCard(l, cs, printerState, ar),
            const SizedBox(height: 18),
          ],

          // THE action. Everything below it is for when this did not do the job.
          BrandCTAButton(
            label: ar ? 'ابحث عن طابعتي' : 'Find my printer',
            leading: Icons.search,
            loading: _loading || _scanning,
            onPressed: (_loading || _scanning || _busyId != null)
                ? null
                : _findMyPrinter,
          ),
          const SizedBox(height: 6),
          Text(
            ar
                ? 'يبحث عن الطابعة المدمجة والطابعات المقترنة والموصولة بهذا الجهاز.'
                : 'Looks for the built-in head and any printer paired or plugged into this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),

          SectionLabel(ar ? 'الطابعات المتاحة' : 'Available printers'),
          const SizedBox(height: 4),
          if (found.isEmpty && !_loading)
            _emptyLine(
              context,
              ar
                  ? 'لم يتم العثور على طابعة. شغّل الطابعة واقترن بها من إعدادات أندرويد، ثم اضغط "ابحث عن طابعتي".'
                  : 'No printer found. Switch the printer on and pair it in Android settings, then tap "Find my printer".',
            )
          else
            ...found,

          const SizedBox(height: 18),

          // Everything that follows is an engineer's tool: a MAC address, an IP
          // and a port, a USB device that is not a printer, a radio almost no
          // thermal printer speaks. It stays — some shops genuinely need it — but
          // it is no longer the first thing a cashier meets.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                ar ? 'إعدادات متقدمة' : 'Advanced',
                style: IntesharType.sans(13.5, color: cs.onSurface, w: FontWeight.w700),
              ),
              subtitle: Text(
                ar
                    ? 'عنوان يدوي، طابعة شبكة، بلوتوث LE'
                    : 'Manual address, network printer, Bluetooth LE',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                const SizedBox(height: 8),

                // Paired devices that do NOT look like printers. Deliberately
                // down here: connecting a voucher to a car kit is a real way to
                // lose a sale.
                if (otherPaired.isNotEmpty) ...[
                  SectionLabel(ar ? 'أجهزة مقترنة أخرى' : 'Other paired devices'),
                  Text(
                    l.printerPickerBluetoothClassicHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ...otherPaired.map((d) => _row(
                        cs,
                        icon: Icons.bluetooth,
                        accent: cs.onSurfaceVariant,
                        title: d.toTarget().label,
                        subtitle: d.address,
                        target: d.toTarget(),
                      )),
                  const SizedBox(height: 18),
                ],

                // USB devices that do not declare a printer interface.
                if (_inv.usbDevices.any((d) => !d.isPrinterClass)) ...[
                  SectionLabel(l.printerPickerUsb),
                  ..._inv.usbDevices.where((d) => !d.isPrinterClass).map(
                        (d) => _row(
                          cs,
                          icon: Icons.usb,
                          accent: cs.onSurfaceVariant,
                          title: d.toTarget().label,
                          subtitle: d.hasPermission
                              ? d.id
                              : l.printerPickerUsbNeedsPermission,
                          target: d.toTarget(),
                        ),
                      ),
                  const SizedBox(height: 18),
                ],

                // Network. Nothing is discovered here on purpose: scanning a
                // shop's LAN for open port 9100 could as easily find the
                // neighbour's printer.
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
                      loading: _busyId ==
                          '${_hostController.text.trim()}:${_portController.text.trim()}',
                      onPressed: _busyId != null ? null : _connectNetwork,
                      expand: false,
                      height: 46,
                      fontSize: 13,
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Manual address (Classic first, then LE).
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
                        loading: _busyId != null &&
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

                // Bluetooth LE, last and opt-in: few thermal printers use it.
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
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pieces

  Widget _connectedCard(
    AppLocalizations l,
    ColorScheme cs,
    PrinterState printerState,
    bool ar,
  ) {
    final approximate = printerState.isApproximate;
    // UX-55: "connected" is a probed fact now, and a printer that did not answer
    // says so here instead of showing the same green as a working one.
    final unreachable = printerState.isUnreachable;
    final tint = (approximate || unreachable)
        ? context.status.warn
        : context.status.success;
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
                child: Icon(
                  unreachable ? Icons.print_disabled_outlined : Icons.print,
                  color: tint,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.serif(
                        18,
                        color: cs.onSurface,
                        w: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unreachable
                          ? (ar ? 'لا تستجيب' : 'Not responding')
                          : l.printerPickerConnected,
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
          if (unreachable) ...[
            const SizedBox(height: 10),
            Text(
              ar
                  ? 'لم تجب الطابعة على آخر فحص — تأكد أنها مشغّلة وقريبة. ما زال بإمكانك تجربة الطباعة.'
                  : "The printer did not answer the last check — make sure it is switched on and nearby. You can still try printing.",
              style: IntesharType.sans(12, color: cs.onSurfaceVariant),
            ),
          ],
          // UX-61: the test slip goes through the SAME raster pipeline as a real
          // voucher (Arabic + a QR), so passing it means the receipts will print.
          const SizedBox(height: 8),
          Text(
            ar
                ? 'الطباعة التجريبية تطبع نموذجاً عربياً مع رمز QR — نفس طريقة طباعة الإيصال الحقيقي.'
                : 'The test print puts an Arabic sample and a QR on paper — exactly how a real receipt is printed.',
            style: IntesharType.sans(12, color: cs.onSurfaceVariant),
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
                // UX-147: this line carries the MAC / host:port — the string an
                // operator compares against a label on the back of a printer.
                // 11px was below the app's floor for exactly that kind of text.
                Text(
                  subtitle,
                  style: IntesharType.mono(12, color: cs.onSurfaceVariant, letterSpacing: 0.3),
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
