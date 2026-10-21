import 'dart:convert';

/// B-151: whether a JWT's `exp` claim has passed (with [skew] of tolerance for a device clock
/// that runs slightly fast). Reads the payload only — no signature check, which is the
/// server's job; this just stops the app from firing requests with a token the server is
/// certain to refuse.
///
/// A token that cannot be read (not three parts, bad base64, no numeric `exp`) is treated as
/// NOT expired: the server stays the judge, and its 401 ends the session.
bool isJwtExpired(String token, {DateTime? now, Duration skew = const Duration(seconds: 30)}) {
  final parts = token.split('.');
  if (parts.length != 3) return false;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    final exp = payload is Map ? payload['exp'] : null;
    if (exp is! num) return false;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
    return (now ?? DateTime.now()).toUtc().isAfter(expiresAt.add(skew));
  } catch (_) {
    return false;
  }
}
