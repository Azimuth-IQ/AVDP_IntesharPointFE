import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/chat/data/chat_repository.dart';
import 'package:inteshar/features/chat/presentation/chat_thread_screen.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// UX-28 — the three things an account cannot give itself.
///
/// Balance only enters the system when HQ grants it after an off-system payment,
/// stock only arrives when HQ uploads a batch, and POS points are only ever
/// distributed by HQ. None of the three is modelled as a request: the whole
/// supply line of an agent runs through *asking*, and until now the app expected
/// the agent to work that out, open التواصل and type a sentence from scratch —
/// even on the one screen that says "ask headquarters" in plain text.
///
/// This is deliberately still **a message**, not a workflow. There is no request
/// entity on the server and one must not be invented on the client; what the
/// action buys is that the sentence is composed for you — who is asking, for
/// what, how much, and what they hold today — and lands in the right thread,
/// unsent, so it can be edited before it goes.
enum SupplyRequestKind { balance, stock, posPoints }

/// What the dialog produced: a counterparty and the sentence to prefill.
class _Draft {
  const _Draft(this.toId, this.toName, this.text);
  final String toId;
  final String toName;
  final String text;
}

/// Asks for the missing numbers, then opens the chat thread with the composed
/// message already in the composer. Nothing is sent by this call.
Future<void> showSupplyRequest(
  BuildContext context,
  WidgetRef ref, {
  required SupplyRequestKind kind,

  /// Stock requests only: the product/category being asked for, prefilled.
  String? category,

  /// What the account holds today (balance, cards, POS points) — quoted in the
  /// message so the reader does not have to look it up.
  num? current,
}) async {
  final auth = ref.read(authStateProvider).valueOrNull;
  final entity = auth is AuthAuthenticated ? auth.entity : null;
  if (entity == null) return;

  final draft = await showDialog<_Draft>(
    context: context,
    builder: (_) => _SupplyRequestDialog(
      kind: kind,
      category: category,
      current: current,
      accountName: entity.meta.name.isNotEmpty ? entity.meta.name : entity.id,
      parentId: entity.parent,
      repo: ChatRepository(ref.read(apiClientProvider)),
    ),
  );
  if (draft == null || !context.mounted) return;

  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChatThreadScreen(
      withId: draft.toId,
      withName: draft.toName,
      draft: draft.text,
    ),
  ));
}

class _SupplyRequestDialog extends StatefulWidget {
  const _SupplyRequestDialog({
    required this.kind,
    required this.category,
    required this.current,
    required this.accountName,
    required this.parentId,
    required this.repo,
  });

  final SupplyRequestKind kind;
  final String? category;
  final num? current;
  final String accountName;
  final String parentId;
  final ChatRepository repo;

  @override
  State<_SupplyRequestDialog> createState() => _SupplyRequestDialogState();
}

class _SupplyRequestDialogState extends State<_SupplyRequestDialog> {
  final _amount = TextEditingController();
  final _category = TextEditingController();

  List<ChatThread> _threads = const [];
  ChatThread? _to;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _category.text = widget.category ?? '';
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final threads = await widget.repo.threads();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _to = _preferred(threads);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Who to ask, by default.
  ///
  /// Supply comes down the tree, so the parent is the answer for balance and
  /// cards. POS points are HQ-only (B-043/B-068) — a Main/Sub Agent's own parent
  /// cannot grant them — so those prefer the HQ thread when the caller has one
  /// (the BRD bypass channel), and fall back to the parent, who can relay.
  ChatThread? _preferred(List<ChatThread> threads) {
    if (threads.isEmpty) return null;
    ChatThread? byId(String id) {
      for (final t in threads) {
        if (t.withId == id) return t;
      }
      return null;
    }

    ChatThread? hq() {
      for (final t in threads) {
        if (t.withTier == EntityType.INTESHAR) return t;
      }
      return null;
    }

    final parent = widget.parentId.isEmpty ? null : byId(widget.parentId);
    final first = widget.kind == SupplyRequestKind.posPoints
        ? (hq() ?? parent)
        : (parent ?? hq());
    return first ?? threads.first;
  }

  bool get _needsCategory => widget.kind == SupplyRequestKind.stock;

  /// Amount for a balance request, count for the other two.
  bool get _isMoney => widget.kind == SupplyRequestKind.balance;

  num get _typed => parseAmount(_amount.text) ?? 0;

  bool get _ready => _to != null && _typed > 0;

  String _title(bool ar) => switch (widget.kind) {
        SupplyRequestKind.balance => ar ? 'طلب رصيد' : 'Request balance',
        SupplyRequestKind.stock => ar ? 'طلب كروت' : 'Request cards',
        SupplyRequestKind.posPoints => ar ? 'طلب نقاط بيع' : 'Request POS points',
      };

