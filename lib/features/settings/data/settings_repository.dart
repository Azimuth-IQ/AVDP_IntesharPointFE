import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/entities/domain/entity.dart';

/// Repository for platform-wide settings that do not belong to a specific
/// feature slice (working hours enforcement, etc.).
///
/// All endpoints require a valid JWT + AGENT_ADMIN capability (enforced by
/// the backend SecurityConfig; the FE relies on the router/nav guard).
class SettingsRepository {
  final ApiClient _api;
  SettingsRepository(this._api);

  /// Returns whether the global working-hours login gate is currently active.
  ///
  /// When [true], entity logins outside their [WorkingHours] window are
  /// rejected with `403 OUTSIDE_WORKING_HOURS`. When [false], every login
  /// is allowed regardless of any per-account window.
  Future<bool> getGlobalWorkingHoursEnabled() async {
    final response = await _api.get(Endpoints.settingsWorkingHours);
    // The generic /api/settings/{key} GET returns the bare stored value
    // (true/false, or null when never set = off).
    return _api.unwrap(response, (d) => d == true);
  }

  /// Enables or disables the global working-hours gate platform-wide.
  ///
  /// [enabled] = true → working-hours windows are enforced for all entities
  /// that have a window configured. [enabled] = false → all logins succeed
  /// regardless of configured windows (windows are preserved, just ignored).
  Future<void> setGlobalWorkingHoursEnabled(bool enabled) async {
    // Generic key/value setting: body is {"value": <any>}.
    await _api.post(
      Endpoints.settingsWorkingHours,
      data: {'value': enabled},
    );
  }

  /// Configures the [WorkingHours] login window for a specific entity.
  ///
  /// The backend stores this on `EntityMeta.workingHours` via a targeted
  /// patch — no other entity fields are touched. Passing
  /// [WorkingHours.enabled] = false disables the window for that account
  /// without deleting its time/day configuration.
  Future<void> setEntityWorkingHours(String entityId, WorkingHours wh) async {
    // POST /api/entity/workingHours?id=<entityId> with the WorkingHours as body;
    // the backend does a targeted $set on meta.workingHours only.
    await _api.post(
      Endpoints.settingsWorkingHoursEntity,
      params: {'id': entityId},
      data: wh.toJson(),
    );
  }
}
