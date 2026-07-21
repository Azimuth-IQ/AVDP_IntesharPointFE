import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// B-061: subscribes to an ntfy topic's JSON stream and invokes [onPing] with the
/// message kind (alert | notification | chat) for each real message. The stream
/// carries only a NON-SENSITIVE ping; the app fetches content over the authed API.
///
/// Robust to drops: reconnects with capped backoff and resumes from the last seen
/// message id (`since=`) so nothing is missed across a reconnect. A no-op when the
/// base URL or topic is empty.
class PushSubscriber {
  PushSubscriber({
    required this.baseUrl,
    required this.topic,
    required this.onPing,
  });

  final String baseUrl;
  final String topic;
  final void Function(String kind) onPing;

  final Dio _dio = Dio();
  CancelToken? _cancel;
  bool _stopped = false;
  int _backoffMs = 1000;
  String? _sinceId;

  bool get _configured => baseUrl.isNotEmpty && topic.isNotEmpty;

  void start() {
    if (!_configured || _stopped) return;
    _connect();
  }

  void stop() {
    _stopped = true;
    _cancel?.cancel('stopped');
  }

  Future<void> _connect() async {
    if (_stopped || !_configured) return;
    _cancel = CancelToken();
    final url = '$baseUrl/inteshar-$topic/json';
    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        queryParameters: {'since': _sinceId ?? 'all'},
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: Duration.zero, // long-lived stream
          headers: {'Accept': 'application/x-ndjson'},
        ),
        cancelToken: _cancel,
      );
      _backoffMs = 1000; // connected → reset backoff
      const splitter = LineSplitter();
      var buffer = '';
      await for (final chunk in resp.data!.stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
        final lines = splitter.convert(buffer);
        // Keep the last (possibly partial) line in the buffer.
        buffer = buffer.endsWith('\n') ? '' : (lines.isNotEmpty ? lines.removeLast() : buffer);
        for (final line in lines) {
          _handleLine(line);
        }
      }
    } catch (e) {
      // fall through to reconnect
      if (kDebugMode) debugPrint('[push] stream ended: $e');
    }
    if (!_stopped) _scheduleReconnect();
  }

  void _handleLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final m = jsonDecode(trimmed) as Map<String, dynamic>;
      final event = m['event'] as String?;
      final id = m['id'] as String?;
      if (id != null) _sinceId = id;
      if (event != 'message') return; // ignore open/keepalive/poll_request
      // Kind rides in the tags (X-Tags) or the body.
      final tags = (m['tags'] as List?)?.cast<String>() ?? const [];
      final body = (m['message'] as String? ?? '').toLowerCase();
      String kind = 'notification';
      for (final t in ['alert', 'chat', 'notification']) {
        if (tags.contains(t) || body == t) {
          kind = t;
          break;
        }
      }
      onPing(kind);
    } catch (_) {
      // Non-JSON keepalive line — ignore.
    }
  }

  void _scheduleReconnect() {
    final delay = Duration(milliseconds: _backoffMs);
    _backoffMs = (_backoffMs * 2).clamp(1000, 30000);
    Future.delayed(delay, () {
      if (!_stopped) _connect();
    });
  }
}
