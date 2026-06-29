/// Transaction stock pre-flight gate.
///
/// BRD rule (backend quirk): `TransactionProcessor` does NOT filter by
/// `ProductStatus` when picking vouchers to move, so the client MUST verify the
/// source holds enough **AVAILABLE** stock for every requested SKU before
/// submitting — otherwise a transfer could drain non-AVAILABLE (used/damaged)
/// vouchers. These pure functions are the single source of truth for that gate
/// and are exercised directly by tests; the new-transaction page delegates its
/// `_overAllocatedSkus` to [overAllocatedSkus].
library;

/// SKUs whose summed requested quantity exceeds the source's AVAILABLE count.
/// An empty result means every requested SKU can be fulfilled.
List<String> overAllocatedSkus(
    Map<String, int> requestedBySku, Map<String, int> availableBySku) {
  final out = <String>[];
  requestedBySku.forEach((sku, qty) {
    if (qty > (availableBySku[sku] ?? 0)) out.add(sku);
  });
  return out;
}

/// Per-SKU shortfall (`requested - available`) for over-allocated SKUs only.
Map<String, int> shortfallBySku(
    Map<String, int> requestedBySku, Map<String, int> availableBySku) {
  final out = <String, int>{};
  requestedBySku.forEach((sku, qty) {
    final have = availableBySku[sku] ?? 0;
    if (qty > have) out[sku] = qty - have;
  });
  return out;
}

/// True when every requested SKU can be fulfilled from AVAILABLE stock, i.e. the
/// submit may proceed. False blocks the submit.
bool preflightPasses(
        Map<String, int> requestedBySku, Map<String, int> availableBySku) =>
    overAllocatedSkus(requestedBySku, availableBySku).isEmpty;
