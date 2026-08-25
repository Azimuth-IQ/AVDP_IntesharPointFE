import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// Who can HOLD POS points.
///
/// A POS point is the licence to onboard a shop, and the backend only ever
/// onboards a shop under a Main or Sub agent (`PosController.onboard` rejects
/// any other host with `400 "A POS must be onboarded under a Main or Sub
/// agent"`). So only those two tiers can ever spend a point.
///
/// HQ is excluded because it is the unbounded origin of points, and STORE is
/// excluded because a store IS a point of sale — points granted to a store can
/// never be consumed, they just sit in the ledger inflating the network
/// "issued"/"unused" KPIs forever.
const List<EntityType> kPosPointHolderTypes = [EntityType.AGENT1, EntityType.AGENT2];

/// The shop's counter user — the login that actually sells at the till.
///
/// Onboarding (B-052) gives a STORE exactly one operator, flagged `isPos`. The
/// second branch covers pre-`isPos` shops, where the counter was identified by
/// the same legacy rule the session resolver still uses (a `USER` role sitting
/// on a STORE — see `AuthController`). A store whose only login is its ADMIN
/// owner has no counter at all, and returns null rather than falsely offering
/// the owner's own account: the credential endpoints all require `isPos`, so
/// anything else here would be a guaranteed 403.
EntityUser? counterUserOf(Entity store) {
  // UX-156: liveUsers only. A retired operator is not who runs the counter,
  // and offering their account would be a guaranteed 403 on every credential
  // endpoint — the same dead end the isPos check already avoids.
  for (final u in store.liveUsers) {
    if (u.isPos) return u;
  }
  for (final u in store.liveUsers) {
    if (u.role == UserRole.USER) return u;
  }
  return null;
}
