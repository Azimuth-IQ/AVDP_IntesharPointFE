import 'dart:math';
import 'package:inteshar/core/api/error_mapper.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/geo/governorate_picker.dart';
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
  String? _error;

  // Step 1 — entity details
  final _name = TextEditingController();
  final _logo = TextEditingController();
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

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.meta.name;
      _logo.text = e.meta.logoUrl;
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
      for (final u in e.users) {
        _users.add(_UserDraft.fromUser(u));
      }
    }
    // A Sub Agent has a single user.
    if (tier == AgentTier.sub && _users.length > 1) {
      for (var i = 1; i < _users.length; i++) {
        _users[i].dispose();
      }
      final first = _users.first;
      _users
        ..clear()
        ..add(first);
    }
    if (_users.isEmpty) {
      _users.add(_UserDraft.blank(AgentUserPreset.admin));
    }
    if (tier.requiresParentPicker) {
      _loadParents();
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
      _logo,
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

  void _addUser() {
    if (_users.length >= tier.maxUsers) return;
    setState(() => _users.add(_UserDraft.blank(AgentUserPreset.monitoring)));
  }

  bool _validateStep1(AgentStrings s) {
    if (tier.requiresParentPicker &&
        (_parentId == null || _parentId!.isEmpty)) {
      setState(() => _error = s.errParentRequired);
      return false;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = s.errNameRequired);
      return false;
    }
    if (_governorates.isEmpty) {
      setState(() => _error = s.errGovRequired);
      return false;
    }
    // Contact email (optional) — if present it must look like an email.
    final email = _contactEmail.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = s.errEmailInvalid);
      return false;
    }
    // Geo (optional) — if present, must be numeric and in range.
    final lat = _lat.text.trim();
    if (lat.isNotEmpty) {
      final v = double.tryParse(lat);
      if (v == null || v < -90 || v > 90) {
        setState(() => _error = s.errGeoInvalid);
        return false;
      }
    }
    final lng = _lng.text.trim();
    if (lng.isNotEmpty) {
      final v = double.tryParse(lng);
      if (v == null || v < -180 || v > 180) {
        setState(() => _error = s.errGeoInvalid);
        return false;
      }
    }
    setState(() => _error = null);
    return true;
  }

  Future<void> _submit() async {
    final s = AgentStrings.of(context, tier);
    if (!_validateStep1(s)) {
      setState(() => _step = 0);
      return;
    }
    if (_users.isEmpty) {
      setState(() => _error = s.errUsersRequired);
      return;
    }
    if (_users.length > tier.maxUsers) {
      setState(() => _error = s.errMaxUsers);
      return;
    }

    final users = <EntityUser>[];
    for (final d in _users) {
      final phone = d.phone.text.trim();
      if (phone.isEmpty) {
        setState(() => _error = s.errUserPhone);
        return;
      }
      final typed = d.password.text.trim();
      // An existing user (already has an id) may keep its current password by leaving this
      // blank: EntityUser.toJson omits a blank password and the backend restores the stored
      // hash on update. Only a NEW user must set one.
      if (typed.isEmpty && d.id.isEmpty) {
        setState(() => _error = s.errUserPassword);
        return;
      }
      users.add(
        EntityUser(
          id: d.id.isNotEmpty ? d.id : _genId('u'),
          phone: phone,
          password: typed,
          role: d.preset.role,
          capabilities: _capsFor(d.preset),
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
      logoUrl: _logo.text.trim(),
      backgroundUrl: _background.text.trim(),
      primaryColor: _primary.text.trim(),
      secondaryColor: _secondary.text.trim(),
      governorates: _governorates.toList(),
      workingHours: _workingHours,
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
                      if (_validateStep1(s)) setState(() => _step = 1);
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
              initialValue: _parentId,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.fieldParent),
              items: _parentOptions
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.label)),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _parentId = v;
                _applyParentCoverage();
              }),
            ),
          const SizedBox(height: 22),
        ],
        // B-055: which sections this agent — and its ENTIRE subtree (sub-agents,
        // POS apps) — may see. Server-enforced; the nav simply mirrors it.
        SectionLabel(Localizations.localeOf(context).languageCode == 'ar'
            ? 'الأقسام المتاحة'
            : 'Visible sections'),
        const SizedBox(height: 4),
        Text(
          Localizations.localeOf(context).languageCode == 'ar'
              ? 'الأقسام المخفية تختفي عن الوكيل وكل حساباته الفرعية ونقاط بيعه.'
              : 'Hidden sections disappear for this agent and its whole subtree (sub-agents, POS).',
          style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
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
        const SizedBox(height: 22),
        SectionLabel(s.sectionIdentity),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: InputDecoration(labelText: s.fieldName),
        ),
        const SizedBox(height: 12),
        ImageUploadField(
          value: _logo.text.isEmpty ? null : _logo.text,
          kind: 'agent-branding',
          label: s.fieldLogo,
          onChanged: (u) => setState(() => _logo.text = u),
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
          selected: _governorates,
          allowedCodes: _allowedGovernorates,
          onChanged: (v) => setState(() => _governorates = v),
        ),
        const SizedBox(height: 22),
        SectionLabel(
          Localizations.localeOf(context).languageCode == 'ar'
              ? 'ساعات الدخول'
              : 'Login hours',
        ),
        const SizedBox(height: 8),
        WorkingHoursEditor(
          value: _workingHours,
          onChanged: (v) => setState(() => _workingHours = v),
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
        const SizedBox(height: 12),
        TextField(
          controller: _landmark,
          decoration: InputDecoration(labelText: s.fieldLandmark),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(labelText: s.fieldLat),
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
                decoration: InputDecoration(labelText: s.fieldLng),
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
          controller: _contactEmail,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: s.fieldEmail),
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
            padding: const EdgeInsets.only(bottom: 12),
            child: _UserCard(
              index: e.key,
              draft: e.value,
              s: s,
              showPreset: showPreset,
              effectiveCaps: _capsFor(e.value.preset),
              onChanged: () => setState(() {}),
              onRemove: (_users.length > 1)
                  ? () => setState(() => _users.removeAt(e.key))
                  : null,
            ),
          ),
        ),
        if (_users.length < tier.maxUsers)
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
            color: on ? IntesharColors.saffron : cs.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check, size: 15, color: IntesharColors.ink)
              : Text(
                  '$index',
                  style: IntesharType.sans(
                    12,
                    w: FontWeight.w800,
                    color: on ? IntesharColors.ink : cs.onSurfaceVariant,
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
          ? IntesharColors.saffron
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
                IconButton(
                  visualDensity: VisualDensity.compact,
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
            ),
          ),
          const SizedBox(height: 10),
          PasswordField(
            controller: draft.password,
            isDense: true,
            label: draft.id.isNotEmpty
                ? s.fieldUserPasswordKeep
                : s.fieldUserPassword,
          ),
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

  _UserDraft({
    required this.id,
    required String phoneText,
    required this.preset,
  }) : phone = TextEditingController(text: phoneText),
       password = TextEditingController();

  factory _UserDraft.blank(AgentUserPreset preset) =>
      _UserDraft(id: '', phoneText: '', preset: preset);

  factory _UserDraft.fromUser(EntityUser u) => _UserDraft(
    id: u.id,
    phoneText: u.phone,
    preset:
        presetForCapabilities(u.role, u.capabilities) ??
        (u.role == UserRole.ADMIN
            ? AgentUserPreset.admin
            : AgentUserPreset.monitoring),
  );

  void dispose() {
    phone.dispose();
    password.dispose();
  }
}
