import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/chat/data/chat_repository.dart';
import 'package:inteshar/features/chat/presentation/chat_thread_screen.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// التواصل thread list (B-057). Every reachable counterparty is shown as a row
/// (tap to start), so the list itself is the contact picker: a POS → its parent
/// agent; an AGENT1 → its children + HQ; an AGENT2 → its children + parent + HQ
/// (the BRD bypass channel, B-069); HQ → its main-agents, with an oversight
/// toggle to read every thread. Polls every 15 s for new activity.
class ChatThreadsPage extends ConsumerStatefulWidget {
  const ChatThreadsPage({super.key});

  @override
  ConsumerState<ChatThreadsPage> createState() => _ChatThreadsPageState();
}

class _ChatThreadsPageState extends ConsumerState<ChatThreadsPage> {
  List<ChatThread> _threads = const [];
  bool _loading = true;
  bool _oversight = false;
  Object? _error;
  Timer? _poll;

  bool get _isHq =>
      (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.type ==
      EntityType.INTESHAR;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final threads = await ChatRepository(ref.read(apiClientProvider))
          .threads(all: _oversight && _isHq);
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
      });
    } catch (e) {
      if (mounted && !silent) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _open(ChatThread t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatThreadScreen(
        withId: t.withId,
        withName: t.label,
        readOnly: _oversight && _isHq,
      ),
    ));
    _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return MaxWidthBox(
      maxWidth: 760,
      child: Column(children: [
        PageHeader(
          eyebrow: ar ? 'التواصل' : 'MESSAGES',
          title: ar ? 'المحادثات' : 'Conversations',
          subtitle: ar
              ? 'راسل حساباتك مباشرة لمعالجة المشاكل والطلبات'
              : 'Message your accounts directly to resolve issues and requests',
          trailing: _isHq
              ? FilterChip(
                  label: Text(ar ? 'كل المحادثات' : 'All threads'),
                  selected: _oversight,
                  onSelected: (v) {
                    setState(() => _oversight = v);
                    _load();
                  },
                )
              : null,
        ),
        Expanded(child: _body(ar)),
      ]),
    );
  }

  Widget _body(bool ar) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    if (_threads.isEmpty) {
      // Reachable contacts normally appear here as tappable rows; a truly empty
      // list means there's no one to message yet — explain rather than dead-end.
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                ar
                    ? 'لا توجد جهات للتواصل بعد. ستظهر حساباتك هنا لبدء محادثة.'
                    : 'No one to message yet. Your accounts will appear here to start a conversation.',
                textAlign: TextAlign.center,
                style: IntesharType.sans(14, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        itemCount: _threads.length,
        itemBuilder: (_, i) => _threadTile(_threads[i], ar, cs),
      ),
    );
  }

  Widget _threadTile(ChatThread t, bool ar, ColorScheme cs) {
    final when = t.lastAt.length >= 16 ? t.lastAt.substring(0, 16).replaceFirst('T', ' ') : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkCard(
        padding: const EdgeInsets.all(12),
        onTap: () => _open(t),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: cs.primary.withValues(alpha: 0.14),
            child: Text(
              (t.label.isNotEmpty ? t.label[0] : '?').toUpperCase(),
              style: IntesharType.sans(15, color: cs.primary, w: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(t.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.sans(14.5, color: cs.onSurface, w: FontWeight.w700)),
                ),
                Text(t.withTier.label,
                    style: IntesharType.sans(10.5, color: cs.onSurfaceVariant)),
              ]),
              const SizedBox(height: 2),
              Text(
                t.lastMessage.isEmpty ? (ar ? 'ابدأ المحادثة' : 'Start the conversation') : t.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (when.isNotEmpty)
              Text(when.length > 10 ? when.substring(5) : when,
                  style: IntesharType.mono(10, color: cs.onSurfaceVariant)),
            if (t.unread > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                // UX-128: unread mail is not an error. The badge is ours and
                // deliberate — brand, so red keeps meaning something broke.
                decoration: BoxDecoration(
                    color: context.tones.brand,
                    borderRadius: BorderRadius.circular(999)),
                child: Text('${t.unread}',
                    style: IntesharType.sans(11,
                        color: context.tones.onBrand, w: FontWeight.w800)),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
