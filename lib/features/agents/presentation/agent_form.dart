import 'dart:math';
import 'package:inteshar/core/api/error_mapper.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/settings/data/settings_repository.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/geo/governorate_picker.dart';
import 'package:inteshar/features/agents/domain/governorate_choice.dart';
import 'package:inteshar/features/agents/data/agent_repository.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_strings.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/color_hex_field.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
import 'package:inteshar/shared/widgets/map_location_picker.dart';
import 'package:inteshar/shared/widgets/password_field.dart';
import 'package:inteshar/shared/widgets/working_hours_editor.dart';
import 'package:latlong2/latlong.dart';

String _genId(String prefix) {
  final rand = Random.secure();
  final hex = List.generate(
    6,
    (_) => rand.nextInt(16).toRadixString(16),
  ).join();
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$hex';
}

/// Two-step onboarding wizard shared by Main Agents (AGENT1) and Sub Agents
/// (AGENT2). Tier-specific differences (Excel): a Sub Agent picks a parent Main
/// Agent, may only cover governorates within that parent's coverage, has a single
/// admin user, and cannot set prices. Pushed as a full page; pops `true` on success.
class AgentForm extends ConsumerStatefulWidget {
  final AgentTier tier;
  final Entity? existing; // null = create mode
  const AgentForm({super.key, required this.tier, this.existing});

  @override
  ConsumerState<AgentForm> createState() => _AgentFormState();
}

class _AgentFormState extends ConsumerState<AgentForm> {
  int _step = 0;
  bool _saving = false;

  /// Whole-form problems only — a rejected save, or a rule about the set of
  /// users rather than one of them. Everything that belongs to a single field
  /// is reported on that field, because this banner is pinned to the bottom of
  /// the screen and the offending field can be several screens up.
  String? _error;

  // Per-field errors. Cleared as soon as the operator edits the field, so a
  // corrected field stops shouting before they reach the bottom of the form.
  String? _parentError;
  String? _nameError;
  String? _govError;
  String? _emailError;
  String? _latError;
  String? _lngError;
  String? _lowStockError;
  String? _bulkError;

  // Anchors for scrolling the first bad field into view.
  final _kParent = GlobalKey();
  final _kName = GlobalKey();
  final _kGov = GlobalKey();
  final _kGeo = GlobalKey();
  final _kEmail = GlobalKey();
  final _kLimits = GlobalKey();

  // Step 1 — entity details
  final _name = TextEditingController();
  final _slogan = TextEditingController();
  final _description = TextEditingController();
  final _logo = TextEditingController();

  // UX-03: operational limits. These lived only in the hierarchy tree's edit
  // sheet, so this form — the one reached from the Main/Sub Agent pages — could
  // not see or write them. Blank means "unset": 0 round-trips as inherit/default.
  final _lowStock = TextEditingController();
  final _bulkLimit = TextEditingController();
  bool _bulkLocked = true;
  final _ownerName = TextEditingController();
  List<String> _documentUrls = [];
  final _landmark = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _contactPhone = TextEditingController();
  final _contactEmail = TextEditingController();
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  final _background = TextEditingController();
  Set<String> _governorates = {};
  WorkingHours? _workingHours;

  /// UX-04: whether the PLATFORM-WIDE login-hours gate is switched on.
  ///
  /// The window edited below is per-account, but it is only enforced while
  /// `auth.workinghours.enabled` is true — and that switch lives on a different
  /// screen entirely. Without this, an admin sets closing hours, saves, is told
  /// it saved, and the account keeps letting people in. Null while the setting
  /// is in flight, so a slow fetch never claims "not enforced" before it knows.
  bool? _hoursGloballyOn;

  /// B-055 section ceiling. The 4 agent-facing sections; all-on = unrestricted
  /// (persisted as {AGENT_ADMIN} so "no restriction" round-trips explicitly).
  static const List<Capability> _sectionChoices = [
    Capability.VIEW_REPORTS,
    Capability.MANAGE_PRICING,
    Capability.MANAGE_POS,
    Capability.CREATE_TRANSACTIONS,
  ];
  Set<Capability> _allowedSections = _sectionChoices.toSet();

  // Sub-agent parent (Main Agent) selection
  List<EntitySummaryRow> _parentOptions = [];
  String? _parentId;
  bool _loadingParents = false;
  Set<String>?
  _allowedGovernorates; // limits the governorate choices to the parent's

