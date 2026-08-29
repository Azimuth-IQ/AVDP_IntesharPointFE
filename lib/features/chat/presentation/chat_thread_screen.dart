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
    this.draft,
  });

  final String withId;
  final String withName;
  final bool readOnly;
  final bool embedded;

  /// UX-28: text placed in the composer on open, UNSENT. The supply-request
  /// actions (طلب رصيد / طلب كروت / طلب نقاط بيع) compose a sentence and hand it
  /// over here so the sender reads and edits it before it goes — a request is a
  /// message in this product, not a workflow, and nothing must leave on one tap.
  final String? draft;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

/// UX-92: a message that has left the composer but not yet the device. Chat is
/// the escalation channel — it gets used precisely when something is already
/// wrong and the link is at its worst — and it had no optimistic bubble and no
/// per-message state: a failure surfaced as a 4-second toast and nothing else.
enum _Delivery { sending, failed }

class _Outgoing {
  _Outgoing(this.text);
  final String text;
  _Delivery state = _Delivery.sending;
  String? reason;
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _messages = const [];

  /// Messages the user has sent that the server has not yet acknowledged. They
  /// render as real bubbles, below the delivered ones, carrying their own state.
  final List<_Outgoing> _outgoing = [];
  bool _loading = true;
  Object? _error;
  Timer? _poll;

  String get _myId =>
      (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id ?? '';

  ChatRepository get _repo => ChatRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    if (draft != null && draft.isNotEmpty) _input.text = draft;
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
    if (text.isEmpty) return;
    // The bubble appears immediately and the composer empties — the text is not
    // lost on failure, it lives in the bubble and can be retried from there.
    _input.clear();
    final pending = _Outgoing(text);
    setState(() => _outgoing.add(pending));
    _scrollToEnd();
    await _deliver(pending);
  }

  Future<void> _deliver(_Outgoing p) async {
    if (!mounted) return;
    setState(() {
      p.state = _Delivery.sending;
      p.reason = null;
    });
    try {
      final msg = await _repo.send(toId: widget.withId, text: p.text);
      if (!mounted) return;
      setState(() {
        _outgoing.remove(p);
        _messages = [..._messages, msg];
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        p.state = _Delivery.failed;
        p.reason = friendlyError(e, context);
      });
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
    if (_messages.isEmpty && _outgoing.isEmpty) {
      return Center(
        child: Text(ar ? 'لا توجد رسائل بعد.' : 'No messages yet.',
            style: IntesharType.sans(14, color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length + _outgoing.length,
      itemBuilder: (_, i) => i < _messages.length
          ? _bubble(_messages[i], cs)
          : _pendingBubble(_outgoing[i - _messages.length], cs, ar),
    );
  }

  Widget _bubble(ChatMessage m, ColorScheme cs) {
    final mine = m.fromEntityId == _myId;
    final when = m.createdAt.length >= 16
        ? m.createdAt.substring(11, 16)
        : '';
    // The bubble is a BRAND fill, so its foreground is the measured on-brand
    // ink — hardcoded `IntesharColors.ink` was black text on whatever colour a
    // white-label agent picked, including the dark ones.
    final onBubble = mine ? context.tones.onBrand : cs.onSurface;
    final footColor = onBubble.withValues(alpha: 0.6);
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
          Text(m.text, style: IntesharType.sans(14, color: onBubble)),
          if (when.isNotEmpty || mine) ...[
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (when.isNotEmpty)
                Text(when, style: IntesharType.mono(IntesharScale.caption, color: footColor)),
              // The delivered marker. Without it "sending" and "sent" looked
              // exactly the same, which is the whole of UX-92.
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(Icons.done, size: 12, color: footColor),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  /// A message still in flight, or one that failed and can be retried in place.
  Widget _pendingBubble(_Outgoing p, ColorScheme cs, bool ar) {
    final failed = p.state == _Delivery.failed;
    final fg = failed ? cs.onErrorContainer : context.tones.onBrand;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: failed
              ? cs.errorContainer
              : context.tones.brand.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: failed ? Border.all(color: context.status.danger) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.text, style: IntesharType.sans(14, color: fg)),
          const SizedBox(height: 4),
          if (!failed)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 1.6, color: fg.withValues(alpha: 0.7)),
              ),
              const SizedBox(width: 6),
              Text(ar ? 'جارٍ الإرسال…' : 'Sending…',
                  style: IntesharType.sans(11, color: fg.withValues(alpha: 0.8))),
            ])
          else ...[
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 12, color: context.status.danger),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  p.reason?.isNotEmpty == true
                      ? p.reason!
                      : (ar ? 'لم تُرسل' : 'Not sent'),
                  style: IntesharType.sans(11,
                      color: context.status.danger, w: IntesharWeight.semibold),
                ),
              ),
            ]),
            const SizedBox(height: 2),
            // UX-119: "Discard" throws away a message the server never took —
            // there is no undo and no copy of it anywhere else. Both buttons
            // carried `visualDensity: compact`, which drops Material's padded
            // tap target from 48dp to 40dp, and they sit side by side, so the
            // irreversible one was the smaller-than-floor target next to the
            // recoverable one. Density removed; the horizontal padding stays
            // tight so the pair still fits a narrow bubble.
            Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.sm),
                  foregroundColor: context.status.danger,
                ),
                onPressed: () => _deliver(p),
                icon: const Icon(Icons.refresh, size: 15),
                label: Text(ar ? 'إعادة المحاولة' : 'Retry',
                    style: IntesharText.body(w: IntesharWeight.bold)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.sm),
                  foregroundColor: cs.onSurfaceVariant,
                ),
                onPressed: () => setState(() => _outgoing.remove(p)),
                child: Text(ar ? 'تجاهل' : 'Discard',
                    style: IntesharText.body(w: IntesharWeight.semibold)),
              ),
            ]),
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
          // Always enabled: an in-flight message no longer blocks the composer,
          // because it is now visible as its own bubble rather than as a
          // disabled send button.
          IconButton.filled(
            // UX-150: the send button carried no name at all.
            tooltip: ar ? 'إرسال' : 'Send',
            onPressed: _send,
            icon: const Icon(Icons.send, size: 20),
          ),
        ]),
      ),
    );
  }
}
