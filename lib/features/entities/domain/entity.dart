import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// Per-account login window (BRD FR-03). Null on EntityMeta / disabled = always open.
class WorkingHours {
  final bool enabled;
  final String start; // "HH:mm" 24h, Asia/Baghdad
  final String end; // "HH:mm"; end < start means the window wraps past midnight
  final List<int> days; // ISO day-of-week 1=Mon..7=Sun; empty = every day

  const WorkingHours({this.enabled = false, this.start = '', this.end = '', this.days = const []});

  factory WorkingHours.fromJson(Map<String, dynamic> j) => WorkingHours(
        enabled: j['enabled'] as bool? ?? false,
        start: j['start'] as String? ?? '',
        end: j['end'] as String? ?? '',
        days: (j['days'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'start': start,
        'end': end,
        'days': days,
      };

  WorkingHours copyWith({bool? enabled, String? start, String? end, List<int>? days}) => WorkingHours(
        enabled: enabled ?? this.enabled,
        start: start ?? this.start,
        end: end ?? this.end,
        days: days ?? this.days,
      );
}

/// One HQ-managed home-slider image: an uploaded [url] plus an [active] toggle.
/// Display order is the position within [EntityMeta.sliderImages] (index 0 first).
class SliderImage {
  final String url;
  final bool active;
  const SliderImage({required this.url, this.active = true});

  factory SliderImage.fromJson(Map<String, dynamic> j) => SliderImage(
        url: j['url'] as String? ?? '',
        active: j['active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {'url': url, 'active': active};

  SliderImage copyWith({String? url, bool? active}) =>
      SliderImage(url: url ?? this.url, active: active ?? this.active);
}

class EntityMeta {
  /// App-wide fallback used when an entity hasn't configured its own
  /// [lowStockThreshold]. A SKU with fewer available units is flagged low.
  static const int defaultLowStockThreshold = 50;

  final String name;
  final String slogan;
  final String description;
  final String logoUrl;
  final String backgroundUrl;
  final List<String> sliderImagesUrl;      // legacy flat list (active URLs, in order)
  final List<SliderImage> sliderImages;    // structured slider: per-image active + order
  final String primaryColor;   // brand hex (e.g. #F5B100) — white-label
  final String secondaryColor; // accent hex — white-label
  final int lowStockThreshold; // per-account low-stock alert level; 0 = unset → default
  final List<String> governorates; // governorate codes this entity operates in (geo-lock)
  final WorkingHours? workingHours; // per-account login window (BRD FR-03); null = always open

  const EntityMeta({this.name = '', this.slogan = '', this.description = '', this.logoUrl = '', this.backgroundUrl = '', this.sliderImagesUrl = const [], this.sliderImages = const [], this.primaryColor = '', this.secondaryColor = '', this.lowStockThreshold = 0, this.governorates = const [], this.workingHours});

  /// The structured slider list, migrating legacy flat [sliderImagesUrl] (all
  /// active, in order) when no structured list has been saved yet.
  List<SliderImage> get effectiveSliderImages => sliderImages.isNotEmpty
      ? sliderImages
      : sliderImagesUrl.map((u) => SliderImage(url: u)).toList();

  /// The threshold to actually apply: the configured value, or the default
  /// when unset (0 or negative).
  int get effectiveLowStockThreshold =>
      lowStockThreshold > 0 ? lowStockThreshold : defaultLowStockThreshold;

  factory EntityMeta.fromJson(Map<String, dynamic> j) => EntityMeta(
    name: j['name'] as String? ?? '',
    slogan: j['slogan'] as String? ?? '',
    description: j['description'] as String? ?? '',
    logoUrl: j['logoUrl'] as String? ?? '',
    backgroundUrl: j['backgroundUrl'] as String? ?? '',
    sliderImagesUrl: (j['sliderImagesUrl'] as List<dynamic>?)?.cast<String>() ?? [],
    sliderImages: (j['sliderImages'] as List<dynamic>?)
            ?.map((e) => SliderImage.fromJson((e as Map).cast<String, dynamic>()))
            .toList() ??
        const [],
    primaryColor: j['primaryColor'] as String? ?? '',
    secondaryColor: j['secondaryColor'] as String? ?? '',
    lowStockThreshold: (j['lowStockThreshold'] as num?)?.toInt() ?? 0,
    governorates: (j['governorates'] as List<dynamic>?)?.cast<String>() ?? const [],
    workingHours: j['workingHours'] == null ? null : WorkingHours.fromJson((j['workingHours'] as Map).cast<String, dynamic>()),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'slogan': slogan,
    'description': description,
    'logoUrl': logoUrl,
    'backgroundUrl': backgroundUrl,
    'sliderImagesUrl': sliderImagesUrl,
    'sliderImages': sliderImages.map((e) => e.toJson()).toList(),
    'primaryColor': primaryColor,
    'secondaryColor': secondaryColor,
    'lowStockThreshold': lowStockThreshold,
    'governorates': governorates,
    if (workingHours != null) 'workingHours': workingHours!.toJson(),
  };

  EntityMeta copyWith({String? name, String? slogan, String? description, String? logoUrl, String? backgroundUrl, List<String>? sliderImagesUrl, List<SliderImage>? sliderImages, String? primaryColor, String? secondaryColor, int? lowStockThreshold, List<String>? governorates, WorkingHours? workingHours}) => EntityMeta(
    name: name ?? this.name,
    slogan: slogan ?? this.slogan,
    description: description ?? this.description,
    logoUrl: logoUrl ?? this.logoUrl,
    backgroundUrl: backgroundUrl ?? this.backgroundUrl,
    sliderImagesUrl: sliderImagesUrl ?? this.sliderImagesUrl,
    sliderImages: sliderImages ?? this.sliderImages,
    primaryColor: primaryColor ?? this.primaryColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    governorates: governorates ?? this.governorates,
    workingHours: workingHours ?? this.workingHours,
  );
}

/// Operational / KYC details captured during agent onboarding (separate from
/// branding [EntityMeta]). Mirrors backend `EntityProfile`. All fields optional.
class EntityProfile {
  final String ownerName;
  final List<String> documentUrls;
  final double? latitude;
  final double? longitude;
  final String nearestLandmark;
  final String address; // street address text — العنوان (B-052)
  // B-054: one-time at-the-shop location confirmation. Selling is blocked
  // (server + UI gate) until locationConfirmedAt is set.
  final double? confirmedLatitude;
  final double? confirmedLongitude;
  final String? locationConfirmedAt;
  final String contactPhone;
  final String contactEmail;

  const EntityProfile({
    this.ownerName = '',
    this.documentUrls = const [],
    this.latitude,
    this.longitude,
    this.nearestLandmark = '',
    this.address = '',
    this.confirmedLatitude,
    this.confirmedLongitude,
    this.locationConfirmedAt,
    this.contactPhone = '',
    this.contactEmail = '',
  });

  factory EntityProfile.fromJson(Map<String, dynamic> j) => EntityProfile(
        ownerName: j['ownerName'] as String? ?? '',
        documentUrls: (j['documentUrls'] as List<dynamic>?)?.cast<String>() ?? const [],
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        nearestLandmark: j['nearestLandmark'] as String? ?? '',
        address: j['address'] as String? ?? '',
        confirmedLatitude: (j['confirmedLatitude'] as num?)?.toDouble(),
        confirmedLongitude: (j['confirmedLongitude'] as num?)?.toDouble(),
        locationConfirmedAt: j['locationConfirmedAt']?.toString(),
        contactPhone: j['contactPhone'] as String? ?? '',
        contactEmail: j['contactEmail'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'ownerName': ownerName,
        'documentUrls': documentUrls,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'nearestLandmark': nearestLandmark,
        'address': address,
        'contactPhone': contactPhone,
        'contactEmail': contactEmail,
      };

  EntityProfile copyWith({String? ownerName, List<String>? documentUrls, double? latitude, double? longitude, String? nearestLandmark, String? address, String? contactPhone, String? contactEmail}) => EntityProfile(
        ownerName: ownerName ?? this.ownerName,
        documentUrls: documentUrls ?? this.documentUrls,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        nearestLandmark: nearestLandmark ?? this.nearestLandmark,
        address: address ?? this.address,
        contactPhone: contactPhone ?? this.contactPhone,
        contactEmail: contactEmail ?? this.contactEmail,
      );
}

class EntityUser {
  final String id;
  final String phone;
  final String password;
  final UserRole role;
  final Set<Capability> capabilities; // fine-grained RBAC permissions
  // POS-user quota model: a POS is a USER with isPos=true attached to ANY entity. isPos (not the
  // entity type) drives the POS session. The point-of-sale "full details" live on the user.
  final bool isPos;
  final String posName;
  final String posOwnerName;
  final String posGovernorate;
  final String posAddress;

  const EntityUser({
    this.id = '',
    required this.phone,
    this.password = '',
    required this.role,
    this.capabilities = const {},
    this.isPos = false,
    this.posName = '',
    this.posOwnerName = '',
    this.posGovernorate = '',
    this.posAddress = '',
  });

  factory EntityUser.fromJson(Map<String, dynamic> j) => EntityUser(
    id: j['id'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    password: j['password'] as String? ?? '',
    role: UserRole.values.firstWhere((e) => e.name == (j['role'] as String? ?? 'USER'), orElse: () => UserRole.USER),
    capabilities: capabilitiesFromJson(j['capabilities']),
    isPos: j['isPos'] as bool? ?? false,
    posName: j['posName'] as String? ?? '',
    posOwnerName: j['posOwnerName'] as String? ?? '',
    posGovernorate: j['posGovernorate'] as String? ?? '',
    posAddress: j['posAddress'] as String? ?? '',
  );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'phone': phone, 'role': role.name};
    if (id.isNotEmpty) m['id'] = id;
    if (password.isNotEmpty) m['password'] = password;
    if (capabilities.isNotEmpty) m['capabilities'] = capabilitiesToJson(capabilities);
    return m;
  }

  EntityUser copyWith({String? id, String? phone, String? password, UserRole? role, Set<Capability>? capabilities}) => EntityUser(
    id: id ?? this.id,
    phone: phone ?? this.phone,
    password: password ?? this.password,
    role: role ?? this.role,
    capabilities: capabilities ?? this.capabilities,
    isPos: isPos,
    posName: posName,
    posOwnerName: posOwnerName,
    posGovernorate: posGovernorate,
    posAddress: posAddress,
  );
}

class Entity {
  final String id;
  final EntityMeta meta;
  final EntityProfile? profile;
  final String parent;
  final EntityType type;
  final List<String> childrenIds;
  final List<String> productsIds;
  final List<EntityUser> users;
  final bool active; // operational on/off — a disabled point's users cannot log in

  /// B-055 section ceiling HQ set on THIS entity (cascades to its subtree).
  /// Null = unrestricted; `{AGENT_ADMIN}` also reads as unrestricted.
  final Set<Capability>? allowedCapabilities;

  /// B-055: the caller USER's resolved capability set from `GET /entity/me`
  /// (own caps ∩ chain ceiling, wildcards expanded). Null on other reads.
  final Set<Capability>? effectiveCapabilities;

  /// B-061: the caller's own ntfy push topic + base URL, returned only by
  /// `/entity/me` (empty when push is disabled server-side).
  final String pushToken;
  final String pushBaseUrl;

  const Entity({required this.id, required this.meta, this.profile, this.parent = '', required this.type, this.childrenIds = const [], this.productsIds = const [], this.users = const [], this.active = true, this.allowedCapabilities, this.effectiveCapabilities, this.pushToken = '', this.pushBaseUrl = ''});

  factory Entity.fromJson(Map<String, dynamic> j) => Entity(
    id: j['id'] as String? ?? j['_id'] as String? ?? '',
    meta: EntityMeta.fromJson(j['meta'] as Map<String, dynamic>? ?? {}),
    profile: j['profile'] == null ? null : EntityProfile.fromJson(j['profile'] as Map<String, dynamic>),
    parent: j['parent'] as String? ?? '',
    type: EntityType.values.firstWhere((e) => e.name == (j['type'] as String? ?? 'INTESHAR'), orElse: () => EntityType.INTESHAR),
    childrenIds: (j['childrenIds'] as List<dynamic>?)?.cast<String>() ?? [],
    productsIds: (j['productsIds'] as List<dynamic>?)?.cast<String>() ?? [],
    users: (j['users'] as List<dynamic>?)?.map((u) => EntityUser.fromJson(u as Map<String, dynamic>)).toList() ?? [],
    active: j['active'] as bool? ?? true,
    allowedCapabilities: j['allowedCapabilities'] == null ? null : capabilitiesFromJson(j['allowedCapabilities']),
    effectiveCapabilities: j['effectiveCapabilities'] == null ? null : capabilitiesFromJson(j['effectiveCapabilities']),
    pushToken: j['pushToken'] as String? ?? '',
    pushBaseUrl: j['pushBaseUrl'] as String? ?? '',
  );

  Map<String, dynamic> toJson({bool includeUsers = false}) {
    final m = <String, dynamic>{
      'id': id,
      'meta': meta.toJson(),
      'parent': parent.isEmpty ? null : parent,
      'type': type.name,
      'childrenIds': childrenIds,
      'productsIds': productsIds,
      'active': active,
    };
    if (profile != null) m['profile'] = profile!.toJson();
    // Omitted (null) = "no change" server-side; to clear a ceiling send {AGENT_ADMIN}.
    if (allowedCapabilities != null) {
      m['allowedCapabilities'] = capabilitiesToJson(allowedCapabilities!);
    }
    if (includeUsers && users.isNotEmpty) {
      m['users'] = users.map((u) => u.toJson()).toList();
    }
    return m;
  }

  Entity copyWith({String? id, EntityMeta? meta, EntityProfile? profile, String? parent, EntityType? type, List<String>? childrenIds, List<String>? productsIds, List<EntityUser>? users, bool? active, Set<Capability>? allowedCapabilities}) => Entity(
    id: id ?? this.id,
    meta: meta ?? this.meta,
    profile: profile ?? this.profile,
    parent: parent ?? this.parent,
    type: type ?? this.type,
    childrenIds: childrenIds ?? this.childrenIds,
    productsIds: productsIds ?? this.productsIds,
    users: users ?? this.users,
    active: active ?? this.active,
    allowedCapabilities: allowedCapabilities ?? this.allowedCapabilities,
    effectiveCapabilities: effectiveCapabilities,
  );
}
