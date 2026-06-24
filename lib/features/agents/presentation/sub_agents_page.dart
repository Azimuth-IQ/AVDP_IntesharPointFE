import 'package:flutter/widgets.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agents_page.dart';

/// HQ "Sub Agents" admin page (`/hq/sub-agents`). A distinct page; the directory +
/// onboarding logic is shared with Main Agents via [AgentsPage], with the Excel
/// sub-agent differences (parent main agent, single user, no pricing).
class SubAgentsPage extends StatelessWidget {
  const SubAgentsPage({super.key});

  @override
  Widget build(BuildContext context) => const AgentsPage(tier: AgentTier.sub);
}
