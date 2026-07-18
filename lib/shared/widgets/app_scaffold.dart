import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/core/printing/printer_registry.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/notifications/application/notification_provider.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_band.dart';
import 'package:inteshar/shared/widgets/brand_masthead.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

/// Material's bottom navigation bar stays legible and tappable up to five
/// destinations on a phone. Roles with more spill the overflow into a sheet.
const int _kMaxBottomTabs = 5;

/// Group key → (Arabic label, English label).
/// Used by [_GroupHeader] to render bilingual section dividers in the desktop
/// sidebar. Keys must match the [_NavItem.group] values assigned in [_navFor].
const Map<String, (String, String)> _kGroupLabels = {
  'oversight': ('الإشراف', 'Oversight'),
  'inventory_stock': ('المخزون', 'Inventory & Stock'),
  'distribution': ('التوزيع', 'Distribution'),
  'network': ('الشبكة', 'Network'),
  'pos': ('منافذ البيع', 'Points of Sale'),
  'catalog': ('الكتالوج', 'Catalog'),
  'administration': ('الإدارة', 'Administration'),
  'operations': ('العمليات', 'Operations'),
};

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  // HQ supervisors are scoped to sections via capabilities; null = always visible.
  final Capability? required;

  /// Desktop-sidebar group key — matches a key in [_kGroupLabels].
  /// Null means the item renders without a group header (agents' Notifications,
  /// Store items, action rows). Ignored by the bottom-bar and NavigationRail.
  final String? group;
  const _NavItem(
    this.icon,
    this.selectedIcon,
    this.label,
    this.route, {
    this.required,
    this.group,
  });
}

/// Whether a nav item is visible to a user with [caps]. Items with no [required]
/// capability are always shown; an empty capability set (the platform admin / legacy
/// users) or the AGENT_ADMIN capability sees everything.
bool _navAllowed(Set<Capability> caps, Capability? required) {
  if (required == null) return true;
  if (caps.isEmpty || caps.contains(Capability.AGENT_ADMIN)) return true;
  return caps.contains(required);
}

