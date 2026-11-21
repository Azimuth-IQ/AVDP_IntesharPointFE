import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/update/application/update_controller.dart';
import 'package:inteshar/features/update/domain/app_release.dart';
import 'package:inteshar/features/update/presentation/update_gate.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// PROD-017: the app looked for updates only when it started.
/// PROD-018: after "Update now" the sheet vanished, so the 50 MB download ran with nothing on
/// screen and the shop thought the update had done nothing.
const _release = AppRelease(
  channel: 'uat',
  platform: 'android',
  versionName: '1.0.0',
  versionCode: 163,
  apkUrl: 'https://example.invalid/inteshar-163.apk',
  sizeBytes: 50000000,
  sha256: 'abc',
  mandatory: false,
  minSupportedVersionCode: 161,
  changelog: 'تحسينات وإصلاحات.',
);

class _FakeUpdates extends UpdateController {
  _FakeUpdates(this.initial);
  final UpdateState initial;
  int checks = 0;

  @override
  UpdateState build() => initial;

  @override
  Future<void> check() async => checks++;

  void set(UpdateState s) => state = s;
}

class _Counter extends StatefulWidget {
  const _Counter();
  static int created = 0;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  void initState() {
    super.initState();
    _Counter.created++;
  }

  @override
  Widget build(BuildContext context) => const Text('SALE ON SCREEN');
}

Future<_FakeUpdates> _pump(WidgetTester tester, UpdateState initial) async {
  final fake = _FakeUpdates(initial);
  await tester.pumpWidget(ProviderScope(
    overrides: [updateControllerProvider.overrideWith(() => fake)],
    child: MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => UpdateGate(child: child!),
      home: const Scaffold(body: _Counter()),
    ),
  ));
  await tester.pump();
  return fake;
}

void main() {
  group('the optional sheet stays up through the download (PROD-018)', () {
    test('shown while available, downloading and failed — not only while available', () {
      expect(showsOptionalUpdate(const UpdateAvailableState(_release, false)), isTrue);
      expect(showsOptionalUpdate(const UpdateDownloading(_release, false, 0.4)), isTrue);
      expect(showsOptionalUpdate(const UpdateFailed(_release, false, 'x')), isTrue);
      expect(showsOptionalUpdate(const UpToDate()), isFalse);
      expect(showsOptionalUpdate(const UpdateDownloading(_release, true, 0.4)), isFalse, reason: 'forced screen instead');
    });

    testWidgets('downloading → a progress bar with the percentage, no «لاحقاً», scrim taps ignored', (tester) async {
      await _pump(tester, const UpdateDownloading(_release, false, 0.42));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('42%'), findsOneWidget);
      expect(find.text('لا تُغلق التطبيق حتى يكتمل التنزيل.'), findsOneWidget);
      expect(find.text('لاحقاً'), findsNothing);
      await tester.tapAt(const Offset(10, 10)); // the scrim
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    test('the line under the bar', () async {
      final l = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(updateProgressLabel(l, 0), l.updateDownloading, reason: 'not "Opening installer" before any byte');
      expect(updateProgressLabel(l, 0.375), '${l.updateDownloading} 37%');
      expect(updateProgressLabel(l, 1), l.updateOpenInstaller);
    });
  });

  group('re-checks (PROD-017)', () {
    final now = DateTime(2026, 11, 21, 12);
    test('coming back to the app checks again — at most once an hour', () {
      expect(shouldRecheckOnResume(null, now), isTrue);
      expect(shouldRecheckOnResume(now.subtract(const Duration(minutes: 10)), now), isFalse);
      expect(shouldRecheckOnResume(now.subtract(const Duration(hours: 1)), now), isTrue);
    });

    test('an open app checks every 6 hours', () {
      expect(updateRecheckEvery, const Duration(hours: 6));
    });

    testWidgets('the gate checks on start, then every 6 hours', (tester) async {
      final fake = await _pump(tester, const UpToDate());
      expect(fake.checks, 1);
      await tester.pump(const Duration(hours: 6));
      expect(fake.checks, 2);
    });

    testWidgets('a forced update found mid-sale covers the sale but does not destroy it', (tester) async {
      _Counter.created = 0;
      final fake = await _pump(tester, const UpToDate());
      expect(find.text('SALE ON SCREEN'), findsOneWidget);
      fake.set(const UpdateAvailableState(_release, true));
      await tester.pump();
      expect(find.text('SALE ON SCREEN'), findsNothing, reason: 'hidden behind the forced screen');
      expect(find.text('SALE ON SCREEN', skipOffstage: false), findsOneWidget, reason: 'still alive');
      expect(_Counter.created, 1, reason: 'the sale sheet was not rebuilt from scratch');
    });
  });
}
