class ProductDefinition {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final String defaultPrice;
  final String sku;

  const ProductDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.imageUrl = '',
    required this.defaultPrice,
    required this.sku,
  });

  factory ProductDefinition.fromJson(Map<String, dynamic> j) =>
      ProductDefinition(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        imageUrl: j['imageUrl'] as String? ?? '',
        defaultPrice: j['defaultPrice'] as String? ?? '0',
        sku: j['sku'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'defaultPrice': defaultPrice,
        'sku': sku,
      };

  ProductDefinition copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    String? defaultPrice,
    String? sku,
  }) =>
      ProductDefinition(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        defaultPrice: defaultPrice ?? this.defaultPrice,
        sku: sku ?? this.sku,
      );
}