  // Step 2 — users
  final List<_UserDraft> _users = [];

  AgentTier get tier => widget.tier;
  bool get _isEdit => widget.existing != null;

  /// How many users the entity already had when the form opened. An account
  /// stored above its tier cap (legacy data, or created before the cap) must
  /// still be editable — the ceiling only stops it growing further.
  int _loadedUserCount = 0;
  int get _userCeiling =>
      tier.maxUsers > _loadedUserCount ? tier.maxUsers : _loadedUserCount;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.meta.name;
      _slogan.text = e.meta.slogan;
      _description.text = e.meta.description;
      _logo.text = e.meta.logoUrl;
      if (e.meta.lowStockThreshold > 0) {
        _lowStock.text = e.meta.lowStockThreshold.toString();
      }
      if (e.meta.maxBulkPrint > 0) {
        _bulkLimit.text = e.meta.maxBulkPrint.toString();
      }
      _bulkLocked = e.meta.bulkLimitLocked;
      _primary.text = e.meta.primaryColor;
      _secondary.text = e.meta.secondaryColor;
      _background.text = e.meta.backgroundUrl;
      _governorates = e.meta.governorates.toSet();
      _workingHours = e.meta.workingHours;
      final ceiling = e.allowedCapabilities;
      if (ceiling != null && !ceiling.contains(Capability.AGENT_ADMIN)) {
        _allowedSections =
            _sectionChoices.where(ceiling.contains).toSet();
      }
      _parentId = e.parent.isEmpty ? null : e.parent;
      final p = e.profile;
      if (p != null) {
        _ownerName.text = p.ownerName;
        _documentUrls = List.of(p.documentUrls);
        _landmark.text = p.nearestLandmark;
        _lat.text = p.latitude?.toString() ?? '';
        _lng.text = p.longitude?.toString() ?? '';
        _contactPhone.text = p.contactPhone;
        _contactEmail.text = p.contactEmail;
      }
      // UX-156: liveUsers ONLY. The form rebuilds the users array for a full
      // entity PUT, so an archived user loaded in here would be sent back and
      // resurrected. The server re-attaches the ones it does not see.
      for (final u in e.liveUsers) {
        _users.add(_UserDraft.fromUser(u));
      }
    }
    // Whatever is stored is kept. This used to silently drop everything past
    // the first user on a Sub Agent, so opening the form to fix a slogan and
    // pressing Save deleted a real login — and now that the hierarchy's Edit
    // routes here too, that would have become the ordinary way to lose one.
    // The tier cap still applies to ADDING (see [_addUser] and the submit
    // check), which is where a limit belongs.
    _loadedUserCount = _users.length;
    if (_users.isEmpty) {
      _users.add(_UserDraft.blank(AgentUserPreset.admin));
    }
    if (tier.requiresParentPicker) {
      _loadParents();
    }
    _loadHoursGate();
  }

  /// UX-04. Best-effort: if the setting cannot be read we leave [_hoursGloballyOn]
  /// null and say nothing, rather than warning that hours are unenforced when we
  /// do not actually know.
  Future<void> _loadHoursGate() async {
    try {
      final on = await SettingsRepository(ref.read(apiClientProvider))
          .getGlobalWorkingHoursEnabled();
      if (mounted) setState(() => _hoursGloballyOn = on);
    } catch (_) {
      // Leave null — no claim either way.
    }
  }

  /// Pick the entity's location on a map (B-037) and fill the lat/lng fields.
  Future<void> _pickOnMap() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    final initial = (lat != null && lng != null) ? LatLng(lat, lng) : null;
    final picked = await pickLocationOnMap(context, initial: initial);
    if (picked == null) return;
    setState(() {
      _lat.text = picked.latitude.toStringAsFixed(6);
      _lng.text = picked.longitude.toStringAsFixed(6);
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _slogan,
      _description,
      _logo,
      _lowStock,
      _bulkLimit,
      _ownerName,
      _landmark,
      _lat,
      _lng,
      _contactPhone,
      _contactEmail,
      _primary,
      _secondary,
      _background,
    ]) {
      c.dispose();
    }
    for (final u in _users) {
      u.dispose();
    }
    super.dispose();
  }

  Future<void> _loadParents() async {
    setState(() => _loadingParents = true);
    try {
      final repo = AgentRepository(ref.read(apiClientProvider));
      final parents = await repo.listAll('AGENT1');
      if (!mounted) return;
      setState(() {
        _parentOptions = parents;
        _loadingParents = false;
        if (_parentId != null) _applyParentCoverage();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingParents = false);
    }
  }

  void _applyParentCoverage() {
    EntitySummaryRow? row;
    for (final p in _parentOptions) {
      if (p.id == _parentId) {
        row = p;
        break;
      }
    }
    final allowed = row?.governorates.toSet();
    _allowedGovernorates = allowed;
    if (allowed != null && allowed.isNotEmpty) {
      _governorates = _governorates.where(allowed.contains).toSet();
    }
  }

  /// Effective capabilities for a preset on this tier — pricing is stripped on tiers
  /// that can't price (sub agents). The backend re-applies this invariant.
  Set<Capability> _capsFor(AgentUserPreset preset) {
    if (tier.allowPricing) return preset.capabilities;
    return {...preset.capabilities}..remove(Capability.MANAGE_PRICING);
  }

  /// What this user will actually be saved with.
  ///
  /// A capability set the four presets cannot describe survives an edit intact —
  /// see [_UserDraft.loadedCapabilities] — unless the operator deliberately picks
  /// a preset for that card. The tier's no-pricing rule still applies either way.
  Set<Capability> _capsForDraft(_UserDraft d) {
    final loaded = d.loadedCapabilities;
    if (loaded == null || d.presetChosen) return _capsFor(d.preset);
    if (tier.allowPricing) return loaded;
    return {...loaded}..remove(Capability.MANAGE_PRICING);
  }

  void _addUser() {
    if (_users.length >= _userCeiling) return;
    setState(() => _users.add(_UserDraft.blank(AgentUserPreset.monitoring)));
  }

  String _t(String ar, String en) =>
      Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

  /// Brings [key]'s field into view on the next frame — after a step switch the
  /// widget does not exist yet, so this cannot run synchronously.
  void _scrollTo(GlobalKey? key) {
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.15,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// Checks every step-1 rule at once and reports each failure ON its field.
  ///
  /// It used to stop at the first failure and put the message in the bottom
  /// banner, so a form this long asked the operator to find the field the
  /// sentence was about. Now the whole step is checked in one pass, the first
  /// offender is scrolled to, and fixing one problem does not hide the next.
  bool _validateStep1(AgentStrings s, {bool scroll = true}) {
    final parentErr =
        tier.requiresParentPicker && (_parentId == null || _parentId!.isEmpty)
            ? s.errParentRequired
            : null;
    final nameErr = _name.text.trim().isEmpty ? s.errNameRequired : null;
    final govErr = _governorates.isEmpty ? s.errGovRequired : null;

    // Contact email (optional) — if present it must look like an email.
    final email = _contactEmail.text.trim();
    final emailErr = email.isNotEmpty &&
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
        ? s.errEmailInvalid
        : null;

    // Geo (optional) — if present, must be numeric and in range.
    String? rangeError(String raw, double min, double max) {
      if (raw.isEmpty) return null;
      final v = double.tryParse(raw);
      return (v == null || v < min || v > max) ? s.errGeoInvalid : null;
    }

    final latErr = rangeError(_lat.text.trim(), -90, 90);
    final lngErr = rangeError(_lng.text.trim(), -180, 180);

    // Operational limits (optional) — blank means unset. A non-numeric or
    // negative value would silently persist as 0 and read as "inherit", which is
    // the opposite of what the operator typed.
    String? countError(String raw, {int min = 0}) {
      if (raw.isEmpty) return null;
      final v = int.tryParse(raw);
      return (v == null || v < min) ? s.errNumberInvalid : null;
    }

    final lowStockErr = countError(_lowStock.text.trim());
    // 0 cards per sale is not a limit, it is a shop that cannot sell.
    final bulkErr = countError(_bulkLimit.text.trim(), min: 1);

    setState(() {
      _parentError = parentErr;
      _nameError = nameErr;
      _govError = govErr;
      _emailError = emailErr;
      _latError = latErr;
      _lngError = lngErr;
      _lowStockError = lowStockErr;
      _bulkError = bulkErr;
    });

    final firstBad = _firstBadDetailsKey();
    if (firstBad != null) {
      if (scroll) _scrollTo(firstBad);
      return false;
    }
    return true;
  }

  /// The anchor of the topmost step-1 field currently in error, or null when
  /// the step is clean. Read after [_validateStep1] has set the flags.
  ///
  /// In the order the fields appear on screen, so "first" means the topmost.
  GlobalKey? _firstBadDetailsKey() => _parentError != null
      ? _kParent
      : _nameError != null
          ? _kName
          : _govError != null
              ? _kGov
              : (_latError != null || _lngError != null)
                  ? _kGeo
                  : _emailError != null
                      ? _kEmail
                      : (_lowStockError != null || _bulkError != null)
                          ? _kLimits
                          : null;

  Future<void> _submit() async {
    final s = AgentStrings.of(context, tier);
    if (!_validateStep1(s, scroll: false)) {
      // Being thrown back a step is disorienting on its own; say why, then land
      // the operator ON the field rather than at the top of a 14-field form.
      setState(() {
        _step = 0;
        _error = _t(
          'راجع الحقول المحددة في خطوة البيانات.',
          'Check the highlighted fields on the Details step.',
        );
      });
      _scrollTo(_firstBadDetailsKey());
      return;
    }
    setState(() => _error = null);
    if (_users.isEmpty) {
      setState(() => _error = s.errUsersRequired);
      return;
    }
    if (_users.length > _userCeiling) {
      setState(() => _error = s.errMaxUsers);
      return;
    }

    // Check every user in one pass so the second bad card is not a surprise
    // after fixing the first.
    var userFieldsOk = true;
    for (final d in _users) {
      final phoneErr = d.phone.text.trim().isEmpty ? s.errUserPhone : null;
      // An existing user (already has an id) may keep its current password by
      // leaving this blank: EntityUser.toJson omits a blank password and the
      // backend restores the stored hash on update. Only a NEW user must set one.
      final passErr = (d.password.text.trim().isEmpty && d.id.isEmpty)
          ? s.errUserPassword
          : null;
      d.phoneError = phoneErr;
      d.passwordError = passErr;
      if (phoneErr != null || passErr != null) userFieldsOk = false;
    }
    if (!userFieldsOk) {
      setState(() {});
      _scrollTo(_users
          .firstWhere((d) => d.phoneError != null || d.passwordError != null)
          .anchor);
      return;
    }

    final users = <EntityUser>[];
    for (final d in _users) {
      final phone = d.phone.text.trim();
      final typed = d.password.text.trim();
      users.add(
        EntityUser(
          id: d.id.isNotEmpty ? d.id : _genId('u'),
          phone: phone,
          password: typed,
          role: d.preset.role,
          capabilities: _capsForDraft(d),
        ),
      );
    }
    final adminCount = users.where((u) => u.role == UserRole.ADMIN).length;
    if (adminCount != 1) {
      setState(() => _error = s.errOneAdmin);
      return;
    }

    // Resolve parent: HQ for a Main Agent, the chosen Main Agent for a Sub Agent.
    String parentId;
    if (tier.requiresParentPicker) {
      parentId = _parentId ?? '';
    } else {
      final auth = ref.read(authStateProvider).valueOrNull;
      parentId = auth is AuthAuthenticated ? auth.entity.id : '';
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = AgentRepository(ref.read(apiClientProvider));
    final existing = widget.existing;

    final meta = (existing?.meta ?? const EntityMeta()).copyWith(
      name: _name.text.trim(),
      slogan: _slogan.text.trim(),
      description: _description.text.trim(),
      logoUrl: _logo.text.trim(),
      backgroundUrl: _background.text.trim(),
      primaryColor: _primary.text.trim(),
      secondaryColor: _secondary.text.trim(),
      governorates: _governorates.toList(),
      workingHours: _workingHours,
      // Blank → 0, which the server reads as "unset": the default threshold and
      // an inherited bulk limit. Same encoding the tree's edit sheet used.
      lowStockThreshold: int.tryParse(_lowStock.text.trim()) ?? 0,
      maxBulkPrint: int.tryParse(_bulkLimit.text.trim()) ?? 0,
      bulkLimitLocked: _bulkLocked,
    );
    final profile = EntityProfile(
      ownerName: _ownerName.text.trim(),
      documentUrls: List.of(_documentUrls),
      latitude: double.tryParse(_lat.text.trim()),
      longitude: double.tryParse(_lng.text.trim()),
      nearestLandmark: _landmark.text.trim(),
      contactPhone: _contactPhone.text.trim(),
      contactEmail: _contactEmail.text.trim(),
    );

    // All sections on → {AGENT_ADMIN} = unrestricted (never null, so an edit
    // can CLEAR a previous restriction); any subset → that exact ceiling.
    final ceiling = _allowedSections.length == _sectionChoices.length
        ? {Capability.AGENT_ADMIN}
        : Set<Capability>.of(_allowedSections);

    try {
      if (existing != null) {
        await repo.update(
          existing.copyWith(
            meta: meta,
            profile: profile,
            parent: parentId,
            users: users,
            allowedCapabilities: ceiling,
          ),
        );
      } else {
        await repo.create(
          Entity(
            id: _genId(tier == AgentTier.sub ? 'subagent' : 'agent'),
            meta: meta,
            profile: profile,
            parent: parentId,
            type: tier.entityType,
            users: users,
            allowedCapabilities: ceiling,
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_isEdit ? s.saved : s.created)));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AgentStrings.of(context, tier);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? s.editTitle : s.createTitle)),
      body: Column(
        children: [
          _StepHeader(step: _step, s: s),
          const Hairline(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _step == 0 ? _buildDetails(s) : _buildUsers(s),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: InkCard(
                ruleColor: cs.error,
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: IntesharType.sans(13, color: cs.onSurface),
                ),
              ),
            ),
          const Hairline(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                if (_step == 1)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => setState(() => _step = 0),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text(s.back),
                  ),
                const Spacer(),
                if (_step == 0)
                  FilledButton.icon(
                    onPressed: () {
                      if (_validateStep1(s)) {
                        setState(() {
                          _step = 1;
                          _error = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(s.next),
                  )
                else
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_isEdit ? s.save : s.create),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(AgentStrings s) {
    final cs = Theme.of(context).colorScheme;
    // Only HQ may hand an agent the right to edit its own bulk limit; everyone
    // else sees the value but not the delegation switch (server-enforced too).
    final viewer = ref.read(authStateProvider).valueOrNull;
    final viewerIsHq =
        viewer is AuthAuthenticated && viewer.entity.type == EntityType.INTESHAR;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tier.requiresParentPicker) ...[
          SectionLabel(s.sectionParent),
          const SizedBox(height: 4),
          Text(
            s.parentHint,
            style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (_loadingParents)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            )
          else if (_parentOptions.isEmpty)
            Text(s.noMainAgents, style: IntesharType.sans(13, color: cs.error))
          else
            DropdownButtonFormField<String>(
              key: _kParent,
              initialValue: _parentId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: s.fieldParent,
                errorText: _parentError,
              ),
              items: _parentOptions
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.label)),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _parentId = v;
                _parentError = null;
                _applyParentCoverage();
              }),
            ),
          const SizedBox(height: 22),
        ],
        // Identity first — who the agent is, before any advanced access config (B-073).
        SectionLabel(s.sectionIdentity),
        const SizedBox(height: 8),
        TextField(
          key: _kName,
          controller: _name,
          decoration: InputDecoration(
            labelText: s.fieldName,
            errorText: _nameError,
          ),
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
        ),
        const SizedBox(height: 12),
        // UX-03: slogan + description were only reachable from the hierarchy
        // tree's own edit sheet. They are identity, so they sit with the name.
        TextField(
          controller: _slogan,
          decoration: InputDecoration(labelText: s.fieldSlogan),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 3,
          decoration: InputDecoration(labelText: s.fieldDescription),
        ),
        const SizedBox(height: 12),
        ImageUploadField(
          value: _logo.text.isEmpty ? null : _logo.text,
          kind: 'agent-branding',
          label: s.fieldLogo,
          onChanged: (u) => setState(() => _logo.text = u),
        ),
        const SizedBox(height: 22),
        // B-055 + B-073: which sections this agent — and its ENTIRE subtree — may
        // see. Server-enforced; the nav mirrors it. All-on by default, so it lives
        // in a collapsed "Advanced access" expander instead of a wall of chips up top.
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: SectionLabel(Localizations.localeOf(context).languageCode == 'ar'
                ? 'الوصول المتقدم (الأقسام المتاحة)'
                : 'Advanced access (visible sections)'),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  Localizations.localeOf(context).languageCode == 'ar'
                      ? 'الأقسام المخفية تختفي عن الوكيل وكل حساباته الفرعية ونقاط بيعه.'
                      : 'Hidden sections disappear for this agent and its whole subtree (sub-agents, POS).',
                  style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _sectionChoices)
                    if (c != Capability.MANAGE_PRICING || tier == AgentTier.main)
                      FilterChip(
                        label: Text(c.label(Localizations.localeOf(context).languageCode)),
                        selected: _allowedSections.contains(c),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _allowedSections.add(c);
                          } else {
                            _allowedSections.remove(c);
                          }
                        }),
                      ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionLabel(s.sectionGovernorates),
        const SizedBox(height: 4),
        Text(
          s.governoratesHint,
          style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        GovernorateMultiSelect(
          key: _kGov,
          selected: _governorates,
          allowedCodes: _allowedGovernorates,
          // B-127: a SUB agent covers exactly one governorate, so picking a second
          // REPLACES the first. A Main Agent may span several and is untouched.
          onChanged: (v) => setState(() {
            _governorates = resolveGovernorateChoice(
              current: _governorates,
              next: v,
              singleChoice: tier == AgentTier.sub,
            );
            if (_governorates.isNotEmpty) _govError = null;
          }),
        ),
        // The picker is a chip grid with no InputDecoration to hang an
        // errorText on, so the message sits directly under it instead.
        if (_govError != null) ...[
          const SizedBox(height: 6),
          Text(_govError!, style: IntesharType.sans(12, color: cs.error)),
        ],
        const SizedBox(height: 22),
        SectionLabel(
          Localizations.localeOf(context).languageCode == 'ar'
              ? 'ساعات الدخول'
              : 'Login hours',
        ),
        const SizedBox(height: 8),
        // UX-04: the window below is enforced only while the PLATFORM-WIDE gate
        // is on, and that switch is on another screen. Saying nothing made this
        // silently no-op configuration: visibly saved, visibly ignored, with the
        // account still letting people in at midnight. Shown only when we know
        // the gate is off — an unknown state claims nothing.
        if (_hoursGloballyOn == false) ...[
          InkCard(
            bordered: true,
            ruleColor: context.status.warn,
            padding: const EdgeInsets.all(IntesharSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outlined,
                  size: 18, color: context.status.warn),
              const SizedBox(width: IntesharSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'ساعات الدخول غير مفعّلة حالياً على مستوى المنصة، لذلك '
                              'سيُحفظ هذا التوقيت ولن يُطبَّق.'
                          : 'Login hours are switched off platform-wide right now, '
                              'so this window will be saved but not enforced.',
                      style: IntesharText.body(color: cs.onSurface),
                    ),
                    const SizedBox(height: IntesharSpacing.sm),
                    // The fix is one screen away; make it one tap away too.
                    InkWell(
                      onTap: () => context.push('/hq/working-hours'),
                      child: Text(
                        Localizations.localeOf(context).languageCode == 'ar'
                            ? 'فتح إعدادات ساعات الدخول'
                            : 'Open login-hours settings',
                        style: IntesharText.body(
                          color: context.tones.brandInk,
                          w: IntesharWeight.semibold,
                        ).copyWith(decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: IntesharSpacing.md),
        ],
        WorkingHoursEditor(
          value: _workingHours,
          onChanged: (v) => setState(() => _workingHours = v),
        ),
        const SizedBox(height: 22),

        // ── Operational limits (UX-03) ───────────────────────────────────────
        // Folded in from the hierarchy tree's edit sheet, which was the only
        // place these could be set. Two forms edited the same agent with
        // disjoint fields and neither mentioned the other, so whichever one an
        // admin opened, half the settings were invisible and unguessable.
        SectionLabel(s.sectionLimits, key: _kLimits),
        const SizedBox(height: 4),
        Text(s.limitsHint, style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        TextField(
          controller: _lowStock,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: s.fieldLowStock,
            hintText: EntityMeta.defaultLowStockThreshold.toString(),
            helperText: s.lowStockHint(EntityMeta.defaultLowStockThreshold),
            helperMaxLines: 2,
            errorText: _lowStockError,
          ),
          onChanged: (_) {
            if (_lowStockError != null) setState(() => _lowStockError = null);
          },
        ),
        const SizedBox(height: 12),
        // B-086: the server resolves the EFFECTIVE limit as the minimum over the
        // chain, so a value here can only ever tighten what an ancestor allows.
        TextField(
          controller: _bulkLimit,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: s.fieldBulkLimit,
            hintText: '10',
            helperText: s.bulkLimitHint,
            helperMaxLines: 2,
            errorText: _bulkError,
          ),
          onChanged: (_) {
            if (_bulkError != null) setState(() => _bulkError = null);
          },
        ),
        // Only HQ may delegate or revoke limit management (server-enforced too).
        if (viewerIsHq)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: !_bulkLocked,
            onChanged: (v) => setState(() => _bulkLocked = !v),
            title: Text(s.bulkUnlockLabel,
                style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w600)),
            subtitle: Text(s.bulkUnlockHint,
                style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
          ),
        const SizedBox(height: 22),
        SectionLabel(s.sectionOwner),
        const SizedBox(height: 8),
        TextField(
          controller: _ownerName,
          decoration: InputDecoration(labelText: s.fieldOwnerName),
        ),
        const SizedBox(height: 12),
        MultiImageUploadField(
          values: _documentUrls,
          label: s.fieldDocuments,
          kind: 'kyc-doc',
          onChanged: (urls) => setState(() => _documentUrls = urls),
        ),
        const SizedBox(height: 4),
        Text(
          s.documentsHint,
          style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _landmark,
          decoration: InputDecoration(labelText: s.fieldLandmark),
        ),
        const SizedBox(height: 12),
        Row(
          key: _kGeo,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: s.fieldLat,
                  errorText: _latError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) {
                  if (_latError != null) setState(() => _latError = null);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: s.fieldLng,
                  errorText: _lngError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) {
                  if (_lngError != null) setState(() => _lngError = null);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _pickOnMap,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(s.pickOnMap),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _contactPhone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: InputDecoration(labelText: s.fieldPhone),
        ),
        const SizedBox(height: 12),
        TextField(
          key: _kEmail,
          controller: _contactEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: s.fieldEmail,
            errorText: _emailError,
          ),
          onChanged: (_) {
            if (_emailError != null) setState(() => _emailError = null);
          },
        ),
        if (tier == AgentTier.main) ...[
          const SizedBox(height: 22),
          SectionLabel(s.sectionBranding),
          const SizedBox(height: 4),
          Text(s.brandingHint, style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ColorHexField(
                  controller: _primary,
                  label: s.fieldPrimary,
                  hint: '#F5B100',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ColorHexField(
                  controller: _secondary,
                  label: s.fieldSecondary,
                  hint: '#2C3A55',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ImageUploadField(
            value: _background.text.isEmpty ? null : _background.text,
            kind: 'agent-branding',
            label: s.fieldBackground,
            onChanged: (u) => setState(() => _background.text = u),
          ),
        ],
      ],
    );
  }

  Widget _buildUsers(AgentStrings s) {
    final cs = Theme.of(context).colorScheme;
    final showPreset = tier.maxUsers > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.usersSubtitle,
          style: IntesharType.sans(13, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        ..._users.asMap().entries.map(
          (e) => Padding(
            key: e.value.anchor,
            padding: const EdgeInsets.only(bottom: 12),
            child: _UserCard(
              index: e.key,
              draft: e.value,
              s: s,
              showPreset: showPreset,
              effectiveCaps: _capsForDraft(e.value),
              onChanged: () => setState(() {}),
              onRemove: (_users.length > 1)
                  ? () => setState(() => _users.removeAt(e.key))
                  : null,
            ),
          ),
        ),
        if (_users.length < _userCeiling)
          OutlinedButton.icon(
            onPressed: _addUser,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: Text(s.addUser),
          ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;
  final AgentStrings s;
  const _StepHeader({required this.step, required this.s});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        children: [
          _StepPill(
            active: step == 0,
            done: step > 0,
            index: 1,
            label: s.stepDetails,
          ),
          Expanded(
            child: Container(
              height: 2,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          _StepPill(
            active: step == 1,
            done: false,
            index: 2,
            label: s.stepUsers,
          ),
        ],
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  final bool active;
  final bool done;
  final int index;
  final String label;
  const _StepPill({
    required this.active,
    required this.done,
    required this.index,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = active || done;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? context.tones.brand : cs.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: done
              ? Icon(Icons.check, size: 15, color: context.tones.onBrand)
              : Text(
                  '$index',
                  style: IntesharType.sans(
                    12,
                    w: FontWeight.w800,
                    color: on ? context.tones.onBrand : cs.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: IntesharType.sans(
            13,
            w: FontWeight.w700,
            color: on ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final int index;
  final _UserDraft draft;
  final AgentStrings s;
  final bool showPreset;
  final Set<Capability> effectiveCaps;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  const _UserCard({
    required this.index,
    required this.draft,
    required this.s,
    required this.showPreset,
    required this.effectiveCaps,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = s.ar ? 'ar' : 'en';
    return InkCard(
      padding: const EdgeInsets.all(14),
      ruleColor: draft.preset == AgentUserPreset.admin
          ? context.tones.brand
          : cs.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                showPreset ? s.userN(index + 1) : s.adminUserLabel,
                style: IntesharType.sans(
                  13,
                  w: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                // UX-119: no `visualDensity: compact`. It shrank the padded
                // 48dp target to 40dp on a destructive control, and there is
                // room to spare in this header row.
                IconButton(
                  tooltip: s.removeUser,
                  icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            decoration: InputDecoration(
              labelText: s.fieldUserPhone,
              isDense: true,
              errorText: draft.phoneError,
              errorMaxLines: 2,
            ),
            onChanged: (_) {
              if (draft.phoneError != null) {
                draft.phoneError = null;
                onChanged();
              }
            },
          ),
          const SizedBox(height: 10),
          PasswordField(
            controller: draft.password,
            isDense: true,
            label: draft.id.isNotEmpty
                ? s.fieldUserPasswordKeep
                : s.fieldUserPassword,
            onChanged: (_) {
              if (draft.passwordError != null) {
                draft.passwordError = null;
                onChanged();
              }
            },
          ),
          // PasswordField takes no errorText, so the message goes right under
          // it rather than into the banner at the far bottom of the screen.
          if (draft.passwordError != null) ...[
            const SizedBox(height: 4),
            Text(draft.passwordError!,
                style: IntesharType.sans(12, color: cs.error)),
          ],
          if (showPreset) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<AgentUserPreset>(
              initialValue: draft.preset,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: s.fieldPreset,
                isDense: true,
              ),
              items: AgentUserPreset.values
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.label(locale)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  draft.preset = v;
                  // An explicit choice overrides a hand-tuned capability set;
                  // merely opening the form does not.
                  draft.presetChosen = true;
                  onChanged();
                }
              },
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: effectiveCaps
                .map(
                  (c) => StampPill(
                    label: c.label(locale),
                    color: cs.outline,
                    filled: false,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _UserDraft {
  final String id;
  final TextEditingController phone;
  final TextEditingController password;
  AgentUserPreset preset;

  /// The capability set this user was LOADED with, when it matched no preset —
  /// null for a new user or one whose caps are exactly a preset.
  ///
  /// [presetForCapabilities] returns null for any set the four presets don't
  /// describe (a user predating the AGENT_ADMIN split, or one HQ tuned by hand),
  /// and the form then falls back to `admin`/`monitoring`. Rebuilding the user
  /// from that fallback would quietly WIDEN such an admin to every capability,
  /// or narrow an operator down to view-only — as a side effect of an edit that
  /// was about the agent's slogan. So the original set is kept and re-sent
  /// verbatim unless the operator actually picks a preset.
  final Set<Capability>? loadedCapabilities;
  bool presetChosen = false;

  /// Validation messages shown on this card's own fields, and the anchor used
  /// to scroll the card into view when it is the first one at fault.
  String? phoneError;
  String? passwordError;
  final GlobalKey anchor = GlobalKey();

  _UserDraft({
    required this.id,
    required String phoneText,
    required this.preset,
    this.loadedCapabilities,
  }) : phone = TextEditingController(text: phoneText),
       password = TextEditingController();

  factory _UserDraft.blank(AgentUserPreset preset) =>
      _UserDraft(id: '', phoneText: '', preset: preset);

  factory _UserDraft.fromUser(EntityUser u) {
    final matched = presetForCapabilities(u.role, u.capabilities);
    return _UserDraft(
      id: u.id,
      phoneText: u.phone,
      preset:
          matched ??
          (u.role == UserRole.ADMIN
              ? AgentUserPreset.admin
              : AgentUserPreset.monitoring),
      // Only when no preset describes them — otherwise the preset IS the set.
      loadedCapabilities:
          matched == null && u.capabilities.isNotEmpty ? u.capabilities : null,
    );
  }

  void dispose() {
    phone.dispose();
    password.dispose();
  }
}
