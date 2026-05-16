import 'package:inteshar/features/entities/domain/entity_type.dart';

class EntityMeta {
  final String name;
  final String slogan;
  final String description;
  final String logoUrl;
  final String backgroundUrl;
  final List<String> sliderImagesUrl;

  const EntityMeta({this.name = '', this.slogan = '', this.description = '', this.logoUrl = '', this.backgroundUrl = '', this.sliderImagesUrl = const []});

  factory EntityMeta.fromJson(Map<String, dynamic> j) => EntityMeta(
    name: j['name'] as String? ?? '',
    slogan: j['slogan'] as String? ?? '',
    description: j['description'] as String? ?? '',
    logoUrl: j['logoUrl'] as String? ?? '',
    backgroundUrl: j['backgroundUrl'] as String? ?? '',
    sliderImagesUrl: (j['sliderImagesUrl'] as List<dynamic>?)?.cast<String>() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'slogan': slogan,
    'description': description,
    'logoUrl': logoUrl,
    'backgroundUrl': backgroundUrl,
    'sliderImagesUrl': sliderImagesUrl,
  };

  EntityMeta copyWith({String? name, String? slogan, String? description, String? logoUrl, String? backgroundUrl, List<String>? sliderImagesUrl}) => EntityMeta(
    name: name ?? this.name,
    slogan: slogan ?? this.slogan,
    description: description ?? this.description,
    logoUrl: logoUrl ?? this.logoUrl,
    backgroundUrl: backgroundUrl ?? this.backgroundUrl,
    sliderImagesUrl: sliderImagesUrl ?? this.sliderImagesUrl,
  );
}

class EntityUser {
  final String id;
  final String phone;
  final String password;
  final UserRole role;

  const EntityUser({this.id = '', required this.phone, this.password = '', required this.role});

  factory EntityUser.fromJson(Map<String, dynamic> j) => EntityUser(
    id: j['id'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    password: j['password'] as String? ?? '',
    role: UserRole.values.firstWhere((e) => e.name == (j['role'] as String? ?? 'USER'), orElse: () => UserRole.USER),
  );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'phone': phone, 'role': role.name};
    if (id.isNotEmpty) m['id'] = id;
    if (password.isNotEmpty) m['password'] = password;
    return m;
  }
}

class Entity {
  final String id;
  final EntityMeta meta;
  final String parent;
  final EntityType type;
  final List<String> childrenIds;
  final List<String> productsIds;
  final List<EntityUser> users;

  const Entity({required this.id, required this.meta, this.parent = '', required this.type, this.childrenIds = const [], this.productsIds = const [], this.users = const []});

  factory Entity.fromJson(Map<String, dynamic> j) => Entity(
    id: j['id'] as String? ?? j['_id'] as String? ?? '',
    meta: EntityMeta.fromJson(j['meta'] as Map<String, dynamic>? ?? {}),
    parent: j['parent'] as String? ?? '',
    type: EntityType.values.firstWhere((e) => e.name == (j['type'] as String? ?? 'INTESHAR'), orElse: () => EntityType.INTESHAR),
    childrenIds: (j['childrenIds'] as List<dynamic>?)?.cast<String>() ?? [],
    productsIds: (j['productsIds'] as List<dynamic>?)?.cast<String>() ?? [],
    users: (j['users'] as List<dynamic>?)?.map((u) => EntityUser.fromJson(u as Map<String, dynamic>)).toList() ?? [],
  );

  Map<String, dynamic> toJson({bool includeUsers = false}) {
    final m = <String, dynamic>{
      'id': id,
      'meta': meta.toJson(),
      'parent': parent.isEmpty ? null : parent,
      'type': type.name,
      'childrenIds': childrenIds,
      'productsIds': productsIds,
    };
    if (includeUsers && users.isNotEmpty) {
      m['users'] = users.map((u) => u.toJson()).toList();
    }
    return m;
  }

  Entity copyWith({String? id, EntityMeta? meta, String? parent, EntityType? type, List<String>? childrenIds, List<String>? productsIds, List<EntityUser>? users}) => Entity(
    id: id ?? this.id,
    meta: meta ?? this.meta,
    parent: parent ?? this.parent,
    type: type ?? this.type,
    childrenIds: childrenIds ?? this.childrenIds,
    productsIds: productsIds ?? this.productsIds,
    users: users ?? this.users,
  );
}
