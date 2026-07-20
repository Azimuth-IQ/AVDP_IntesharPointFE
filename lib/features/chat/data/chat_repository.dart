import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// One conversation in the caller's chat list (B-057).
class ChatThread {
  final String withId;
  final String withName;
  final EntityType withTier;
  final String lastMessage;
  final String lastAt;
  final int unread;

  const ChatThread({
    this.withId = '',
    this.withName = '',
    this.withTier = EntityType.STORE,
    this.lastMessage = '',
    this.lastAt = '',
    this.unread = 0,
  });

  String get label => withName.isNotEmpty ? withName : withId;

  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
        withId: j['withId'] as String? ?? '',
        withName: j['withName'] as String? ?? '',
        withTier: EntityType.values.firstWhere(
          (e) => e.name == (j['withTier'] as String? ?? 'STORE'),
          orElse: () => EntityType.STORE,
        ),
        lastMessage: j['lastMessage'] as String? ?? '',
        lastAt: j['lastAt'] as String? ?? '',
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );
}

/// One chat message (B-057).
class ChatMessage {
  final String id;
  final String fromEntityId;
  final String fromName;
  final String toEntityId;
  final String text;
  final String createdAt;

  const ChatMessage({
    this.id = '',
    this.fromEntityId = '',
    this.fromName = '',
    this.toEntityId = '',
    this.text = '',
    this.createdAt = '',
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String? ?? '',
        fromEntityId: j['fromEntityId'] as String? ?? '',
        fromName: j['fromName'] as String? ?? '',
        toEntityId: j['toEntityId'] as String? ?? '',
        text: j['text'] as String? ?? '',
        createdAt: j['createdAt']?.toString() ?? '',
      );
}

/// Thin client for the chat slice. Pairing rules are server-enforced.
class ChatRepository {
  final ApiClient _api;
  ChatRepository(this._api);

  /// The caller's conversations. HQ may pass [all] for read-only oversight.
  Future<List<ChatThread>> threads({bool all = false}) async {
    final r = await _api.get(Endpoints.chatThreads,
        params: {if (all) 'all': true});
    return _api.unwrap(r, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => ChatThread.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// One conversation, newest first.
  Future<Paged<ChatMessage>> messages(String withId, {int page = 0, int size = 50}) async {
    final r = await _api.get(Endpoints.chatMessages,
        params: {'withId': withId, 'page': page, 'size': size});
    return _api.unwrap(r, (d) => Paged.from(d, ChatMessage.fromJson, size: size));
  }

  Future<ChatMessage> send({required String toId, required String text}) async {
    final r = await _api.post(Endpoints.chatSend, data: {'toId': toId, 'text': text});
    return _api.unwrap(r, (d) => ChatMessage.fromJson(d as Map<String, dynamic>));
  }

  Future<void> markRead(String withId) async {
    await _api.post(Endpoints.chatRead, data: {'withId': withId});
  }
}
