// HQ network-wide POS-slot oversight (B-029).

/// Network totals across all agents.
class PosNetworkSummary {
  final int totalIssued; // slots HQ pushed into the network
  final int totalUsed; // live POS points
  final int unused; // totalIssued - totalUsed
  final int agents;
  final int mainAgents;
  final int subAgents;

  const PosNetworkSummary({
    this.totalIssued = 0,
    this.totalUsed = 0,
    this.unused = 0,
    this.agents = 0,
    this.mainAgents = 0,
    this.subAgents = 0,
  });

  factory PosNetworkSummary.fromJson(Map<String, dynamic> j) => PosNetworkSummary(
        totalIssued: (j['totalIssued'] as num?)?.toInt() ?? 0,
        totalUsed: (j['totalUsed'] as num?)?.toInt() ?? 0,
        unused: (j['unused'] as num?)?.toInt() ?? 0,
        agents: (j['agents'] as num?)?.toInt() ?? 0,
        mainAgents: (j['mainAgents'] as num?)?.toInt() ?? 0,
        subAgents: (j['subAgents'] as num?)?.toInt() ?? 0,
      );
}

/// One agent's POS-slot line in the HQ network table.
class PosNetworkRow {
  final String entityId;
  final String name;
  final String tier; // AGENT1 | AGENT2
  final String? parentId;
  final String? parentName;
  final int total;
  final int granted;
  final int used;
  final int available;

  const PosNetworkRow({
    required this.entityId,
    required this.name,
    required this.tier,
    this.parentId,
    this.parentName,
    this.total = 0,
    this.granted = 0,
    this.used = 0,
    this.available = 0,
  });

  factory PosNetworkRow.fromJson(Map<String, dynamic> j) => PosNetworkRow(
        entityId: j['entityId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        tier: j['tier'] as String? ?? '',
        parentId: j['parentId'] as String?,
        parentName: j['parentName'] as String?,
        total: (j['total'] as num?)?.toInt() ?? 0,
        granted: (j['granted'] as num?)?.toInt() ?? 0,
        used: (j['used'] as num?)?.toInt() ?? 0,
        available: (j['available'] as num?)?.toInt() ?? 0,
      );
}

/// A page of network rows + whether more pages follow.
class PosNetworkPage {
  final List<PosNetworkRow> items;
  final bool hasMore;
  const PosNetworkPage(this.items, this.hasMore);
}
