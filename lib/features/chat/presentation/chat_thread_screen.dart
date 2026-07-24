import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/chat/data/chat_repository.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

/// One conversation (B-057, التواصل): a message list + composer with 10 s polling.
/// [readOnly] hides the composer for HQ oversight of others' threads.
///
/// [embedded] = true renders WITHOUT its own Scaffold/AppBar (a slim in-body title
/// row instead), so it can live inside another screen's tab (the POS التواصل tab)
/// without stacking a second app bar. The default (false) wraps it in a Scaffold +
/// AppBar for use as a pushed route from the threads list.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({
    super.key,
    required this.withId,
    required this.withName,
    this.readOnly = false,
    this.embedded = false,
  });

  final String withId;
  final String withName;
  final bool readOnly;
  final bool embedded;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  Object? _error;
  Timer? _poll;

  String get _myId =>
      (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id ?? '';

  ChatRepository get _repo => ChatRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.messages(widget.withId);
      if (!mounted) return;
      setState(() {
        _messages = page.items.reversed.toList(); // oldest→newest for the list
        _loading = false;
      });
      if (!widget.readOnly) await _repo.markRead(widget.withId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    try {
      final page = await _repo.messages(widget.withId);
      if (!mounted) return;
      final next = page.items.reversed.toList();
      if (next.length != _messages.length) {
        setState(() => _messages = next);
        if (!widget.readOnly) await _repo.markRead(widget.withId);
      }
    } catch (_) {
      // Transient — the next tick retries.
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await _repo.send(toId: widget.withId, text: text);
      _input.clear();
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      _scrollToEnd();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = Column(children: [
      if (widget.embedded) _slimTitle(),
      Expanded(child: _body()),
      if (!widget.readOnly) _composer(),
    ]);
    // Embedded (a tab body): no Scaffold/AppBar — the host screen owns those.
    if (widget.embedded) return conversation;
    return Scaffold(
      appBar: AppBar(title: Text(widget.withName)),
      body: conversation,
    );
  }

  /// Slim in-body header shown only in embedded mode (no AppBar to carry the name).
  Widget _slimTitle() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(children: [
        Icon(Icons.forum_outlined, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(widget.withName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _body() {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    if (_messages.isEmpty) {
      return Center(
        child: Text(ar ? 'لا توجد رسائل بعد.' : 'No messages yet.',
            style: IntesharType.sans(14, color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i], cs),
    );
  }

  Widget _bubble(ChatMessage m, ColorScheme cs) {
    final mine = m.fromEntityId == _myId;
    final when = m.createdAt.length >= 16
        ? m.createdAt.substring(11, 16)
        : '';
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? context.tones.brand : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text,
              style: IntesharType.sans(13.5,
                  color: mine ? IntesharColors.ink : cs.onSurface)),
          if (when.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(when,
                style: IntesharType.mono(9.5,
                    color: (mine ? IntesharColors.ink : cs.onSurfaceVariant)
                        .withValues(alpha: 0.6))),
          ],
        ]),
      ),
    );
  }

  Widget _composer() {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: ar ? 'اكتب رسالة…' : 'Type a message…',
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send, size: 20),
          ),
        ]),
      ),
    );
  }
}
