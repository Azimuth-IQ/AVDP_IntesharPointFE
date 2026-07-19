import 'package:inteshar/features/entities/domain/entity_type.dart';

/// Projected entity row from `GET /api/entity/summary`, `GET /api/entity/search`
/// and `GET /api/entity/children`. Heavy arrays (`productsIds`, `childrenIds`,
/// `users`) and branding are stripped; the counts are computed server-side.
/// Never carries user passwords.
class EntitySummaryRow {
  final String id;
  final String name;
  final EntityType type;
  final String parentId;
  final String parentName;
  final int childrenCount;
  final int productsCount;
  final int userCount;
  final String slogan;
  final List<String> governorates; // governorate codes the entity operates in
  final bool active; // resolved server-side (legacy null → active)

  const EntitySummaryRow({
    this.id = '',
    this.name = '',
    this.type = EntityType.STORE,
    this.parentId = '',
    this.parentName = '',
    this.childrenCount = 0,
    this.productsCount = 0,
    this.userCount = 0,
    this.slogan = '',
    this.governorates = const [],
    this.active = true,
  });

  String get label => name.isNotEmpty ? name : id;

  factory EntitySummaryRow.fromJson(Map<String, dynamic> j) => EntitySummaryRow(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        type: EntityType.values.firstWhere(
          (e) => e.name == (j['type'] as String? ?? 'STORE'),
          orElse: () => EntityType.STORE,
        ),
        parentId: j['parentId'] as String? ?? '',
        parentName: j['parentName'] as String? ?? '',
        childrenCount: (j['childrenCount'] as num?)?.toInt() ?? 0,
        productsCount: (j['productsCount'] as num?)?.toInt() ?? 0,
        userCount: (j['userCount'] as num?)?.toInt() ?? 0,
        slogan: j['slogan'] as String? ?? '',
        governorates: (j['governorates'] as List<dynamic>?)?.cast<String>() ?? const [],
        active: j['active'] as bool? ?? true,
      );
}
