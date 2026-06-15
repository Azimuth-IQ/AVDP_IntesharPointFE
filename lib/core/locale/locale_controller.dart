import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/storage/session_storage.dart';

const Locale defaultAppLocale = Locale('ar');
const List<Locale> appSupportedLocales = <Locale>[Locale('ar'), Locale('en')];

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(defaultAppLocale) {
    _load();
  }

  Future<void> _load() async {
    final saved = await sessionStorage.getLocale();
    if (saved == null) return;
    if (saved == 'ar' || saved == 'en') {
      state = Locale(saved);
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    await sessionStorage.setLocale(locale.languageCode);
  }

  Future<void> toggle() async {
    final next = state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
    await setLocale(next);
  }
}

final localeControllerProvider = StateNotifierProvider<LocaleController, Locale>(
  (ref) => LocaleController(),
);
