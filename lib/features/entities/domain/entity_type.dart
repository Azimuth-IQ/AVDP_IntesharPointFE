// ignore_for_file: constant_identifier_names
enum EntityType {
  INTESHAR,
  AGENT1,
  AGENT2,
  STORE,
}

extension EntityTypeX on EntityType {
  String get label {
    switch (this) {
      case EntityType.INTESHAR:
        return 'HQ';
      case EntityType.AGENT1:
        return 'Main Agent';
      case EntityType.AGENT2:
        return 'Sub Agent';
      case EntityType.STORE:
        return 'Store';
    }
  }

  String get homeRoute {
    switch (this) {
      case EntityType.INTESHAR:
        return '/hq/home';
      case EntityType.AGENT1:
        return '/agent1/home';
      case EntityType.AGENT2:
        return '/agent2/home';
      case EntityType.STORE:
        return '/store/home';
    }
  }

  /// The tier's dedicated balance-transfer page, or null when it has none.
  ///
  /// B-111: HQ pushes value by assigning stock (batch add → the agent's
  /// uploaded-value counter), and a Store has no children to send to — so
  /// neither has a transfers page, and the dashboard must not offer the action.
  String? get transfersRoute {
    switch (this) {
      case EntityType.AGENT1:
        return '/agent1/transfers';
      case EntityType.AGENT2:
        return '/agent2/transfers';
      case EntityType.INTESHAR:
      case EntityType.STORE:
        return null;
    }
  }

  /// Whether this tier holds voucher stock of its own. HQ and Main Agents are
  /// inventory-backed; Sub Agents and Stores hold no cards — they draw from their
  /// parent Main Agent's pool at print time (draw-on-print). Drives whether any
  /// inventory/stock UI is shown at all (B-042).
  bool get inventoryBacked =>
      this == EntityType.INTESHAR || this == EntityType.AGENT1;
}

enum UserRole { USER, ADMIN }
