import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/template_inheritance.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';
import 'package:inteshar/features/inventory/presentation/voucher_templates_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// PROD-023: one print template per company; a category follows it until it has
/// its own. Owner, 2026-11-21: "a general Asiacell setting, then if we want to modify
/// the print template of the Asiacell 10k we can".

class _Put {
  final String path;
  final Map<String, dynamic>? params;
  final dynamic data;
  _Put(this.path, this.params, this.data);
}

class _FakeApi extends ApiClient {
  _FakeApi() : super(Dio());

  final puts = <_Put>[];

  final company = <String, dynamic>{
    'id': 'co-asia',
    'name': 'Asiacell',
    'displayOrder': 1,
    'voucherTemplate': {'headerText': 'ASIACELL HDR'},
  };

  final defs = <Map<String, dynamic>>[
    {
      'id': 'd-5k', 'name': 'Asiacell 5000', 'sku': 'AS5', 'defaultPrice': 5000,
      'companyId': 'co-asia', 'followsCompanyTemplate': true,
      'voucherTemplate': {'headerText': 'STALE COPY'},
    },
    {
      'id': 'd-10k', 'name': 'Asiacell 10000', 'sku': 'AS10', 'defaultPrice': 10000,
      'companyId': 'co-asia', 'followsCompanyTemplate': false,
      'voucherTemplate': {'headerText': 'TEN OWN'},
    },
    {
      'id': 'd-it', 'name': 'iTunes 10', 'sku': 'IT10', 'defaultPrice': 15000,
      'voucherTemplate': {'headerText': 'ITUNES'},
    },
  ];

  Response<dynamic> _ok(String path, dynamic data) => Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'status': 200, 'message': 'ok', 'data': data},
      );

  @override
  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    if (path == Endpoints.definitionReadAll) return _ok(path, defs);
    if (path == Endpoints.companyReadAll) return _ok(path, [company]);
    throw UnsupportedError('_FakeApi: unexpected GET $path');
  }

  @override
  Future<Response<dynamic>> put(String path, {dynamic data, Map<String, dynamic>? params}) async {
    puts.add(_Put(path, params, data));
    if (path == Endpoints.companyTemplate) {
      company['voucherTemplate'] = data;
      return _ok(path, company);
    }
    if (path == Endpoints.definitionTemplate) {
      final d = defs.firstWhere((d) => d['id'] == params!['id']);
      final body = data as Map<String, dynamic>;
      if (body['followsCompany'] != null) d['followsCompanyTemplate'] = body['followsCompany'];
      if (body['template'] != null) d['voucherTemplate'] = body['template'];
      return _ok(path, d);
    }
    throw UnsupportedError('_FakeApi: unexpected PUT $path');
  }
}

