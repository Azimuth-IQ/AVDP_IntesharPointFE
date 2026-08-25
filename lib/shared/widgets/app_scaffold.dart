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
import 'package:inteshar/features/chat/application/chat_provider.dart';
import 'package:inteshar/features/notifications/application/notification_provider.dart';
import 'package:inteshar/features/notifications/presentation/alert_banner.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_band.dart';
import 'package:inteshar/shared/widgets/brand_masthead.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/language_switcher_row.dart';
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

/// Wraps [icon] in a Material [Badge] for the destinations that carry an unread
/// count. Applied to bottom-bar, rail, sidebar, and the More sheet.
///
/// B-133: chat was left out, so a reply arrived with no sign of it anywhere in
/// the navigation — the only way to find out was to open التواصل and look.
/// Keyed by route suffix rather than by index because the destination list is
/// filtered per role, so positions differ between tiers.
class UnreadCounts {
  final int notifications;
  final int chat;
  const UnreadCounts({this.notifications = 0, this.chat = 0});

  /// Unread for a destination, keyed by route SUFFIX rather than by index —
  /// the destination list is filtered per role, so positions differ by tier.
  int forRoute(String route) {
    if (route.endsWith('/notifications')) return notifications;
    if (route.endsWith('/chat')) return chat;
    return 0;
  }

  /// Total for the destinations currently hidden behind "More".
  int forRoutes(Iterable<String> routes) =>
      routes.fold<int>(0, (sum, r) => sum + forRoute(r));
}

