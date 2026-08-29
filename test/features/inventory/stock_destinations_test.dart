import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/presentation/inventory_page.dart';

/// C-19 / UX-104 — which destinations the "move stock out" dialog offers.
///
/// Reported by the client on 2026-08-29 as "بضاعة بالمخزن بدون تحكم" — stock in
/// the warehouse with nothing you can do to it. HQ's own warehouse showed no
/// action at all, because the gate required the warehouse to belong to someone
/// else. The server never had that restriction, so the cards were reachable by
/// API and stranded in the UI: the only way to get stock to an agent was to name
/// the target at batch-load time.
///
/// The one thing that genuinely must NOT be offered on your own warehouse is
/// "back to the HQ warehouse", because it would send `from == to`, which the
/// backend rejects with a 400 in two places (`InventoryController.transferStock`
/// and `InventoryHelper.transferStock`). That is the invariant here — everything
/// else about the dialog is presentation.
void main() {
  group("someone else's warehouse", () {
    test('offers all three destinations', () {
      expect(
        stockDestinationsFor(isOwnWarehouse: false),
        containsAll(WithdrawDestination.values),
        reason: 'pulling back, handing on, and retiring all apply',
      );
    });

    test('defaults to pulling the stock back to HQ', () {
      expect(defaultStockDestination(isOwnWarehouse: false),
          WithdrawDestination.hq);
    });
  });

  group('your own warehouse', () {
    test('never offers "back to HQ" — it would post from == to', () {
      expect(
        stockDestinationsFor(isOwnWarehouse: true),
        isNot(contains(WithdrawDestination.hq)),
        reason: 'the server answers from == to with a 400, so the control '
            'could only ever produce an error',
      );
    });

    test('still offers transfer and retire — this is the reported bug', () {
      // Before the fix the whole action was withheld here, which is what the
      // client saw as stock they could not touch.
      expect(stockDestinationsFor(isOwnWarehouse: true),
          containsAll([WithdrawDestination.transfer, WithdrawDestination.retire]));
    });

    test('defaults to transfer', () {
      expect(defaultStockDestination(isOwnWarehouse: true),
          WithdrawDestination.transfer);
    });
  });

  test('the dialog never opens on an option it does not display', () {
    // The dialog seeds its radio group from defaultStockDestination and builds
    // its tiles from stockDestinationsFor. If those two ever disagree the group
    // has a groupValue matching no tile, and every option renders unselected.
    for (final own in [true, false]) {
      expect(
        stockDestinationsFor(isOwnWarehouse: own),
        contains(defaultStockDestination(isOwnWarehouse: own)),
        reason: 'isOwnWarehouse: $own',
      );
    }
  });
}
