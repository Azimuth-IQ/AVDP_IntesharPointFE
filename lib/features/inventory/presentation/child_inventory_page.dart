import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/inventory/presentation/inventory_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// A pushed, back-aware page showing one downstream entity's inventory.
///
/// UX-104: this used to hard-code `readOnly: true`, which is why the SAME stock
/// screen granted different powers depending on the door — HQ could withdraw
/// from the `/hq/inventory` picker but not from this drill-in, on the same
/// warehouse. [InventoryPage] decides that from the signed-in tier now, so this
/// page is purely the frame: a back-aware AppBar naming the account. A Main
/// Agent or Sub Agent drilling downstream still browses, because their tier
/// says so — not because this route asked for it.
class ChildInventoryPage extends StatelessWidget {
  final String entityId;
  final String entityName;
  const ChildInventoryPage({super.key, required this.entityId, this.entityName = ''});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          entityName.isNotEmpty ? entityName : l.navInventory,
          // UX-127: was an off-scale 18. `titleLg` (20) is the app-bar step, and
          // AppBar already ellipsizes a long agent name.
          style: IntesharText.titleLg(color: cs.onSurface),
        ),
      ),
      body: SafeArea(
        child: InventoryPage(entityId: entityId),
      ),
    );
  }
}
