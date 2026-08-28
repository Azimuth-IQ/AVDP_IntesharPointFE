import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display preferences that belong to the DEVICE, not to the session (UX-153).
///
/// High contrast is a property of where the handheld is standing — a shop front
/// in Baghdad sun — so it must survive a logout, a shift change and a different
/// operator signing in on the same terminal. That is why it is kept on its own
/// `SharedPreferences` key instead of going through `SessionStorage`, which is
/// the session's store and is cleared on sign-out.
///
/// **Why high contrast and not dark mode.** The dark theme has been built but
/// unreachable (`themeMode: ThemeMode.light`) for as long as it has existed, and
/// the reason it stays that way is written up on `SurfaceTreatment` in
/// `theme.dart`. Independently of that: a dark theme is the wrong tool for this
/// product's hard case. The POS is used OUTDOORS; sunlight does not make a
/// screen too bright, it makes it too washed out, and the answer to washed out
/// is *more* separation between ink and paper, not less light. Dark mode is a
/// comfort feature for dim rooms; this is a legibility feature for daylight.
class DisplayPrefs {
  static const String _kHighContrastKey = 'display_high_contrast';

  const DisplayPrefs._();

  static Future<bool> loadHighContrast() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHighContrastKey) ?? false;
  }

  static Future<void> saveHighContrast(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHighContrastKey, value);
  }
}

/// Whether the app paints its high-contrast theme.
///
/// Starts `false` and flips once the stored value loads, exactly like
/// [LocaleController] — a one-frame default is invisible next to the splash, and
/// blocking startup on a disk read to avoid it would be the worse trade.
class HighContrastController extends StateNotifier<bool> {
  HighContrastController() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final saved = await DisplayPrefs.loadHighContrast();
    if (saved != state) state = saved;
  }

  Future<void> set(bool value) async {
    state = value;
    await DisplayPrefs.saveHighContrast(value);
  }

  Future<void> toggle() => set(!state);
}

final highContrastProvider =
    StateNotifierProvider<HighContrastController, bool>(
  (ref) => HighContrastController(),
);
