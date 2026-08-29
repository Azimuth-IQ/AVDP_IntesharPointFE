import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

class HealthPage extends ConsumerStatefulWidget {
  const HealthPage({super.key});

  @override
  ConsumerState<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends ConsumerState<HealthPage> {
  final Map<String, _HealthResult> _results = {};
  bool _loading = false;
  String _baseUrl = '';
  String _maskedToken = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = await sessionStorage.getBaseUrl();
    final token = await sessionStorage.getToken();
    String masked;
    if (token != null && token.length > 12) {
      masked = '${token.substring(0, 6)}…${token.substring(token.length - 6)}';
    } else if (token != null) {
      masked = '(token present)';
    } else {
      masked = '(no token)';
    }
    if (mounted) {
      setState(() {
        _baseUrl = url;
        _maskedToken = masked;
      });
    }
    await _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() {
      _loading = true;
      _results.clear();
    });

    final checks = {
      'General': Endpoints.healthGeneral,
      'RAM': Endpoints.healthRam,
      'CPU': Endpoints.healthCpu,
      'Storage': Endpoints.healthStorage,
    };

    final api = ref.read(apiClientProvider);

    for (final entry in checks.entries) {
      final label = entry.key;
      final path = entry.value;
      try {
        final r = await api.get(path);
        if (mounted) {
          setState(() => _results[label] = _HealthResult(
                ok: true,
                statusCode: r.statusCode ?? 0,
                data: r.data,
              ));
        }
      } catch (e) {
        if (mounted) {
          setState(() => _results[label] = _HealthResult(
                ok: false,
                statusCode: 0,
                data: e.toString(),
              ));
        }
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        // Diagnostics is pushed on top of the current screen, so provide an explicit
        // way back (pop). If it was somehow reached without a page below, fall back to
        // /login — the router redirects an authenticated session on to its home.
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l.commonClose,
          onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        ),
        title: Text(l.healthDiagnosticsTitle, style: Theme.of(context).appBarTheme.titleTextStyle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.healthRefresh,
            onPressed: _loading ? null : _runChecks,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          SectionLabel(l.healthConnectionSection),
          InkCard(
            ruleColor: cs.outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(l.healthBaseUrl, _baseUrl),
                const SizedBox(height: 6),
                _InfoRow(l.healthJwt, _maskedToken),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SectionLabel(l.healthChecksSection),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(IntesharSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_results.isEmpty)
            Text(l.healthNoResults)
          else
            ..._results.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.xs),
                  child: _HealthCard(label: e.key, result: e.value),
                )),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(label.toUpperCase(), style: IntesharType.overline(color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: cs.onSurface, letterSpacing: 0.4),
          ),
        ),
      ],
    );
  }
}

class _HealthCard extends StatefulWidget {
  final String label;
  final _HealthResult result;

  const _HealthCard({required this.label, required this.result});

  @override
  State<_HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends State<_HealthCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ok = widget.result.ok;
    final tone = ok ? IntesharColors.sage : cs.error;
    return InkCard(
      density: CardDensity.flush,
      ruleColor: tone,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Icon(ok ? Icons.check_circle : Icons.error_outline, size: 18, color: tone),
                  const SizedBox(width: IntesharSpacing.md),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: IntesharType.serif(16, color: cs.onSurface, w: IntesharWeight.semibold),
                    ),
                  ),
                  StampPill(
                    label: ok ? 'HTTP ${widget.result.statusCode}' : l.healthFailed,
                    color: tone,
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 160),
                    turns: _open ? 0.25 : 0,
                    child: Icon(Icons.chevron_right, size: 16, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                Container(height: 1, color: cs.outline),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    _formatData(widget.result.data),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11.5,
                      color: cs.onSurface,
                      height: 1.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatData(dynamic data) {
    if (data == null) return 'null';
    return data.toString();
  }
}

class _HealthResult {
  final bool ok;
  final int statusCode;
  final dynamic data;

  const _HealthResult({required this.ok, required this.statusCode, required this.data});
}
