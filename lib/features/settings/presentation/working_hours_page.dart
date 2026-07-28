import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/features/settings/data/settings_repository.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/working_hours_editor.dart';

// ─── Inline localisation strings (no .arb edits) ───────────────────────────

class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) =>
      _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('Administration', 'الإدارة');
  String get title => p('Working Hours', 'ساعات العمل');
  String get totpTitle =>
      p('Two-factor (Google Authenticator)', 'التحقق بخطوتين (Google Authenticator)');
  String get totpBody => p(
      'Choose which account tiers must enter an authenticator code at login. POS points are off by default — a shop counter already has a PIN.',
      'حدّد أي مستويات الحسابات تحتاج إدخال رمز المصادقة عند الدخول. نقاط البيع مُعطّلة افتراضياً — نقطة البيع لديها رمز سري أصلاً.');
  String get totpDefault => p('Using the default', 'القيمة الافتراضية');
  String get subtitle =>
      p('Control login time windows for accounts', 'تحكم في أوقات تسجيل دخول الحسابات');

  // Global card
  String get globalSection => p('Global Lock', 'القفل العام');
  String get globalDesc => p(
        'When enabled, accounts that have a configured window cannot log in outside that window. '
        'Accounts with no window configured are unaffected.',
        'عند التفعيل، لا تستطيع الحسابات ذات النافذة الزمنية تسجيل الدخول خارجها. '
        'الحسابات التي لا تمتلك نافذة لا تتأثر.',
      );
  String get globalToggle =>
      p('Enforce working hours system-wide', 'تطبيق ساعات العمل على كامل النظام');
  String get active => p('Active', 'مُفعَّل');
  String get inactive => p('Inactive', 'معطَّل');

  // Per-entity card
  String get entitySection => p('Per-Account Window', 'نافذة الحساب');
  String get selectEntityHint => p('Select an account', 'اختر الحساب');
  String get noEntitySelected =>
      p('Choose an account above to configure its login window.',
          'اختر حسابًا أعلاه لضبط نافذته الزمنية.');
  String get save => p('Save window', 'حفظ النافذة');
  String get savedMsg => p('Working hours saved.', 'تم حفظ ساعات العمل.');
}

// ─── Page ───────────────────────────────────────────────────────────────────

/// HQ-only screen for configuring the working-hours login gate (BRD FR-03).
///
/// **Section A — Global Lock**: a toggle that enables/disables platform-wide
/// enforcement via [Endpoints.settingsWorkingHours]. When off, every login
/// succeeds regardless of per-account windows (windows are preserved, just
/// not enforced). When on, accounts with a window are gated; accounts without
/// one are unaffected.
///
/// **Section B — Per-Account Window**: pick any entity from the hierarchy,
/// edit its window using the shared [WorkingHoursEditor] widget, then save
/// via [Endpoints.settingsWorkingHoursEntity].
///
/// Route: `/hq/working-hours` (add to router.dart — see wiringNotes).
/// Required capability: [Capability.AGENT_ADMIN].
class WorkingHoursPage extends ConsumerStatefulWidget {
  const WorkingHoursPage({super.key});

  @override
  ConsumerState<WorkingHoursPage> createState() => _WorkingHoursPageState();
}

class _WorkingHoursPageState extends ConsumerState<WorkingHoursPage> {
  // ── Global toggle ─────────────────────────────────────────────────────────
  bool _globalEnabled = false;
  // B-107: per-tier 2FA. null = never set → the backend default applies.
  final Map<EntityType, bool?> _totp = {};
  bool _totpLoading = true;
  EntityType? _totpSaving;
  bool _globalLoading = true;
  bool _globalSaving = false;
  Object? _globalError;

  // ── Entity selection (server-searched picker, B-023) ──────────────────────
  bool _entityResolving = false;

  // ── Per-entity form ───────────────────────────────────────────────────────
  Entity? _selectedEntity;
  /// The working-hours value currently shown in the editor.
  WorkingHours? _pendingWindow;
  bool _windowSaving = false;
  String? _windowError;

