/// A telecom provider (Asiacell, Zain, …) — the top of the catalog. Categories
/// (ProductDefinitions) reference it by id. Mirrors backend `Pricing/Models/Company`.
class Company {
  final String id;
  final String name;
  final String logoUrl;
  final String description;
  final int displayOrder;
  final bool active;

  const Company({
    this.id = '',
    required this.name,
    this.logoUrl = '',
    this.description = '',
    this.displayOrder = 0,
    this.active = true,
  });

  factory Company.fromJson(Map<String, dynamic> j) => Company(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        logoUrl: j['logoUrl'] as String? ?? '',
        description: j['description'] as String? ?? '',
        displayOrder: (j['displayOrder'] as num?)?.toInt() ?? 0,
        active: j['active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'logoUrl': logoUrl,
        'description': description,
        'displayOrder': displayOrder,
        'active': active,
      };

  Company copyWith({String? id, String? name, String? logoUrl, String? description, int? displayOrder, bool? active}) =>
      Company(
        id: id ?? this.id,
        name: name ?? this.name,
        logoUrl: logoUrl ?? this.logoUrl,
        description: description ?? this.description,
        displayOrder: displayOrder ?? this.displayOrder,
        active: active ?? this.active,
      );
}
