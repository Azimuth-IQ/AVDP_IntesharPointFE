import 'package:inteshar/features/inventory/domain/voucher_template.dart';

class ProductDefinition {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final String defaultPrice;
  final String sku;

  /// Print/redeem template applied by the Store/POS. Defaults to a sensible
  /// template when the backend hasn't stored one yet.
  final VoucherTemplate template;

  const ProductDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.imageUrl = '',
    required this.defaultPrice,
    required this.sku,
    this.template = const VoucherTemplate(),
  });

  factory ProductDefinition.fromJson(Map<String, dynamic> j) =>
      ProductDefinition(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        imageUrl: j['imageUrl'] as String? ?? '',
        defaultPrice: (j['defaultPrice'] is num)
            ? (j['defaultPrice'] as num).toInt().toString()
            : (j['defaultPrice']?.toString() ?? '0'),
        sku: j['sku'] as String? ?? '',
        template: VoucherTemplate.fromJson(j['voucherTemplate'] as Map<String, dynamic>?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'defaultPrice': defaultPrice,
        'sku': sku,
        'voucherTemplate': template.toJson(),
      };

  ProductDefinition copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    String? defaultPrice,
    String? sku,
    VoucherTemplate? template,
  }) =>
      ProductDefinition(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        defaultPrice: defaultPrice ?? this.defaultPrice,
        sku: sku ?? this.sku,
        template: template ?? this.template,
      );
}