  SettingsRepository get _settingsRepo =>
      SettingsRepository(ref.read(apiClientProvider));
  EntityRepository get _entityRepo =>
      EntityRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _loadGlobal();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadGlobal() async {
    setState(() {
      _globalLoading = true;
      _globalError = null;
    });
    try {
      final enabled = await _settingsRepo.getGlobalWorkingHoursEnabled();
      final totp = <EntityType, bool?>{};
      for (final t in _totpTiers) {
        totp[t] = await _settingsRepo.getTotpRequired(t);
      }
      if (!mounted) return;
      setState(() {
        _globalEnabled = enabled;
        _totp
          ..clear()
          ..addAll(totp);
        _totpLoading = false;
        _globalLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _globalError = e;
          _globalLoading = false;
        });
      }
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _toggleGlobal(bool value) async {
    setState(() => _globalSaving = true);
    try {
      await _settingsRepo.setGlobalWorkingHoursEnabled(value);
      if (!mounted) return;
      setState(() {
        _globalEnabled = value;
        _globalSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _globalSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
  }

  /// Pick an account via the server-searched picker (B-023), then fetch the
  /// full entity — the picker rows don't carry `meta.workingHours`.
  Future<void> _pickEntity() async {
    final picked = await showEntitySearchPicker(
      context,
      repository: _entityRepo,
      title: _S.of(context).selectEntityHint,
    );
    if (picked == null || !mounted) return;
    setState(() => _entityResolving = true);
    try {
      final entity = await _entityRepo.read(picked.id);
      if (!mounted) return;
      setState(() {
        _selectedEntity = entity;
        // Seed the editor with the account's current window (or a blank default).
        _pendingWindow = entity.meta.workingHours ?? const WorkingHours();
        _windowError = null;
        _entityResolving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _entityResolving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
  }

  Future<void> _saveWindow() async {
    final entity = _selectedEntity;
    if (entity == null) return;
    setState(() {
      _windowSaving = true;
      _windowError = null;
    });
    final wh = _pendingWindow ?? const WorkingHours();
    try {
      await _settingsRepo.setEntityWorkingHours(entity.id, wh);
      if (!mounted) return;
      setState(() => _windowSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_S.of(context).savedMsg)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _windowSaving = false;
        _windowError = friendlyError(e, context);
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: s.eyebrow,
            title: s.title,
            subtitle: s.subtitle,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadGlobal,
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 32),
                children: [
                  _globalCard(s),
                  const SizedBox(height: 20),
                  _totpCard(s),
                  const SizedBox(height: 20),
                  _entityWindowCard(s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTotp(EntityType tier, bool value) async {
    setState(() => _totpSaving = tier);
    try {
      await _settingsRepo.setTotpRequired(tier, value);
      if (!mounted) return;
      setState(() {
        _totp[tier] = value;
        _totpSaving = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _totpSaving = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
  }

  /// B-107: the tiers HQ can decide 2FA for. STORE last — it is the one the
  /// customer asked to exempt, and the backend already defaults it to off.
  static const _totpTiers = [
    EntityType.INTESHAR,
    EntityType.AGENT1,
    EntityType.AGENT2,
    EntityType.STORE,
  ];

  /// Effective state for [tier] when nothing has been stored — mirrors
  /// SystemSettingHelper.isTotpRequiredFor so the switch never lies about what
  /// the server will actually do.
  bool _totpEffective(EntityType tier) =>
      _totp[tier] ?? (tier != EntityType.STORE);

  Widget _totpCard(_S s) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.totpTitle, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(s.totpBody, style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (_totpLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final t in _totpTiers)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(t.label, style: IntesharType.sans(13.5, color: cs.onSurface)),
              // Say when a tier is on the default rather than an explicit choice.
              subtitle: _totp[t] == null
                  ? Text(s.totpDefault, style: IntesharType.sans(11.5, color: cs.onSurfaceVariant))
                  : null,
              value: _totpEffective(t),
              onChanged: _totpSaving != null ? null : (v) => _toggleTotp(t, v),
            ),
      ]),
    );
  }

  // ── Global toggle card ────────────────────────────────────────────────────

  Widget _globalCard(_S s) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      ruleColor: _globalEnabled ? context.tones.brand : cs.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(s.globalSection),
          Text(
            s.globalDesc,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (_globalLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_globalError != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    friendlyError(_globalError!, context),
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadGlobal,
                  tooltip: s.ar ? 'إعادة المحاولة' : 'Retry',
                ),
              ],
            )
          else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                s.globalToggle,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              value: _globalEnabled,
              onChanged: _globalSaving ? null : _toggleGlobal,
              activeThumbColor: context.tones.brand,
              secondary: _globalSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _globalEnabled
                          ? Icons.schedule
                          : Icons.lock_open_outlined,
                      color: _globalEnabled
                          ? context.tones.brand
                          : cs.onSurfaceVariant,
                    ),
            ),
            const SizedBox(height: 4),
            StampPill(
              label: _globalEnabled ? s.active : s.inactive,
              color: _globalEnabled ? IntesharColors.sage : cs.outline,
              icon: _globalEnabled
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
              filled: false,
            ),
          ],
        ],
      ),
    );
  }

  // ── Per-entity window card ────────────────────────────────────────────────

  Widget _entityWindowCard(_S s) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      ruleColor: context.tones.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(s.entitySection),

          // Entity picker — server-searched (B-023): tap to search instead of a
          // dropdown fed by downloading every entity.
          InkWell(
            onTap: _entityResolving ? null : _pickEntity,
            borderRadius: BorderRadius.circular(IntesharRadii.sm),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: s.selectEntityHint,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                suffixIcon: _entityResolving
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : const Icon(Icons.search, size: 18),
              ),
              child: Text(
                _selectedEntity == null
                    ? s.selectEntityHint
                    : '${_selectedEntity!.meta.name.isNotEmpty ? _selectedEntity!.meta.name : _selectedEntity!.id}  ·  ${_selectedEntity!.type.label}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: _selectedEntity == null
                      ? cs.onSurfaceVariant
                      : null,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Editor — shown only when an entity is chosen ───────────────────
          if (_selectedEntity == null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                s.noEntitySelected,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            WorkingHoursEditor(
              value: _pendingWindow,
              onChanged: (wh) => setState(() => _pendingWindow = wh),
            ),

            if (_windowError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _windowError!,
                  style: TextStyle(color: cs.error, fontSize: 12.5),
                ),
              ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _windowSaving ? null : _saveWindow,
                child: _windowSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(s.save),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
