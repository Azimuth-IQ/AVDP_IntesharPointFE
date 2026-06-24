import 'package:flutter/widgets.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agents_page.dart';

/// HQ "Main Agents" admin page (`/hq/main-agents`). A distinct page; the directory
/// + onboarding logic is shared with Sub Agents via [AgentsPage].
class MainAgentsPage extends StatelessWidget {
  const MainAgentsPage({super.key});

  @override
  Widget build(BuildContext context) => const AgentsPage(tier: AgentTier.main);
}
