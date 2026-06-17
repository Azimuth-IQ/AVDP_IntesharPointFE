import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/update/domain/app_release.dart';

class ReleaseRepository {
  final ApiClient _api;
  ReleaseRepository(this._api);

  /// Asks the backend whether [versionCode] (the installed build number) needs
  /// an update. Public endpoint — works before login and for forced gating.
  Future<UpdateCheck> check({
    required int versionCode,
    String platform = 'android',
    String channel = 'uat',
  }) async {
    final r = await _api.get(Endpoints.appCheck, params: {
      'versionCode': versionCode,
      'platform': platform,
      'channel': channel,
    });
    return _api.unwrap(r, (d) => UpdateCheck.fromJson(d as Map<String, dynamic>));
  }
}

final releaseRepositoryProvider = Provider<ReleaseRepository>((ref) {
  return ReleaseRepository(ref.watch(apiClientProvider));
});