Widget _wrapBadge(Widget icon, String route, UnreadCounts unread) {
  final count = unread.forRoute(route);
  if (count == 0) return icon;
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

  // UX-97/UX-99: a nav label IS the breadcrumb — there is no breadcrumb widget
  // anywhere in the app, so once the More sheet closes the destination name in
  // the bar is the only thing telling the operator where they are. Six labels
  // disagreed with the title of the page they opened. Where the page title is
  // the better name, the nav follows it, using the same bilingual-literal idiom
  // already used below for Reports/Transfers/POS.
  List<_NavItem> _navFor(AppLocalizations l, EntityType type) {
    final reportsLabel = l.localeName.startsWith('ar') ? 'التقارير' : 'Reports';
    final transfersLabel = l.localeName.startsWith('ar') ? 'التحويل' : 'Transfers';
    // UX-97/UX-99: was 'Messages', which (a) is not what the page calls itself
    // ("Conversations" / المحادثات) and (b) is ALSO the eyebrow of the
    // notifications INBOX — one word naming two unrelated destinations.
    final chatLabel = l.localeName.startsWith('ar') ? 'المحادثات' : 'Conversations';
    // UX-99: HQ's /notifications is a send-only broadcast COMPOSER; every other
    // tier's is a receive-only inbox. Shipping one label for both meant "the
    // place I read my messages" and "the place I write to everyone" were the
    // same word. The icon here is already a megaphone.
    final broadcastLabel = l.localeName.startsWith('ar') ? 'البث' : 'Broadcast';
    // UX-97: matches `batch_add_page`'s own title (batchAddTitle), not "Batch Add".
    final batchAddLabel = l.localeName.startsWith('ar') ? 'إضافة قسائم' : 'Add vouchers';
    // UX-97: matches `voucher_templates_page`'s title (vtTitle).
    final templatesLabel = l.localeName.startsWith('ar') ? 'قوالب القسائم' : 'Voucher Templates';
    // UX-97: matches `hq_users_page`'s title — the page covers supervisors too,
    // which a bare "Users" hides.
    final hqUsersLabel = l.localeName.startsWith('ar') ? 'المستخدمون / المشرفون' : 'Users & supervisors';
    final posLabel = l.localeName.startsWith('ar') ? 'نقاط البيع' : 'POS points';
    // A store hosts no POS points — it IS one. Singular, so the destination
    // does not promise a list of shops it can never have (see StorePosView).
    final storePosLabel = l.localeName.startsWith('ar') ? 'نقطة البيع' : 'My POS';
    final sliderLabel = l.localeName.startsWith('ar') ? 'شريط الصور' : 'Home slider';
    final appDownloadLabel = l.localeName.startsWith('ar') ? 'تحميل التطبيق' : 'Get the app';
    switch (type) {
      case EntityType.INTESHAR:
        // Flat order — frequency-first; first 4 = mobile bottom-bar primaries.
        // B-112: Reports sits in the 4th slot, not Print Ops. A platform admin
        // opens Reports daily; Print Ops is an investigation tool reached when
        // something looks wrong, so it belongs one tap deeper.
        // Oversight is the HQ landing (index 0). Desktop sidebar overlays group
        // headers on top of this flat order (see _kGroupLabels / _buildSidebarEntries).
        //
        // Groups: Oversight · Inventory & Stock · Distribution · Network (agents) ·
        // Points of Sale · Catalog · Administration. Group SECTIONING on desktop is
        // handled by _buildSidebarEntries (contiguous per group), independent of this
        // flat order — so this list stays frequency-first for the mobile bottom bar.
        //
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
            Icons.account_tree_outlined,
            Icons.account_tree,
            l.navHierarchy,
            '/hq/entities',
            required: Capability.VIEW_REPORTS,
            group: 'network',
          ),
          // ── More sheet below ─────────────────────────────────────────────
          _NavItem(
            Icons.assessment_outlined,
            Icons.assessment,
            reportsLabel,
            '/hq/reports',
            required: Capability.VIEW_REPORTS,
            group: 'oversight',
          ),
          _NavItem(
            Icons.fact_check_outlined,
            Icons.fact_check,
            l.navPrintOps,
            '/hq/print-operations',
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
            batchAddLabel,
            '/hq/batch',
            required: Capability.MANAGE_CATALOG,
            group: 'inventory_stock',
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
          // UX-01: HQ had no pricing destination at all — the page was mounted
          // only under /agent1 — while the HQ landing page permanently reports
          // "N agents with unpriced cards". Filed under Catalog, next to the SKUs
          // whose prices it sets.
          _NavItem(
            Icons.sell_outlined,
            Icons.sell,
            l.navPrices,
            '/hq/pricing',
            required: Capability.MANAGE_PRICING,
            group: 'catalog',
          ),
          _NavItem(
            Icons.receipt_long_outlined,
            Icons.receipt_long,
            templatesLabel,
            '/hq/templates',
            required: Capability.MANAGE_CATALOG,
            group: 'catalog',
          ),
          _NavItem(
            Icons.manage_accounts_outlined,
            Icons.manage_accounts,
            hqUsersLabel,
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
            Icons.forum_outlined,
            Icons.forum,
            chatLabel,
            '/hq/chat',
            required: Capability.AGENT_ADMIN,
            group: 'administration',
          ),
          _NavItem(
            Icons.campaign_outlined,
            Icons.campaign,
            broadcastLabel,
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
        // Frequency order: Dashboard, Transfers, Inventory, Children (primaries);
        // Pricing, Reports, Stores, Messages, Notifications (More).
        // Groups: Operations · Network (Notifications ungrouped, always last).
        //
        // B-112: Pricing used to be insert()ed at build time "before the last
        // item", which actually landed it AFTER Messages — position 8 of 9 for a
        // daily task — and left it tagged `operations` while sitting among
        // `network` items, so the desktop sidebar filed it under the wrong header.
        // It is declared here like everything else; the MANAGE_PRICING gate is the
        // same capability filter every other item uses.
        return [
          _NavItem(
            Icons.dashboard_outlined,
            Icons.dashboard,
            l.navDashboard,
            '/agent1/home',
            group: 'operations',
          ),
          // B-056: the balance-transfer page takes the retired Transactions slot.
          _NavItem(
            Icons.swap_horiz_outlined,
            Icons.swap_horiz,
            transfersLabel,
            '/agent1/transfers',
            required: Capability.CREATE_TRANSACTIONS,
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
            // UX-97: was `navChildren` ("Children" / الفروع) while the page it
            // opens — the same EntityTreePage HQ reaches — titles itself
            // `navHierarchy`. One destination, three tiers, one name now.
            l.navHierarchy,
            '/agent1/entities',
            group: 'network',
          ),
          // B-112: Pricing LEADS the overflow. It used to be insert()ed "before the
          // last item", which put it after Messages — position 8 of 9 for a core
          // task. It is periodic rather than daily, so it should not displace an
          // established primary either; first-in-More is the honest slot.
          _NavItem(
            Icons.sell_outlined,
            Icons.sell,
            l.navPrices,
            '/agent1/pricing',
            required: Capability.MANAGE_PRICING,
            group: 'operations',
          ),
          // After the 4 primaries (Dashboard/Transactions/Inventory/Children) so it lands
          // in the More overflow, not on the phone bar.
          _NavItem(
            Icons.assessment_outlined,
            Icons.assessment,
            reportsLabel,
            '/agent1/reports',
            required: Capability.VIEW_REPORTS,
            group: 'network',
          ),
          _NavItem(
            Icons.storefront_outlined,
            Icons.storefront,
            posLabel,
            '/agent1/pos-users',
            required: Capability.MANAGE_POS,
            group: 'network',
          ),
          // Pricing is runtime-inserted at (length-1) so it lands before Notifications.
          _NavItem(
            Icons.forum_outlined,
            Icons.forum,
            chatLabel,
            '/agent1/chat',
            group: 'network',
          ),
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
          // B-056: the balance-transfer page takes the retired Transactions slot.
          _NavItem(
            Icons.swap_horiz_outlined,
            Icons.swap_horiz,
            transfersLabel,
            '/agent2/transfers',
            required: Capability.CREATE_TRANSACTIONS,
            group: 'operations',
          ),
          _NavItem(
            Icons.account_tree_outlined,
            Icons.account_tree,
            // UX-97: see the AGENT1 note — same page, same name.
            l.navHierarchy,
            '/agent2/entities',
            group: 'network',
          ),
          // After the 4 primaries so it lands in the More overflow, not on the phone bar.
          _NavItem(
            Icons.assessment_outlined,
            Icons.assessment,
            reportsLabel,
            '/agent2/reports',
            required: Capability.VIEW_REPORTS,
            group: 'network',
          ),
          _NavItem(
            Icons.storefront_outlined,
            Icons.storefront,
            posLabel,
            '/agent2/pos-users',
            required: Capability.MANAGE_POS,
            group: 'network',
          ),
          _NavItem(
            Icons.forum_outlined,
            Icons.forum,
            chatLabel,
            '/agent2/chat',
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
            storePosLabel,
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

    // B-112: every destination is declarative in _navFor now — Pricing used to be
    // insert()ed here and landed in the wrong slot under the wrong group header.
    final base = _navFor(l, type);

    // Users see only the sections their capabilities allow. B-055: auth.can() is
    // ceiling-aware (server-resolved effective set beats the ADMIN-role bypass),
    // so a section HQ hid for an agent disappears for its whole subtree. Never
    // produce an empty nav.
    final filtered = base.where((it) {
      if (it.required == null) return true;
      if (auth is! AuthAuthenticated) return false;
      return auth.can({it.required!});
    }).toList();
    final items = filtered.isEmpty ? base : filtered;

    final location = GoRouterState.of(context).matchedLocation;
    final activeIndex = _activeIndex(items, location);

    // Unread badge counts — both fail silently (0 on any error), because a badge
    // is an ambient hint and a failed count must never break the navigation it
    // decorates. B-133 adds chat, which had no indicator anywhere.
    final unreadCount = UnreadCounts(
      notifications:
          ref.watch(notificationsUnreadCountProvider).valueOrNull ?? 0,
      chat: ref.watch(chatUnreadCountProvider).valueOrNull ?? 0,
    );

    void go(int i) {
      final target = items[i].route;
      if (target != location) context.go(target);
    }

    // B-060: an unread ALERT surfaces as a banner above the routed body, on every
    // signed-in screen (empty/no-op when there is nothing to alert).
    final bodyWithAlert = Column(
      children: [const AlertBanner(), Expanded(child: child)],
    );

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
        body: bodyWithAlert,
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
        body: bodyWithAlert,
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
        body: bodyWithAlert,
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
  final UnreadCounts unreadCount;
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
          onLongPress: () => context.push('/diagnostics'),
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

    // A badge-bearing destination hidden in the More overflow would be invisible,
    // so bubble the hidden count onto the "More" tab itself. B-133: this now
    // covers chat as well as notifications — it previously counted only
    // notifications, so an unread chat in the overflow showed nothing at all.
    final hiddenUnread = overflow ? unreadCount.forRoutes(extras.map((e) => e.route)) : 0;
    Widget moreIcon() => hiddenUnread > 0
        ? Badge(label: Text('$hiddenUnread'), child: const Icon(Icons.more_horiz))
        : const Icon(Icons.more_horiz);

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
          icon: moreIcon(),
          selectedIcon: moreIcon(),
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
  final UnreadCounts unreadCount;
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
          // overflow destinations or the screen is short. Grouped with the same
          // bilingual section headers as the desktop sidebar (B-074), so a 14-item
          // HQ overflow isn't one flat, undifferentiated scroll.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in _buildSidebarEntries(items))
                    if (entry.isHeader)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
                        child: _GroupHeader(groupKey: entry.groupKey!),
                      )
                    else
                      _MoreRow(
                        item: items[entry.itemIndex!],
                        active: entry.itemIndex == activeIndex,
                        unreadCount: unreadCount,
                        onTap: () => onSelect(entry.itemIndex!),
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
  final UnreadCounts unreadCount;
  final VoidCallback onTap;
  const _MoreRow({
    required this.item,
    required this.active,
    required this.onTap,
    this.unreadCount = const UnreadCounts(),
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
  final UnreadCounts unreadCount;
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
          onLongPress: () => context.push('/diagnostics'),
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
                    // UX-116: a Row lays out a non-flex child with unbounded
                    // width, so a long RTL label ("الوكلاء الرئيسيون") made the
                    // rail as wide as the label and ate the body. Bounded here,
                    // the labels wrap to two centred lines instead.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 116),
                      child: NavigationRail(
                        selectedIndex: activeIndex,
                        onDestinationSelected: onSelect,
                        labelType: NavigationRailLabelType.all,
                        minWidth: 88,
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
                                label: Text(
                                  e.label,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                      ),
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
  final UnreadCounts unreadCount;
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
  final UnreadCounts unreadCount;

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
              onLongPress: () => context.push('/diagnostics'),
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
                  // B-096: language was buried at the bottom of About, below the
                  // printer list — nobody finds it there. With only two locales a
                  // one-tap toggle beats a control: the row names the language you'd
                  // switch TO, in its own script, so it reads as an action.
                  Consumer(
                    builder: (ctx, ref, _) => _NavRow.action(
                      icon: Icons.translate_outlined,
                      label: otherLanguageLabel(ctx),
                      onTap: () => ref.read(localeControllerProvider.notifier).toggle(),
                    ),
                  ),
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
  final UnreadCounts unreadCount;
  final VoidCallback onTap;

  const _NavRow({
    required this.item,
    required this.active,
    required this.onTap,
    this.unreadCount = const UnreadCounts(),
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
       unreadCount = const UnreadCounts();

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
              const LanguageSwitcherRow(),
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
                    tagline: 'Inteshar',
                    onBrandSurface: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l.aboutVersion,
                    style: GoogleFonts.jetBrainsMono(
                      // On-brand surface: track onPrimary so it stays legible
                      // under a dark white-label brand (B-085).
                      color: cs.onPrimary.withValues(alpha: 0.65),
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
              child: LanguageSwitcherRow(),
            ),
          ],
        ),
      ),
    );
  }
}
