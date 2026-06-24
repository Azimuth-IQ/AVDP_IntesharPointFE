// ignore_for_file: constant_identifier_names
import 'package:inteshar/features/inventory/domain/product_definition.dart';

enum ProductStatus { AVAILABLE, SENT_FOR_PRINTING, PRINTED, FAILED_PRINTING, DAMAGED }

class Product {
  final String id;
  final int? version;
  final ProductDefinition productDefinition;
  final ProductStatus status;
  final String serialNumber;
  final String pin;
  final List<String> owners;
  final String currentOwner;

  /// Region-lock tag (governorate code). Null = not geo-locked (movable anywhere).
  final String? governorate;

  const Product({
    required this.id,
    this.version,
    required this.productDefinition,
    required this.status,
    required this.serialNumber,
    required this.pin,
    this.owners = const [],
    required this.currentOwner,
    this.governorate,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String? ?? '',
        version: j['version'] as int?,
        productDefinition: ProductDefinition.fromJson(
            j['productDefinition'] as Map<String, dynamic>? ?? {}),
        status: ProductStatus.values.firstWhere(
          (e) => e.name == (j['status'] as String? ?? 'AVAILABLE'),
          orElse: () => ProductStatus.AVAILABLE,
        ),
        serialNumber: j['serialNumber'] as String? ?? '',
        pin: j['pin'] as String? ?? '',
        owners: (j['owners'] as List<dynamic>?)?.cast<String>() ?? [],
        currentOwner: j['currentOwner'] as String? ?? '',
        governorate: j['governorate'] as String?,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'productDefinition': productDefinition.toJson(),
      'status': status.name,
      'serialNumber': serialNumber,
      'pin': pin,
      'owners': owners,
      'currentOwner': currentOwner,
    };
    if (version != null) m['version'] = version;
    if (governorate != null) m['governorate'] = governorate;
    return m;
  }

  Product copyWith({
    String? id,
    int? version,
    ProductDefinition? productDefinition,
    ProductStatus? status,
    String? serialNumber,
    String? pin,
    List<String>? owners,
    String? currentOwner,
    String? governorate,
  }) =>
      Product(
        id: id ?? this.id,
        version: version ?? this.version,
        productDefinition: productDefinition ?? this.productDefinition,
        status: status ?? this.status,
        serialNumber: serialNumber ?? this.serialNumber,
        pin: pin ?? this.pin,
        owners: owners ?? this.owners,
        currentOwner: currentOwner ?? this.currentOwner,
        governorate: governorate ?? this.governorate,
      );
}
