import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A "get the app" page: shows a scannable QR that points at the public
/// `GET /api/app/download` endpoint (302 → the latest signed APK). A POS operator
/// scans it with their phone camera to install the newest build — no app-store,
/// no manual URL typing. Reached from the dashboard nav.
class AppDownloadPage extends StatefulWidget {
  const AppDownloadPage({super.key});

  @override
  State<AppDownloadPage> createState() => _AppDownloadPageState();
}

class _AppDownloadPageState extends State<AppDownloadPage> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  /// Absolute, scannable URL. On web that's the current page origin (what testers
  /// see in the address bar); on mobile it's the configured API base.
  Future<void> _resolveUrl() async {
    String origin;
    if (kIsWeb) {
      origin = Uri.base.origin;
    } else {
      final base = await sessionStorage.getBaseUrl();
      origin = base.isNotEmpty ? base : Uri.base.origin;
    }
    origin = origin.replaceAll(RegExp(r'/+$'), '');
    if (mounted) setState(() => _url = '$origin${Endpoints.appDownload}');
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return MaxWidthBox(
      maxWidth: 560,
      child: Column(
        children: [
          PageHeader(
            eyebrow: ar ? 'الإدارة' : 'ADMINISTRATION',
            title: ar ? 'تحميل التطبيق' : 'Get the app',
            subtitle: ar ? 'شارك رمز QR مع نقاط البيع لتثبيت أحدث إصدار' : 'Share this QR with your POS points to install the latest build',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              child: Center(
                child: InkCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_2, size: 28, color: context.tones.brandInk),
                      const SizedBox(height: 10),
                      Text(
                        ar ? 'امسح بكاميرا الهاتف للتثبيت' : 'Scan with your phone camera to install',
                        textAlign: TextAlign.center,
                        style: IntesharType.sans(14.5, color: cs.onSurface, w: FontWeight.w700),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(IntesharRadii.lg),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                        ),
                        child: _url == null
                            ? const SizedBox(width: 240, height: 240, child: Center(child: CircularProgressIndicator()))
                            : QrImageView(
                                data: _url!,
                                version: QrVersions.auto,
                                size: 240,
                                backgroundColor: Colors.white,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                              ),
                      ),
                      const SizedBox(height: 16),
                      if (_url != null)
                        SelectableText(
                          _url!,
                          textAlign: TextAlign.center,
                          style: IntesharType.mono(12.5, color: cs.onSurfaceVariant),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _url == null ? null : () => _copy(ar),
                            icon: const Icon(Icons.copy, size: 16),
                            label: Text(ar ? 'نسخ الرابط' : 'Copy link'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        ar ? 'أندرويد فقط · يتم دائماً تنزيل أحدث إصدار' : 'Android only · always downloads the newest version',
                        textAlign: TextAlign.center,
                        style: IntesharType.sans(11.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(bool ar) async {
    await Clipboard.setData(ClipboardData(text: _url ?? ''));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ar ? 'تم نسخ الرابط' : 'Link copied')),
      );
    }
  }
}
