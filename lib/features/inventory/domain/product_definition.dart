import 'package:inteshar/features/inventory/domain/voucher_template.dart';

class ProductDefinition {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final String defaultPrice;
  final String sku;
  final String companyId; // owning Company; '' when uncategorized

  /// Print/redeem template applied by the Store/POS. Defaults to a sensible
  /// template when the backend hasn't stored one yet.
  final VoucherTemplate template;

  /// PROD-023: true = prints with its company's template ([template] is then only the
  /// starting point for "customise"); false = [template] is its own. null = not known yet
  /// (an old backend, or a new category) — never sent, so the backend keeps or decides.
  final bool? followsCompanyTemplate;

  const ProductDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.imageUrl = '',
    required this.defaultPrice,
    required this.sku,
    this.companyId = '',
    this.template = const VoucherTemplate(),
    this.followsCompanyTemplate,
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
        companyId: j['companyId'] as String? ?? '',
        template: VoucherTemplate.fromJson(j['voucherTemplate'] as Map<String, dynamic>?),
        followsCompanyTemplate: j['followsCompanyTemplate'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'defaultPrice': defaultPrice,
        'sku': sku,
        if (companyId.isNotEmpty) 'companyId': companyId,
        'voucherTemplate': template.toJson(),
        if (followsCompanyTemplate != null) 'followsCompanyTemplate': followsCompanyTemplate,
      };

  ProductDefinition copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    String? defaultPrice,
    String? sku,
    String? companyId,
    VoucherTemplate? template,
    bool? followsCompanyTemplate,
  }) =>
      ProductDefinition(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        defaultPrice: defaultPrice ?? this.defaultPrice,
        sku: sku ?? this.sku,
        companyId: companyId ?? this.companyId,
        template: template ?? this.template,
        followsCompanyTemplate: followsCompanyTemplate ?? this.followsCompanyTemplate,
      );
}
