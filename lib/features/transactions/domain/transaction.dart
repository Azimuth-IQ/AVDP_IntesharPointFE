// ignore_for_file: constant_identifier_names
enum TransactionStatus { PENDING, PROCESSING, COMPLETED, FAILED }

class TransactionLine {
  final String id;
  final String sku;
  final String amount;
  final String price;
  final String lineTotal;

  const TransactionLine({
    required this.id,
    required this.sku,
    required this.amount,
    required this.price,
    required this.lineTotal,
  });

  factory TransactionLine.fromJson(Map<String, dynamic> j) => TransactionLine(
        id: j['id'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        amount: j['amount']?.toString() ?? '0',
        price: j['price']?.toString() ?? '0',
        lineTotal: j['lineTotal']?.toString() ?? '0',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'amount': amount,
        'price': price,
        'lineTotal': lineTotal,
      };
}

class AppTransaction {
  final String id;
  final int? version;
  final String date;
  final String time;
  final String sourceId;
  final String destinationId;
  final TransactionStatus status;
  final List<TransactionLine> lines;
  final String processMessage;

  const AppTransaction({
    this.id = '',
    this.version,
    required this.date,
    required this.time,
    required this.sourceId,
    required this.destinationId,
    this.status = TransactionStatus.PENDING,
    this.lines = const [],
    this.processMessage = '',
  });

  factory AppTransaction.fromJson(Map<String, dynamic> j) => AppTransaction(
        id: j['id'] as String? ?? '',
        version: j['version'] as int?,
        date: j['date'] as String? ?? '',
        time: j['time'] as String? ?? '',
        sourceId: j['sourceId'] as String? ?? '',
        destinationId: j['destinationId'] as String? ?? '',
        status: TransactionStatus.values.firstWhere(
          (e) => e.name == (j['status'] as String? ?? 'PENDING'),
          orElse: () => TransactionStatus.PENDING,
        ),
        lines: (j['lines'] as List<dynamic>?)
                ?.map((l) =>
                    TransactionLine.fromJson(l as Map<String, dynamic>))
                .toList() ??
            [],
        processMessage: j['processMessage'] as String? ?? '',
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'date': date,
      'time': time,
      'sourceId': sourceId,
      'destinationId': destinationId,
      'lines': lines.map((l) => l.toJson()).toList(),
    };
    if (id.isNotEmpty) m['id'] = id;
    if (version != null) m['version'] = version;
    return m;
  }

  AppTransaction copyWith({
    String? id,
    int? version,
    String? date,
    String? time,
    String? sourceId,
    String? destinationId,
    TransactionStatus? status,
    List<TransactionLine>? lines,
    String? processMessage,
  }) =>
      AppTransaction(
        id: id ?? this.id,
        version: version ?? this.version,
        date: date ?? this.date,
        time: time ?? this.time,
        sourceId: sourceId ?? this.sourceId,
        destinationId: destinationId ?? this.destinationId,
        status: status ?? this.status,
        lines: lines ?? this.lines,
        processMessage: processMessage ?? this.processMessage,
      );
}