/// Wraps [icon] in a Material [Badge] when [route] ends with `/notifications`
/// and [count] > 0. Applied to bottom-bar, rail, sidebar, and the More sheet.
Widget _wrapBadge(Widget icon, String route, int count) {
  if (!route.endsWith('/notifications') || count == 0) return icon;
  return Badge(label: Text('$count'), isLabelVisible: true, child: icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar group header support
// ─────────────────────────────────────────────────────────────────────────────

/// An entry in the desktop sidebar's ListView: either an interactive nav item
/// (carrying its original flat [itemIndex] for correct [activeIndex]/[onSelect]
/// indexing) or a non-interactive group header.
class _SidebarEntry {
  /// Non-null for nav items; null for group headers.
  final int? itemIndex;

  /// Non-null for group headers; null for nav items.
  final String? groupKey;
  const _SidebarEntry.item(int index) : itemIndex = index, groupKey = null;
  const _SidebarEntry.header(String key) : itemIndex = null, groupKey = key;
  bool get isHeader => groupKey != null;
}

/// Builds [sidebarEntries] from [items]: injects one [_SidebarEntry.header]
/// before the first occurrence of each distinct non-null group key, then
/// appends an [_SidebarEntry.item] for every nav item.
List<_SidebarEntry> _buildSidebarEntries(List<_NavItem> items) {
  // Render one clean, contiguous section per group. Group order = first appearance
  // in the flat list; within a group, items keep their flat relative order. This
  // decouples the desktop sidebar's sectioning from the flat order the mobile bottom
  // bar consumes, so groups don't scatter when the flat list interleaves them
  // (e.g. oversight items after network ones). Ungrouped items fall to the end.
  final groupOrder = <String>[];
  final byGroup = <String, List<int>>{};
  final ungrouped = <int>[];
  for (var i = 0; i < items.length; i++) {
    final g = items[i].group;
    if (g == null) {
      ungrouped.add(i);
      continue;
    }
    if (!byGroup.containsKey(g)) {
      groupOrder.add(g);
      byGroup[g] = <int>[];
    }
    byGroup[g]!.add(i);
  }
  final entries = <_SidebarEntry>[];
  for (final g in groupOrder) {
    entries.add(_SidebarEntry.header(g));
    for (final i in byGroup[g]!) {
      entries.add(_SidebarEntry.item(i));
    }
  }
  for (final i in ungrouped) {
    entries.add(_SidebarEntry.item(i));
  }
  return entries;
}

/// Lightweight bilingual section label rendered as a non-interactive separator
/// in the desktop sidebar ListView.
class _GroupHeader extends StatelessWidget {
  final String groupKey;
  const _GroupHeader({required this.groupKey});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final labels = _kGroupLabels[groupKey];
    final label = labels != null ? (isAr ? labels.$1 : labels.$2) : groupKey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'CodecPro',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main shell widget
// ─────────────────────────────────────────────────────────────────────────────

/// Responsive shell used by all signed-in role routes.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  List<_NavItem> _navFor(AppLocalizations l, EntityType type) {
    final reportsLabel = l.localeName.startsWith('ar') ? 'التقارير' : 'Reports';
    final posLabel = l.localeName.startsWith('ar') ? 'نقاط البيع' : 'POS points';
    final sliderLabel = l.localeName.startsWith('ar') ? 'شريط الصور' : 'Home slider';
    final appDownloadLabel = l.localeName.startsWith('ar') ? 'تحميل التطبيق' : 'Get the app';
    switch (type) {
      case EntityType.INTESHAR:
        // Flat order — frequency-first; first 4 = mobile bottom-bar primaries.
        // Oversight is the HQ landing (index 0). Desktop sidebar overlays group
        // headers on top of this flat order (see _kGroupLabels / _buildSidebarEntries).
        //
        // Groups: Oversight · Inventory & Stock · Distribution · Network (agents) ·
        // Points of Sale · Catalog · Administration. Group SECTIONING on desktop is
        // handled by _buildSidebarEntries (contiguous per group), independent of this
        // flat order — so this list stays frequency-first for the mobile bottom bar.
        //
        // Stock reallocation has no ARB key yet — labelled inline (mirrors the
        // inline-localized strings used by the reallocation page itself).
        final reallocLabel = l.localeName.startsWith('ar')
            ? 'إعادة التوزيع'
            : 'Reallocation';
        return [
          _NavItem(
            Icons.monitor_heart_outlined,
            Icons.monitor_heart,
            l.navSystemActivity,
            '/hq/home',
            required: Capability.VIEW_REPORTS,
            group: 'oversight',
          ),
          _NavItem(
            Icons.warehouse_outlined,
            Icons.warehouse,
            l.navInventory,
            '/hq/inventory',
            required: Capability.VIEW_REPORTS,
            group: 'inventory_stock',
          ),
          _NavItem(
            Icons.swap_horiz_outlined,
            Icons.swap_horiz,
            l.navTransactions,
            '/hq/transactions',
            required: Capability.VIEW_REPORTS,
            group: 'distribution',
          ),
          _NavItem(
            Icons.account_tree_outlined,
            Icons.account_tree,
            l.navHierarchy,
            '/hq/entities',
            required: Capability.VIEW_REPORTS,
            group: 'network',
          ),
          // ── More sheet below ─────────────────────────────────────────────
          _NavItem(
            Icons.fact_check_outlined,
            Icons.fact_check,
            l.navPrintOps,
            '/hq/print-operations',
            required: Capability.VIEW_REPORTS,
            group: 'oversight',
          ),
          _NavItem(
            Icons.assessment_outlined,
            Icons.assessment,
            reportsLabel,
            '/hq/reports',
            required: Capability.VIEW_REPORTS,
            group: 'oversight',
          ),
          _NavItem(
            Icons.storefront_outlined,
            Icons.storefront,
            posLabel,
            '/hq/pos-users',
            required: Capability.MANAGE_POS,
            group: 'pos',
          ),
          _NavItem(
            Icons.upload_file_outlined,
            Icons.upload_file,
            l.navBatchAdd,
            '/hq/batch',
            required: Capability.MANAGE_CATALOG,
            group: 'inventory_stock',
          ),
          _NavItem(
            Icons.move_down_outlined,
            Icons.move_down,
            reallocLabel,
            '/hq/points-transfer',
            required: Capability.AGENT_ADMIN,
            group: 'distribution',
          ),
          _NavItem(
            Icons.badge_outlined,
            Icons.badge,
            l.navMainAgents,
            '/hq/main-agents',
            required: Capability.MANAGE_AGENTS,
            group: 'network',
          ),
          _NavItem(
            Icons.store_outlined,
            Icons.store,
            l.navSubAgents,
            '/hq/sub-agents',
            required: Capability.MANAGE_AGENTS,
            group: 'network',
          ),
          _NavItem(
            Icons.point_of_sale_outlined,
            Icons.point_of_sale,
            l.navStores,
            '/hq/stores',
            // Store/POS management is its own section (historically MANAGE_POS) —
            // distinct from agent/entity CRUD (MANAGE_AGENTS). Grouped with POS points
            // under "Points of Sale" so the two shop-side screens sit together.
            required: Capability.MANAGE_POS,
            group: 'pos',
          ),
          _NavItem(
            Icons.business_outlined,
            Icons.business,
            l.navCompanies,
            '/hq/companies',
            required: Capability.MANAGE_COMPANIES,
            group: 'catalog',
          ),
          _NavItem(
            Icons.inventory_2_outlined,
            Icons.inventory_2,
            l.navCatalog,
            '/hq/definitions',
            required: Capability.MANAGE_CATALOG,
            group: 'catalog',
          ),
          _NavItem(
            Icons.receipt_long_outlined,
            Icons.receipt_long,
            l.navTemplates,
            '/hq/templates',
            required: Capability.MANAGE_CATALOG,
            group: 'catalog',
          ),
          _NavItem(
            Icons.manage_accounts_outlined,
            Icons.manage_accounts,
            l.navUsers,
            '/hq/users',
            required: Capability.AGENT_ADMIN,
            group: 'administration',
          ),
          _NavItem(
            Icons.schedule_outlined,
            Icons.schedule,
            l.navWorkingHours,
            '/hq/working-hours',
            required: Capability.AGENT_ADMIN,
            group: 'administration',
          ),
          _NavItem(
            Icons.campaign_outlined,
            Icons.campaign,
            l.navNotifications,
            '/hq/notifications',
            required: Capability.AGENT_ADMIN,
            group: 'administration',
          ),
          _NavItem(
            Icons.view_carousel_outlined,
            Icons.view_carousel,
            sliderLabel,
            '/hq/slider',
            required: Capability.AGENT_ADMIN,
            group: 'administration',
          ),
          _NavItem(
            Icons.qr_code_2_outlined,
            Icons.qr_code_2,
            appDownloadLabel,
            '/hq/app-download',
            required: Capability.AGENT_ADMIN,
            group: 'administration',
          ),
        ];

      case EntityType.AGENT1:
        // Frequency order: Dashboard, Transactions, Inventory, Children (primaries);
        // Stores, [Pricing — runtime-appended before Notifications], Notifications (More).
        // Groups: Operations · Network (Notifications ungrouped, always last).
        return [
          _NavItem(
            Icons.dashboard_outlined,
            Icons.dashboard,
            l.navDashboard,
            '/agent1/home',
            group: 'operations',
          ),
          _NavItem(
            Icons.swap_horiz_outlined,
            Icons.swap_horiz,
            l.navTransactions,
            '/agent1/transactions',
            group: 'operations',
          ),
          _NavItem(
            Icons.warehouse_outlined,
            Icons.warehouse,
            l.navInventory,
            '/agent1/inventory',
            group: 'operations',
          ),
          _NavItem(
            Icons.account_tree_outlined,
            Icons.account_tree,
            l.navChildren,
            '/agent1/entities',
            group: 'network',
          ),
          // After the 4 primaries (Dashboard/Transactions/Inventory/Children) so it lands
          // in the More overflow, not on the phone bar.
          _NavItem(
            Icons.assessment_outlined,
            Icons.assessment,
            reportsLabel,
            '/agent1/reports',
            group: 'network',
          ),
          _NavItem(
            Icons.storefront_outlined,
            Icons.storefront,
            posLabel,
            '/agent1/pos-users',
            group: 'network',
          ),
          _NavItem(
            Icons.point_of_sale_outlined,
            Icons.point_of_sale,
            l.navStores,
            '/agent1/stores',
            group: 'network',
          ),
          // Pricing is runtime-inserted at (length-1) so it lands before Notifications.
          _NavItem(
            Icons.notifications_outlined,
            Icons.notifications,
            l.navNotifications,
            '/agent1/notifications',
          ),
        ];

      case EntityType.AGENT2:
        // Same operational-first rationale as AGENT1 (no Pricing for AGENT2).
        // No Inventory tab: a sub-agent holds no cards of its own — it draws from
        // its parent Main Agent's pool at print time (draw-on-print), so an own-
        // inventory view would always be empty (B-042).
        return [
          _NavItem(
            Icons.dashboard_outlined,
            Icons.dashboard,
            l.navDashboard,
            '/agent2/home',
            group: 'operations',
          ),
          _NavItem(
            Icons.swap_horiz_outlined,
            Icons.swap_horiz,
            l.navTransactions,
            '/agent2/transactions',
            group: 'operations',
          ),
          _NavItem(
            Icons.account_tree_outlined,
            Icons.account_tree,
            l.navChildren,
            '/agent2/entities',
            group: 'network',
          ),
          // After the 4 primaries so it lands in the More overflow, not on the phone bar.
          _NavItem(
            Icons.assessment_outlined,
            Icons.assessment,
            reportsLabel,
            '/agent2/reports',
            group: 'network',
          ),
          _NavItem(
            Icons.storefront_outlined,
            Icons.storefront,
            posLabel,
            '/agent2/pos-users',
            group: 'network',
          ),
          _NavItem(
            Icons.point_of_sale_outlined,
            Icons.point_of_sale,
            l.navStores,
            '/agent2/stores',
            group: 'network',
          ),
          _NavItem(
            Icons.notifications_outlined,
            Icons.notifications,
            l.navNotifications,
            '/agent2/notifications',
          ),
        ];

      case EntityType.STORE:
        // The STORE-ADMIN manages the shop (dashboard / reports / POS points). The POS
        // terminal is a SEPARATE USER-role session (/pos); a /pos/home nav item here would
        // only bounce the store-admin (route prefix mismatch), so it is intentionally omitted.
        // The legacy voucher pages (Inventory / Transactions) are gone: since draw-on-print
        // a store holds no cards, so both were permanently empty.
        return [
          _NavItem(
            Icons.dashboard_outlined,
            Icons.dashboard,
            l.navDashboard,
            '/store/home',
          ),
          _NavItem(
            Icons.assessment_outlined,
            Icons.assessment,
            reportsLabel,
            '/store/reports',
          ),
          _NavItem(
            Icons.storefront_outlined,
            Icons.storefront,
            posLabel,
            '/store/pos-users',
          ),
          _NavItem(
            Icons.notifications_outlined,
            Icons.notifications,
            l.navNotifications,
            '/store/notifications',
          ),
        ];
    }
  }

  int _activeIndex(List<_NavItem> items, String location) {
    int best = 0;
    int bestLen = -1;
    for (var i = 0; i < items.length; i++) {
      final r = items[i].route;
      if (location == r || location.startsWith('$r/')) {
        if (r.length > bestLen) {
          best = i;
          bestLen = r.length;
        }
      }
    }
    return best;
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authStateProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final auth = ref.watch(authStateProvider).valueOrNull;
    final entity = (auth is AuthAuthenticated) ? auth.entity : null;
    final type = entity?.type ?? EntityType.STORE;

    // Capability-gated Pricing item for AGENT1 (behind MANAGE_PRICING).
    // Inserted before the last item (Notifications) so it lands at the correct
    // frequency position: Dashboard, Transactions, Inventory, Children,
    // Stores, Pricing, Notifications.
    final base = [..._navFor(l, type)];
    if (type == EntityType.AGENT1 &&
        auth is AuthAuthenticated &&
        auth.can({Capability.MANAGE_PRICING})) {
      base.insert(
        base.length - 1,
        _NavItem(
          Icons.sell_outlined,
          Icons.sell,
          l.navPrices,
          '/agent1/pricing',
          group: 'operations',
        ),
      );
    }

    // HQ supervisors see only the sections their capabilities allow (empty caps =
    // full access). Never produce an empty nav.
    final caps = (auth is AuthAuthenticated)
        ? auth.capabilities
        : const <Capability>{};
    final filtered = base
        .where((it) => _navAllowed(caps, it.required))
        .toList();
    final items = filtered.isEmpty ? base : filtered;

    final location = GoRouterState.of(context).matchedLocation;
    final activeIndex = _activeIndex(items, location);

    // Unread notification badge count — fails silently (returns 0 on any error).
    final unreadCount =
        ref.watch(notificationsUnreadCountProvider).valueOrNull ?? 0;

    void go(int i) {
      final target = items[i].route;
      if (target != location) context.go(target);
    }

    return switch (context.screenSize) {
      ScreenSize.mobile => _MobileLayout(
        items: items,
        activeIndex: activeIndex,
        onSelect: go,
        title: l.appTitle,
        signOutTooltip: l.signOut,
        onLogout: () => _logout(context, ref),
        entity: entity,
        unreadCount: unreadCount,
        body: child,
      ),
      ScreenSize.tablet => _TabletLayout(
        items: items,
        activeIndex: activeIndex,
        onSelect: go,
        title: l.appTitle,
        signOutTooltip: l.signOut,
        onLogout: () => _logout(context, ref),
        entity: entity,
        unreadCount: unreadCount,
        body: child,
      ),
      ScreenSize.desktop => _DesktopLayout(
        items: items,
        activeIndex: activeIndex,
        onSelect: go,
        title: l.appTitle,
        signOutLabel: l.signOut,
        onLogout: () => _logout(context, ref),
        entity: entity,
        unreadCount: unreadCount,
        body: child,
      ),
    };
  }
}

// Legacy name kept so the existing import path `AppScaffold` continues to work.
typedef AppScaffold = AppShell;

// ─────────────────────────────────────────────────────────────────────────────
// Mobile
// ─────────────────────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final List<_NavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final String title;
  final String signOutTooltip;
  final VoidCallback onLogout;
  final Entity? entity;
  final int unreadCount;
  final Widget body;

  const _MobileLayout({
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.title,
    required this.signOutTooltip,
    required this.onLogout,
    required this.entity,
    required this.unreadCount,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onLongPress: () => context.go('/diagnostics'),
          child: BrandMasthead(
            fallbackTitle: title,
            compact: true,
            showTagline: false,
          ),
        ),
        actions: [
          if (entity != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(child: RoleBadge(type: entity!.type)),
            ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: signOutTooltip,
            onPressed: onLogout,
          ),
        ],
      ),
      drawer: const _AboutDrawer(),
      body: body,
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  /// Builds the bottom navigation. When a role has more destinations than a
  /// phone bar can hold ([_kMaxBottomTabs]), the four most-used stay on the bar
  /// and the rest collapse behind a "More" tab that opens a sheet — rather than
  /// crushing seven labels into a width where none are legible or tappable.
  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    final overflow = items.length > _kMaxBottomTabs;
    final primaryCount = overflow ? _kMaxBottomTabs - 1 : items.length;
    final primary = items.take(primaryCount).toList();
    final extras = overflow
        ? items.skip(primaryCount).toList()
        : const <_NavItem>[];
    final activeInExtras = activeIndex >= primaryCount;

    final destinations = <NavigationDestination>[
      for (final item in primary)
        NavigationDestination(
          icon: _wrapBadge(Icon(item.icon), item.route, unreadCount),
          selectedIcon: _wrapBadge(
            Icon(item.selectedIcon),
            item.route,
            unreadCount,
          ),
          label: item.label,
          tooltip: item.label,
        ),
      if (overflow)
        NavigationDestination(
          icon: const Icon(Icons.more_horiz),
          selectedIcon: const Icon(Icons.more_horiz),
          label: l.navMore,
          tooltip: l.navMore,
        ),
    ];

    final selectedIndex =
        (overflow && activeInExtras ? primaryCount : activeIndex).clamp(
          0,
          destinations.length - 1,
        );

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        boxShadow: const [
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, -6),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          if (overflow && i == primaryCount) {
            _openMoreSheet(context, extras, primaryCount);
          } else {
            onSelect(i);
          }
        },
        destinations: destinations,
      ),
    );
  }

  void _openMoreSheet(
    BuildContext context,
    List<_NavItem> extras,
    int primaryCount,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => _MoreSheet(
        items: extras,
        // Index of the active route within [extras]; negative when a primary
        // tab is active (nothing in the sheet is highlighted then).
        activeIndex: activeIndex - primaryCount,
        unreadCount: unreadCount,
        onSelect: (extraIndex) {
          Navigator.pop(sheetCtx);
          onSelect(primaryCount + extraIndex);
        },
      ),
    );
  }
}

