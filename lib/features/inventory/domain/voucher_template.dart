/// Print/redeem template for a voucher SKU. Defined by HQ on the
/// [ProductDefinition]; applied by the Store/POS when printing or showing a
/// voucher. Mirrors the backend `VoucherTemplate` embedded document and
/// round-trips through the existing definition create/update endpoints.
class VoucherTemplate {
  /// Top line(s) on the receipt, e.g. supplier or campaign header.
  final String headerText;

  /// Closing line(s), e.g. hotline or terms.
  final String footerText;

  /// Human redeem hint, e.g. "Dial *133*PIN# to recharge".
  final String redeemInstructions;

  final bool showProductName;
  final bool showSerial;
  final bool showPin;
  final bool showPrice;

  final bool qrEnabled;

  /// What the QR encodes between prefix/suffix: 'PIN' or 'SERIAL'.
  final String qrSource;

  /// Prepended to the QR payload, e.g. '*133*'.
  final String qrPrefix;

  /// Appended to the QR payload, e.g. '#'.
  final String qrSuffix;

  /// Print the main agent's logo (nearest AGENT1 ancestor's logo).
  final bool showAgentLogo;

  /// Print the company logo (e.g. Asiacell), from the SKU's company.
  final bool showCompanyLogo;

  /// Print the voucher expiry date below the code.
  final bool showExpiry;

  const VoucherTemplate({
    this.headerText = '',
    this.footerText = '',
    this.redeemInstructions = '',
    this.showProductName = true,
    this.showSerial = true,
    this.showPin = true,
    this.showPrice = false,
    this.qrEnabled = true,
    this.qrSource = 'PIN',
    this.qrPrefix = '',
    this.qrSuffix = '',
    this.showAgentLogo = true,
    this.showCompanyLogo = true,
    this.showExpiry = true,
  });

  factory VoucherTemplate.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const VoucherTemplate();
    return VoucherTemplate(
      headerText: j['headerText'] as String? ?? '',
      footerText: j['footerText'] as String? ?? '',
      redeemInstructions: j['redeemInstructions'] as String? ?? '',
      showProductName: j['showProductName'] as bool? ?? true,
      showSerial: j['showSerial'] as bool? ?? true,
      showPin: j['showPin'] as bool? ?? true,
      showPrice: j['showPrice'] as bool? ?? false,
      qrEnabled: j['qrEnabled'] as bool? ?? true,
      qrSource: j['qrSource'] as String? ?? 'PIN',
      qrPrefix: j['qrPrefix'] as String? ?? '',
      qrSuffix: j['qrSuffix'] as String? ?? '',
      showAgentLogo: j['showAgentLogo'] as bool? ?? true,
      showCompanyLogo: j['showCompanyLogo'] as bool? ?? true,
      showExpiry: j['showExpiry'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'headerText': headerText,
        'footerText': footerText,
        'redeemInstructions': redeemInstructions,
        'showProductName': showProductName,
        'showSerial': showSerial,
        'showPin': showPin,
        'showPrice': showPrice,
        'qrEnabled': qrEnabled,
        'qrSource': qrSource,
        'qrPrefix': qrPrefix,
        'qrSuffix': qrSuffix,
        'showAgentLogo': showAgentLogo,
        'showCompanyLogo': showCompanyLogo,
        'showExpiry': showExpiry,
      };

  /// Builds the QR payload from a voucher's pin/serial using the configured
  /// source + prefix/suffix. E.g. prefix `*133*`, source PIN, suffix `#`
  /// → `*133*123456789#` so a scan dials the redeem code directly.
  String qrPayload({required String pin, required String serial}) {
    final core = qrSource == 'SERIAL' ? serial : pin;
    return '$qrPrefix$core$qrSuffix';
  }

  VoucherTemplate copyWith({
    String? headerText,
    String? footerText,
    String? redeemInstructions,
    bool? showProductName,
    bool? showSerial,
    bool? showPin,
    bool? showPrice,
    bool? qrEnabled,
    String? qrSource,
    String? qrPrefix,
    String? qrSuffix,
    bool? showAgentLogo,
    bool? showCompanyLogo,
    bool? showExpiry,
  }) =>
      VoucherTemplate(
        headerText: headerText ?? this.headerText,
        footerText: footerText ?? this.footerText,
        redeemInstructions: redeemInstructions ?? this.redeemInstructions,
        showProductName: showProductName ?? this.showProductName,
        showSerial: showSerial ?? this.showSerial,
        showPin: showPin ?? this.showPin,
        showPrice: showPrice ?? this.showPrice,
        qrEnabled: qrEnabled ?? this.qrEnabled,
        qrSource: qrSource ?? this.qrSource,
        qrPrefix: qrPrefix ?? this.qrPrefix,
        qrSuffix: qrSuffix ?? this.qrSuffix,
        showAgentLogo: showAgentLogo ?? this.showAgentLogo,
        showCompanyLogo: showCompanyLogo ?? this.showCompanyLogo,
        showExpiry: showExpiry ?? this.showExpiry,
      );
}
