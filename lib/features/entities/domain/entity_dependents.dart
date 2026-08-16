/// What still hangs off an account, and therefore what stands between it and
/// being deleted.
///
/// An account is deletable only once it is a leaf, so "delete this Main Agent" is
/// really a short sequence: clear its points of sale, then its sub-agents, then
/// the agent. This is the map of that sequence.
class EntityDependents {
  final String id;
  final String name;
  final String type;
  final List<DependentSubAgent> subAgents;
  final List<DependentStore> stores;
  final int subAgentCount;
  final int storeCount;
  final bool deletable;

  const EntityDependents({
    required this.id,
    required this.name,
    required this.type,
    this.subAgents = const [],
    this.stores = const [],
    this.subAgentCount = 0,
    this.storeCount = 0,
    this.deletable = false,
  });

  int get total => subAgentCount + storeCount;

  factory EntityDependents.fromJson(Map<String, dynamic> j) => EntityDependents(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
        subAgents: ((j['subAgents'] as List<dynamic>?) ?? const [])
            .map((e) => DependentSubAgent.fromJson(e as Map<String, dynamic>))
            .toList(),
        stores: ((j['stores'] as List<dynamic>?) ?? const [])
            .map((e) => DependentStore.fromJson(e as Map<String, dynamic>))
            .toList(),
        subAgentCount: (j['subAgentCount'] as num?)?.toInt() ?? 0,
        storeCount: (j['storeCount'] as num?)?.toInt() ?? 0,
        deletable: j['deletable'] as bool? ?? false,
      );
}

class DependentSubAgent {
  final String id;
  final String name;
  final String? governorate;

  /// Shops still under this sub-agent. Non-zero means it cannot be deleted yet
  /// either — its own shops have to go first.
  final int storeCount;

  const DependentSubAgent({
    required this.id,
    required this.name,
    this.governorate,
    this.storeCount = 0,
  });

  bool get isDeletable => storeCount == 0;

  factory DependentSubAgent.fromJson(Map<String, dynamic> j) => DependentSubAgent(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        governorate: j['governorate'] as String?,
        storeCount: (j['storeCount'] as num?)?.toInt() ?? 0,
      );
}

class DependentStore {
  final String id;
  final String name;
  final String? governorate;
  final String? hostId;
  final String? hostName;

  /// The POS operator's phone. Removing a shop goes through the POS revoke
  /// endpoint, which is keyed on this — a row without it cannot be revoked and
  /// falls back to a plain entity delete.
  final String? operatorPhone;

  const DependentStore({
    required this.id,
    required this.name,
    this.governorate,
    this.hostId,
    this.hostName,
    this.operatorPhone,
  });

  factory DependentStore.fromJson(Map<String, dynamic> j) => DependentStore(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        governorate: j['governorate'] as String?,
        hostId: j['hostId'] as String?,
        hostName: j['hostName'] as String?,
        operatorPhone: j['operatorPhone'] as String?,
      );
}
