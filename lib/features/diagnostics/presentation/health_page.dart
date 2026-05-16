import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/storage/session_storage.dart';

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
    String masked = '';
    if (token != null && token.length > 12) {
      masked =
          '${token.substring(0, 6)}…${token.substring(token.length - 6)}';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _runChecks,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connection',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _InfoRow('Base URL', _baseUrl),
                  _InfoRow('JWT', _maskedToken),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Health Checks',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_results.isEmpty)
            const Text('No results yet.')
          else
            ..._results.entries.map(
              (e) => _HealthCard(label: e.key, result: e.value),
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final String label;
  final _HealthResult result;

  const _HealthCard({required this.label, required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(
          result.ok ? Icons.check_circle : Icons.error,
          color: result.ok ? Colors.green : Colors.red,
        ),
        title: Text(label),
        subtitle: Text(
          result.ok
              ? 'HTTP ${result.statusCode}'
              : 'Failed',
          style: TextStyle(
              color: result.ok ? Colors.green : Colors.red,
              fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                _formatData(result.data),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatData(dynamic data) {
    if (data == null) return 'null';
    if (data is Map || data is List) {
      // Simple pretty-print without dart:convert
      return data.toString();
    }
    return data.toString();
  }
}

class _HealthResult {
  final bool ok;
  final int statusCode;
  final dynamic data;

  const _HealthResult({
    required this.ok,
    required this.statusCode,
    required this.data,
  });
}
