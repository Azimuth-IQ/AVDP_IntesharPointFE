import 'package:flutter/material.dart';
import 'package:inteshar/features/inventory/presentation/inventory_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// A pushed, back-aware page showing a child entity's inventory read-only.
/// Used by HQ and Distributor (AGENT2) to browse downstream stock without
/// being able to mutate it.
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
          style: TextStyle(
            fontFamily: 'CodecPro',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: InventoryPage(entityId: entityId, readOnly: true),
      ),
    );
  }
}
