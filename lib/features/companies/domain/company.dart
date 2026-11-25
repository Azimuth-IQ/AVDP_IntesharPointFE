import 'package:inteshar/features/inventory/domain/voucher_template.dart';

/// A telecom provider (Asiacell, Zain, …) — the top of the catalog. Categories
/// (ProductDefinitions) reference it by id. Mirrors backend `Pricing/Models/Company`.
class Company {
  final String id;
  final String name;
  final String logoUrl;
  /// PROD-028: the logo printed on receipts (transparent PNG), separate from [logoUrl], the
  /// full-colour picture on the POS tile. Empty = receipts use [logoUrl], as before.
  final String receiptLogoUrl;
  final String description;
  final int displayOrder;
  final bool active;
  // B-058 per-shop withdrawal cap (0 = unlimited) over a rolling window.
  final int withdrawalCap;
  final int withdrawalWindowHours;

  /// PROD-023: the print template its categories follow unless they have their own.
  /// null = the built-in default. Read-only here: set with [CompanyRepository.setTemplate],
  /// never sent by [toJson] (the backend keeps it on a company edit).
  final VoucherTemplate? voucherTemplate;

  const Company({
    this.id = '',
    required this.name,
    this.logoUrl = '',
    this.receiptLogoUrl = '',
    this.description = '',
    this.displayOrder = 0,
    this.active = true,
    this.withdrawalCap = 0,
    this.withdrawalWindowHours = 24,
    this.voucherTemplate,
  });

  factory Company.fromJson(Map<String, dynamic> j) => Company(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        logoUrl: j['logoUrl'] as String? ?? '',
        receiptLogoUrl: j['receiptLogoUrl'] as String? ?? '',
        description: j['description'] as String? ?? '',
        displayOrder: (j['displayOrder'] as num?)?.toInt() ?? 0,
        active: j['active'] as bool? ?? true,
        withdrawalCap: (j['withdrawalCap'] as num?)?.toInt() ?? 0,
        withdrawalWindowHours: (j['withdrawalWindowHours'] as num?)?.toInt() ?? 24,
        voucherTemplate: j['voucherTemplate'] is Map<String, dynamic>
            ? VoucherTemplate.fromJson(j['voucherTemplate'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'logoUrl': logoUrl,
        'receiptLogoUrl': receiptLogoUrl,
        'description': description,
        'displayOrder': displayOrder,
        'active': active,
        'withdrawalCap': withdrawalCap,
        'withdrawalWindowHours': withdrawalWindowHours,
      };

  Company copyWith({String? id, String? name, String? logoUrl, String? receiptLogoUrl, String? description, int? displayOrder, bool? active, int? withdrawalCap, int? withdrawalWindowHours}) =>
      Company(
        id: id ?? this.id,
        name: name ?? this.name,
        logoUrl: logoUrl ?? this.logoUrl,
        receiptLogoUrl: receiptLogoUrl ?? this.receiptLogoUrl,
        description: description ?? this.description,
        displayOrder: displayOrder ?? this.displayOrder,
        active: active ?? this.active,
        withdrawalCap: withdrawalCap ?? this.withdrawalCap,
        withdrawalWindowHours: withdrawalWindowHours ?? this.withdrawalWindowHours,
        voucherTemplate: voucherTemplate,
      );
}