  /// What the number means, as it reads inside the message.
  String _askLabel(bool ar) => switch (widget.kind) {
        SupplyRequestKind.balance => ar ? 'المبلغ المطلوب' : 'Amount requested',
        SupplyRequestKind.stock => ar ? 'الكمية المطلوبة' : 'Quantity requested',
        SupplyRequestKind.posPoints =>
          ar ? 'عدد النقاط المطلوبة' : 'Points requested',
      };

  /// The same thing as a field label — money carries its unit here.
  String _amountLabel(bool ar) => _isMoney
      ? '${_askLabel(ar)} (${Formatters.currencyUnit(ar ? 'ar' : 'en')})'
      : _askLabel(ar);

  String _currentLabel(bool ar) => switch (widget.kind) {
        SupplyRequestKind.balance => ar ? 'رصيدي الحالي' : 'My balance now',
        SupplyRequestKind.stock => ar ? 'المتوفر لديّ' : 'What I hold now',
        SupplyRequestKind.posPoints => ar ? 'المتاح لديّ' : 'Available to me now',
      };

  /// The sentence itself. Every line is a fact the reader would otherwise have
  /// to go and look up: who is asking, for what, how much, against what they
  /// already hold.
  String _compose(bool ar) {
    final amount = _isMoney
        ? Formatters.iqd(_typed.round(), languageCode: ar ? 'ar' : 'en')
        : Formatters.money(_typed);
    final lines = <String>[
      _title(ar),
      ar ? 'الحساب: ${widget.accountName}' : 'Account: ${widget.accountName}',
      if (_needsCategory && _category.text.trim().isNotEmpty)
        ar ? 'الفئة: ${_category.text.trim()}' : 'Category: ${_category.text.trim()}',
      '${_askLabel(ar)}: $amount',
      if (widget.current != null)
        '${_currentLabel(ar)}: ${_isMoney ? Formatters.iqd(widget.current!.round(), languageCode: ar ? 'ar' : 'en') : Formatters.money(widget.current)}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.forum_outlined, color: context.tones.brandOnSurface),
      title: Text(_title(ar), textAlign: TextAlign.center),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text(friendlyError(_error!, context),
                    style: IntesharType.sans(14, color: cs.error))
                : _form(ar, cs),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ar ? 'إلغاء' : 'Cancel'),
        ),
        if (_error != null)
          FilledButton(
            onPressed: _load,
            child: Text(ar ? 'إعادة المحاولة' : 'Retry'),
          )
        else
          FilledButton.icon(
            onPressed: !_ready
                ? null
                : () => Navigator.pop(
                      context,
                      _Draft(_to!.withId, _to!.label, _compose(ar)),
                    ),
            icon: const Icon(Icons.send_outlined, size: 16),
            // Not "Send": the message opens in the thread and the agent presses
            // send. A request that leaves on one tap of a dialog is a workflow,
            // and this is a sentence.
            label: Text(ar ? 'كتابة الرسالة' : 'Write the message'),
          ),
      ],
    );
  }

  Widget _form(bool ar, ColorScheme cs) {
    if (_threads.isEmpty) {
      return Text(
        ar
            ? 'لا توجد جهة يمكن مراسلتها من هذا الحساب بعد.'
            : 'This account has no one to message yet.',
        style: IntesharType.sans(14, color: cs.onSurfaceVariant),
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One counterparty: say who, don't make them pick from a list of one.
          if (_threads.length == 1)
            Row(children: [
              Icon(Icons.person_outline, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ar ? 'إلى ${_to?.label ?? ''}' : 'To ${_to?.label ?? ''}',
                  style: IntesharType.sans(14, color: cs.onSurface, w: IntesharWeight.semibold),
                ),
              ),
            ])
          else
            DropdownButtonFormField<ChatThread>(
              initialValue: _to,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: ar ? 'إلى' : 'To',
                isDense: true,
              ),
              items: _threads
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text('${t.label} · ${t.withTier.label}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _to = v),
            ),
          const SizedBox(height: 12),
          if (_needsCategory) ...[
            TextField(
              controller: _category,
              decoration: InputDecoration(
                labelText: ar ? 'الفئة' : 'Category',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: const [ThousandsInputFormatter()],
            autofocus: true,
            // UX-12: the amount is the last (and usually only) thing typed here
            // and the dialog already autofocuses it. Enter now does what the
            // button does — and is gated on the same `_ready`, so it cannot
            // draft a request the button would have refused.
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_ready) return;
              Navigator.pop(
                context,
                _Draft(_to!.withId, _to!.label, _compose(ar)),
              );
            },
            decoration: InputDecoration(
              labelText: _amountLabel(ar),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.current != null) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_currentLabel(ar),
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
              Text(
                _isMoney
                    ? Formatters.iqd(widget.current!.round(),
                        languageCode: ar ? 'ar' : 'en')
                    : Formatters.money(widget.current),
                style: IntesharType.mono(12, color: cs.onSurface),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Text(
            ar
                ? 'ستفتح المحادثة والرسالة جاهزة — يمكنك تعديلها قبل الإرسال.'
                : 'The conversation opens with the message ready — edit it before sending.',
            style: IntesharType.sans(12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
