/// Client mirror of the backend `PageResponse<T>` envelope used by the BFF
/// admin feeds: `{ items, page, size, hasMore }`. `hasMore` is authoritative
/// (the server over-fetches one row to compute it), so the UI never needs a
/// separate total count to know whether to show "Load more".
class Paged<T> {
  final List<T> items;
  final int page;
  final int size;
  final bool hasMore;

  const Paged({
    this.items = const [],
    this.page = 0,
    this.size = 0,
    this.hasMore = false,
  });

  factory Paged.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) item,
  ) {
    final list = (j['items'] as List<dynamic>?) ?? const [];
    return Paged(
      items: list.map((e) => item(e as Map<String, dynamic>)).toList(),
      page: (j['page'] as num?)?.toInt() ?? 0,
      size: (j['size'] as num?)?.toInt() ?? 0,
      hasMore: j['hasMore'] as bool? ?? false,
    );
  }

  /// Tolerant of either the `{ items, page, size, hasMore }` envelope OR a bare
  /// JSON array (e.g. a non-paginated endpoint, or a backend not yet redeployed
  /// with the page envelope). For the bare-list case `hasMore` is inferred from
  /// whether a full page came back.
  factory Paged.from(
    dynamic d,
    T Function(Map<String, dynamic>) item, {
    int size = 0,
  }) {
    if (d is Map) {
      return Paged.fromJson(Map<String, dynamic>.from(d), item);
    }
    if (d is List) {
      final items =
          d.map((e) => item(e as Map<String, dynamic>)).toList();
      return Paged(
        items: items,
        page: 0,
        size: size,
        hasMore: size > 0 && items.length >= size,
      );
    }
    return Paged(items: const [], page: 0, size: size, hasMore: false);
  }
}
