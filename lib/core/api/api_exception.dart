class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic raw;

  const ApiException(this.message, [this.statusCode, this.raw]);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
