/// A HQ-managed POS-home slider image with server-resolved targeting (B-022).
class PosSlider {
  final String id;
  final String imageUrl;
  final bool active;
  final int order;

  /// ALL | TIER | ENTITY | GOVERNORATE
  final String audience;
  final List<String> tierTypes;
  final List<String> entityIds;
  final List<String> governorates;

  const PosSlider({
    required this.id,
    required this.imageUrl,
    required this.active,
    required this.order,
    required this.audience,
    this.tierTypes = const [],
    this.entityIds = const [],
    this.governorates = const [],
  });

  factory PosSlider.fromJson(Map<String, dynamic> j) => PosSlider(
        id: (j['id'] ?? '') as String,
        imageUrl: (j['imageUrl'] ?? '') as String,
        active: (j['active'] ?? true) as bool,
        order: (j['order'] ?? 0) as int,
        audience: (j['audience'] ?? 'ALL') as String,
        tierTypes: _strList(j['tierTypes']),
        entityIds: _strList(j['entityIds']),
        governorates: _strList(j['governorates']),
      );

  /// Body for POST/PUT `/api/slider`.
  Map<String, dynamic> toRequestJson() => {
        'imageUrl': imageUrl,
        'active': active,
        'order': order,
        'audience': audience,
        'tierTypes': tierTypes,
        'entityIds': entityIds,
        'governorates': governorates,
      };

  PosSlider copyWith({
    String? imageUrl,
    bool? active,
    int? order,
    String? audience,
    List<String>? tierTypes,
    List<String>? entityIds,
    List<String>? governorates,
  }) =>
      PosSlider(
        id: id,
        imageUrl: imageUrl ?? this.imageUrl,
        active: active ?? this.active,
        order: order ?? this.order,
        audience: audience ?? this.audience,
        tierTypes: tierTypes ?? this.tierTypes,
        entityIds: entityIds ?? this.entityIds,
        governorates: governorates ?? this.governorates,
      );

  static List<String> _strList(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];
}