Future<_FakeApi> _pump(WidgetTester tester, {Size size = const Size(1400, 1000), Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _FakeApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(api)],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const VoucherTemplatesPage(),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  group('the rule (same as the backend)', () {
    const own = VoucherTemplate(headerText: 'OWN');
    const co = Company(id: 'co-asia', name: 'Asiacell', voucherTemplate: VoucherTemplate(headerText: 'CO'));
    ProductDefinition def({bool? follows, String companyId = 'co-asia'}) => ProductDefinition(
        id: 'd', name: 'Asiacell 10000', defaultPrice: '10000', sku: 'AS10',
        companyId: companyId, template: own, followsCompanyTemplate: follows);

    test('follows → the company template; own → its own', () {
      expect(effectiveTemplate(def(follows: true), co).headerText, 'CO');
      expect(effectiveTemplate(def(follows: false), co).headerText, 'OWN');
    });

    test('a company without a template gives the built-in default', () {
      final t = effectiveTemplate(def(follows: true), const Company(id: 'co-asia', name: 'Asiacell'));
      expect(t.toJson(), const VoucherTemplate().toJson());
    });

    test('no flag yet, no company, or another company → its own', () {
      expect(effectiveTemplate(def(follows: null), co).headerText, 'OWN');
      expect(effectiveTemplate(def(follows: true), null).headerText, 'OWN');
      expect(effectiveTemplate(def(follows: true, companyId: 'co-zain'), co).headerText, 'OWN');
      expect(companyOf(def(companyId: ''), [co]), isNull);
      expect(companyOf(def(), [co])?.name, 'Asiacell');
    });

    test('the category editor never sends a flag it does not know (the backend keeps it)', () {
      expect(def(follows: null).toJson().containsKey('followsCompanyTemplate'), isFalse);
      expect(def(follows: true).toJson()['followsCompanyTemplate'], isTrue);
      expect(ProductDefinition.fromJson({'followsCompanyTemplate': false}).followsCompanyTemplate, isFalse);
    });

    test('a company edit never sends — and never drops — the template', () {
      expect(co.toJson().containsKey('voucherTemplate'), isFalse);
      expect(co.copyWith(name: 'Asia').voucherTemplate?.headerText, 'CO');
      expect(Company.fromJson({'name': 'Zain'}).voucherTemplate, isNull);
    });
  });

  group('HQ templates screen', () {
    testWidgets('companies, their categories marked follows / own, then "No company"', (tester) async {
      await _pump(tester);
      expect(find.text('Asiacell'), findsOneWidget);
      expect(find.text('Asiacell 5000'), findsOneWidget);
      expect(find.text('Asiacell 10000'), findsOneWidget);
      expect(find.text('Follows company'), findsOneWidget);
      expect(find.text('Own template'), findsOneWidget);
      expect(find.text('No company'), findsOneWidget);
      expect(find.text('iTunes 10'), findsOneWidget);
    });

    testWidgets('a following category previews the company template, read-only, and can be customised',
        (tester) async {
      final api = await _pump(tester);
      await tester.tap(find.text('Asiacell 5000'));
      await tester.pumpAndSettle();

      expect(find.textContaining("prints with Asiacell's template"), findsOneWidget);
      expect(find.text('ASIACELL HDR'), findsOneWidget, reason: 'the paper shows the company template');
      expect(find.text('STALE COPY'), findsNothing);
      expect(find.byType(TextField), findsNothing, reason: 'nothing of its own to edit');

      await tester.tap(find.text('Customise this category'));
      await tester.pumpAndSettle();

      final put = api.puts.single;
      expect(put.path, Endpoints.definitionTemplate);
      expect(put.params, {'id': 'd-5k'});
      expect(put.data['followsCompany'], isFalse);
      expect(put.data['template']['headerText'], 'ASIACELL HDR', reason: 'starts from a copy of the company template');
      expect(find.byType(TextField), findsWidgets, reason: 'now it has its own template to edit');
      expect(find.text('Own template'), findsNWidgets(2));
    });

    testWidgets('the company template is edited and saved on the company', (tester) async {
      final api = await _pump(tester);
      await tester.tap(find.text('Asiacell'));
      await tester.pumpAndSettle();

      expect(find.text("Applies to 1 of the company's categories · 1 have their own template"), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'NEW HDR');
      await tester.pump();
      await tester.ensureVisible(find.text('Save template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save template'));
      await tester.pumpAndSettle();

      final put = api.puts.single;
      expect(put.path, Endpoints.companyTemplate);
      expect(put.params, {'id': 'co-asia'});
      expect(put.data['headerText'], 'NEW HDR');
      expect(find.text('All changes saved.'), findsOneWidget);

      // The following category now previews the new company header. (The company
      // preview samples its first category, so the list row is the first match.)
      await tester.tap(find.text('Asiacell 5000').first);
      await tester.pumpAndSettle();
      expect(find.text('NEW HDR'), findsOneWidget);
    });

    testWidgets('own template → back to the company, after a confirm', (tester) async {
      final api = await _pump(tester);
      await tester.tap(find.text('Asiacell 10000'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Changes to Asiacell's template don't affect it"), findsOneWidget);

      await tester.tap(find.text('Back to the company template'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(api.puts, isEmpty, reason: 'cancel changes nothing');

      await tester.tap(find.text('Back to the company template'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Change'));
      await tester.pumpAndSettle();

      expect(api.puts.single.path, Endpoints.definitionTemplate);
      expect(api.puts.single.data, {'followsCompany': true});
      expect(find.text('Customise this category'), findsOneWidget);
      expect(find.text('ASIACELL HDR'), findsOneWidget);
    });

    testWidgets('"make it the company template" moves what is on screen to the company', (tester) async {
      final api = await _pump(tester);
      await tester.tap(find.text('Asiacell 10000'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make it the company template'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(2)'), findsOneWidget, reason: 'the other follower plus this one');
      await tester.tap(find.widgetWithText(FilledButton, 'Change'));
      await tester.pumpAndSettle();

      expect(api.puts.map((p) => p.path), [Endpoints.companyTemplate, Endpoints.definitionTemplate]);
      expect(api.puts[0].data['headerText'], 'TEN OWN');
      expect(api.puts[1].data, {'followsCompany': true});
      expect(find.text('Follows company'), findsNWidgets(2));
    });

    testWidgets('a category with no company edits its own template as before', (tester) async {
      final api = await _pump(tester);
      await tester.tap(find.text('iTunes 10'));
      await tester.pumpAndSettle();
      expect(find.text('This category has no company, so its template is its own.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'IT HDR');
      await tester.pump();
      await tester.ensureVisible(find.text('Save template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save template'));
      await tester.pumpAndSettle();
      expect(api.puts.single.path, Endpoints.definitionTemplate);
      expect(api.puts.single.params, {'id': 'd-it'});
      expect(api.puts.single.data['template']['headerText'], 'IT HDR');
      expect(api.puts.single.data.containsKey('followsCompany'), isFalse);
    });

    testWidgets('phone width: the dropdown lists the company template and its categories', (tester) async {
      await _pump(tester, size: const Size(420, 900));
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Asiacell · Company template').last, findsOneWidget);
      await tester.tap(find.text('Asiacell · Company template').last);
      await tester.pumpAndSettle();
      expect(find.text("Applies to 1 of the company's categories · 1 have their own template"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // Pictures for review, with the real fonts: RENDER_GOLDENS=1 flutter test --update-goldens <this file>
  group('pictures for review', () {
    setUpAll(() async {
      Future<void> load(String family, String dir, List<String> files) async {
        final loader = FontLoader(family);
        for (final f in files) {
          loader.addFont(Future.value(ByteData.sublistView(await File('$dir/$f').readAsBytes())));
        }
        await loader.load();
      }

      await load('CodecPro', 'assets/fonts', [
        'CodecPro-Heavy.ttf', 'CodecPro-ExtraBold.ttf', 'CodecPro-Bold.ttf',
        'CodecPro-Regular.ttf', 'CodecPro-News.ttf',
      ]);
      await load('JetBrainsMono', 'assets/fonts/mono', [
        'JetBrainsMono-Regular.ttf', 'JetBrainsMono-Medium.ttf',
        'JetBrainsMono-SemiBold.ttf', 'JetBrainsMono-Bold.ttf',
      ]);
    });

    for (final (name, tap) in [
      ('vt_company', 'Asiacell'),
      ('vt_following', 'Asiacell 5000'),
      ('vt_own', 'Asiacell 10000'),
    ]) {
      testWidgets('picture: $name', (tester) async {
        await _pump(tester, size: const Size(1400, 1100), locale: const Locale('ar'));
        await tester.tap(find.text(tap).first);
        await tester.pumpAndSettle();
        await expectLater(find.byType(VoucherTemplatesPage), matchesGoldenFile('goldens/$name.png'));
      }, skip: !Platform.environment.containsKey('RENDER_GOLDENS'));
    }
  });
}