/// Overflow destinations for the mobile bottom bar, presented as a sheet of
/// full-width rows — the same active treatment as the desktop sidebar.
class _MoreSheet extends StatelessWidget {
  final List<_NavItem> items;
  final int activeIndex;
  final int unreadCount;
  final ValueChanged<int> onSelect;
  const _MoreSheet({
    required this.items,
    required this.activeIndex,
    required this.unreadCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text(
              l.navMore,
              style: TextStyle(
                fontFamily: 'CodecPro',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.2,
              ),
            ),
          ),
          // Scrollable so the sheet never overflows when the role has many
          // overflow destinations or the screen is short.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++)
                    _MoreRow(
                      item: items[i],
                      active: i == activeIndex,
                      unreadCount: unreadCount,
                      onTap: () => onSelect(i),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final int unreadCount;
  final VoidCallback onTap;
  const _MoreRow({
    required this.item,
    required this.active,
    required this.onTap,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // onSurface (ink) on a brand tint keeps the active row legible; gold-on-gold
    // fails contrast. Mirrors the sidebar's active _NavRow.
    final fg = active ? cs.onSurface : cs.onSurfaceVariant;
    return Material(
      color: active ? cs.primary.withValues(alpha: 0.16) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              _wrapBadge(
                Icon(
                  active ? item.selectedIcon : item.icon,
                  size: 22,
                  color: fg,
                ),
                item.route,
                unreadCount,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: fg,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              if (active)
                IntesharStar(size: 14, color: cs.onSurface, filled: true),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tablet
// ─────────────────────────────────────────────────────────────────────────────

class _TabletLayout extends StatelessWidget {
  final List<_NavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final String title;
  final String signOutTooltip;
  final VoidCallback onLogout;
  final Entity? entity;
  final int unreadCount;
  final Widget body;

  const _TabletLayout({
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.title,
    required this.signOutTooltip,
    required this.onLogout,
    required this.entity,
    required this.unreadCount,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onLongPress: () => context.go('/diagnostics'),
          child: BrandMasthead(
            fallbackTitle: title,
            compact: true,
          ),
        ),
        actions: [
          if (entity != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Center(child: RoleBadge(type: entity!.type)),
            ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: signOutTooltip,
            onPressed: onLogout,
          ),
        ],
      ),
      drawer: const _AboutDrawer(),
      body: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              boxShadow: const [
                BoxShadow(
                  blurRadius: 20,
                  offset: Offset(2, 0),
                  color: Color(0x0F000000),
                ),
              ],
            ),
            // A rail listing every destination can exceed a short or landscape
            // viewport; let it scroll rather than overflow.
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: activeIndex,
                      onDestinationSelected: onSelect,
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: Colors.transparent,
                      indicatorColor: cs.primary.withValues(alpha: 0.22),
                      indicatorShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(IntesharRadii.md),
                      ),
                      destinations: items
                          .map(
                            (e) => NavigationRailDestination(
                              icon: _wrapBadge(
                                Icon(e.icon),
                                e.route,
                                unreadCount,
                              ),
                              selectedIcon: _wrapBadge(
                                Icon(e.selectedIcon),
                                e.route,
                                unreadCount,
                              ),
                              label: Text(e.label),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop / Web
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final List<_NavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final String title;
  final String signOutLabel;
  final VoidCallback onLogout;
  final Entity? entity;
  final int unreadCount;
  final Widget body;

  const _DesktopLayout({
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.title,
    required this.signOutLabel,
    required this.onLogout,
    required this.entity,
    required this.unreadCount,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _Sidebar(
              items: items,
              activeIndex: activeIndex,
              onSelect: onSelect,
              title: title,
              signOutLabel: signOutLabel,
              onLogout: onLogout,
              entity: entity,
              unreadCount: unreadCount,
            ),
            Expanded(
              child: Container(color: cs.surface, child: body),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final String title;
  final String signOutLabel;
  final VoidCallback onLogout;
  final Entity? entity;
  final int unreadCount;

  const _Sidebar({
    required this.items,
    required this.activeIndex,
    required this.onSelect,
    required this.title,
    required this.signOutLabel,
    required this.onLogout,
    required this.entity,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Sidebar entries: interleave group headers (non-interactive) before the
    // first occurrence of each distinct group key. Item indices remain unchanged
    // so activeIndex / onSelect are unaffected by the header rows.
    final sidebarEntries = _buildSidebarEntries(items);

    return SizedBox(
      width: 280,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          boxShadow: const [
            BoxShadow(
              blurRadius: 22,
              offset: Offset(2, 0),
              color: Color(0x12000000),
            ),
          ],
        ),
        child: Column(
          children: [
            // Brand header — yellow band with star + wordmark
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => context.go('/diagnostics'),
              child: BrandBand(
                // Fill the masthead with the account's brand colour (tracks
                // colorScheme.primary; saffron for HQ / unbranded) — B-046.
                background: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                sparkleSize: 140,
                sparkleAlignment: const Alignment(1.4, 1.2),
                child: BrandMasthead(
                  fallbackTitle: title,
                  onBrandSurface: true,
                ),
              ),
            ),
            // Active entity card
            if (entity != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                child: _EntityChip(entity: entity!),
              )
            else
              const SizedBox(height: 16),
            // Nav list with interleaved group headers (HQ and agent roles).
            // Headers are non-interactive separators; only _NavRow entries carry
            // selectable indices — so activeIndex / onSelect are unaffected.
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 10,
                ),
                itemCount: sidebarEntries.length,
                itemBuilder: (ctx, e) {
                  final entry = sidebarEntries[e];
                  if (entry.isHeader) {
                    return _GroupHeader(groupKey: entry.groupKey!);
                  }
                  final i = entry.itemIndex!;
                  final item = items[i];
                  final active = i == activeIndex;
                  return _NavRow(
                    item: item,
                    active: active,
                    unreadCount: unreadCount,
                    onTap: () => onSelect(i),
                  );
                },
              ),
            ),
            // Footer actions
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
              child: Column(
                children: [
                  _NavRow.action(
                    icon: Icons.info_outline,
                    label: AppLocalizations.of(context)!.aboutTitle,
                    onTap: () => _showAboutSheet(context),
                  ),
                  _NavRow.action(
                    icon: Icons.logout_outlined,
                    label: signOutLabel,
                    onTap: onLogout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityChip extends StatelessWidget {
  final Entity entity;
  const _EntityChip({required this.entity});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.appShellActiveEntity,
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              RoleBadge(type: entity.type),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entity.meta.name.isNotEmpty ? entity.meta.name : entity.id,
            style: TextStyle(
              fontFamily: 'CodecPro',
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            entity.id,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatefulWidget {
  final _NavItem? item;
  final IconData? iconOverride;
  final String? labelOverride;
  final bool active;
  final int unreadCount;
  final VoidCallback onTap;

  const _NavRow({
    required this.item,
    required this.active,
    required this.onTap,
    this.unreadCount = 0,
  }) : iconOverride = null,
       labelOverride = null;

  const _NavRow.action({
    required IconData icon,
    required String label,
    required this.onTap,
  }) : item = null,
       iconOverride = icon,
       labelOverride = label,
       active = false,
       unreadCount = 0;

  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.active;

    final icon = active && widget.item != null
        ? widget.item!.selectedIcon
        : (widget.item?.icon ?? widget.iconOverride!);
    final label = widget.item?.label ?? widget.labelOverride!;

    // onSurface (ink in light, bone in dark) keeps the active label legible on
    // the brand-tint highlight in both themes; cs.primary tracks white-label.
    final fg = (active || _hover) ? cs.onSurface : cs.onSurfaceVariant;
    final bg = active
        ? cs.primary.withValues(alpha: 0.22)
        : (_hover ? cs.surfaceContainerHighest : Colors.transparent);

    final route = widget.item?.route ?? '';
    final iconWidget = _wrapBadge(
      Icon(icon, size: 20, color: fg),
      route,
      widget.unreadCount,
    );

    // Merge the InkWell (tappable) + label Text into ONE labelled button node so the rail is
    // reachable by screen readers AND findable/tappable by the semantics-driven E2E (the tap
    // node otherwise carries no label).
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(IntesharRadii.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(IntesharRadii.md),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // Active: small star indicator instead of the editorial rule.
                      if (active)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: IntesharStar(
                            size: 14,
                            color: cs.onSurface,
                            filled: true,
                          ),
                        )
                      else
                        const SizedBox(width: 24),
                      iconWidget,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'CodecPro',
                            color: fg,
                            fontSize: 13.5,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// About sheet / drawer
// ─────────────────────────────────────────────────────────────────────────────

void _showAboutSheet(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final l = AppLocalizations.of(ctx)!;
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Row(
          children: [
            IntesharStar(size: 28, color: cs.onSurface),
            const SizedBox(width: 12),
            Text(l.aboutTitle),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.aboutVersion,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 16),
              SectionLabel(l.aboutSupportedPrinters),
              ...supportedPrinterModels.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        Icons.print_outlined,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.name,
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        '${m.paperMm} mm',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l.aboutPrinterNote,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const _LanguageSwitcherRow(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonClose),
          ),
        ],
      );
    },
  );
}

class _LanguageSwitcherRow extends ConsumerWidget {
  const _LanguageSwitcherRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final locale = ref.watch(localeControllerProvider);
    return Row(
      children: [
        Icon(Icons.translate_outlined, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l.languageLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelSmall,
            ),
          ),
          segments: [
            ButtonSegment(value: 'ar', label: Text(l.languageArabic)),
            ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
          ],
          selected: {locale.languageCode},
          onSelectionChanged: (sel) {
            final code = sel.first;
            ref.read(localeControllerProvider.notifier).setLocale(Locale(code));
          },
        ),
      ],
    );
  }
}

class _AboutDrawer extends StatelessWidget {
  const _AboutDrawer();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Drawer(
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrandBand(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              sparkleSize: 200,
              sparkleAlignment: const Alignment(1.4, 1.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IntesharLockup(
                    title: l.appTitle,
                    tagline: 'Inteshar Platform',
                    onBrandSurface: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.aboutVersion,
                    style: GoogleFonts.jetBrainsMono(
                      color: IntesharColors.ink.withValues(alpha: 0.65),
                      fontSize: 11,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: SectionLabel(
                l.aboutSupportedPrinters,
                padding: EdgeInsets.zero,
              ),
            ),
            ...supportedPrinterModels.map(
              (m) => ListTile(
                dense: true,
                leading: const Icon(Icons.print_outlined, size: 18),
                title: Text(m.name),
                subtitle: Text('${m.paperMm} mm ESC/POS'),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(l.aboutPrinterNote, style: theme.textTheme.bodySmall),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: _LanguageSwitcherRow(),
            ),
          ],
        ),
      ),
    );
  }
}
