import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/pos/presentation/pos_tiles.dart';

/// PROD-025 — the client's example (22 Nov): on the POS home, a company or card-type tile is its
/// picture, edge to edge, with only the name under it. No price, no "available" line, no Sell button
/// on the tile; a tap opens the sale sheet, which shows the price before anything is sold.
void main() {
  group('the tile', () {
    testWidgets('shows the name and nothing else; a tap goes through', (tester) async {
      var taps = 0;
      await _pumpGrid(tester, [
        PosPictureTile(
          name: 'Asiacell 5000 IQD',
          imageUrl: null,
          decodeWidth: 120,
          fallback: const ColoredBox(color: Colors.red),
          onTap: () => taps++,
        ),
      ]);
      expect(find.text('Asiacell 5000 IQD'), findsOneWidget);
      // Exactly one text on the tile: the name.
      expect(find.byType(Text), findsOneWidget);
      await tester.tap(find.byType(PosPictureTile));
      expect(taps, 1);
    });

    testWidgets('no picture → the fallback fills the picture area, edge to edge', (tester) async {
      await _pumpGrid(tester, [
        PosPictureTile(
          name: 'KOREK',
          imageUrl: '  ',
          decodeWidth: 120,
          fallback: const PosLetterArt(name: 'KOREK'),
          onTap: () {},
        ),
      ]);
      final tile = tester.getRect(find.byType(PosPictureTile));
      final art = tester.getRect(find.byType(PosLetterArt));
      expect(art.width, tile.width, reason: 'the picture spans the full tile width');
      expect(art.top, tile.top);
      expect(tile.height - art.height, kPosTileBandHeight, reason: 'only the name band sits under it');
      expect(find.text('K'), findsOneWidget);
    });

    testWidgets('balance too low → says so and refuses the tap (UX-53)', (tester) async {
      var taps = 0;
      await _pumpGrid(tester, [
        PosPictureTile(
          name: 'Zain 10000 IQD',
          imageUrl: null,
          decodeWidth: 120,
          fallback: const ColoredBox(color: Colors.blue),
          notice: 'الرصيد لا يكفي',
          onTap: null,
        ),
      ]);
      expect(find.text('الرصيد لا يكفي'), findsOneWidget);
      await tester.tap(find.byType(PosPictureTile), warnIfMissed: false);
      expect(taps, 0);
    });

    // 23 Nov (the owner): pictures were cut by the 4:3 frame. Now a picture is never cut — drawn whole.
    Future<Rect> pictureRect(WidgetTester tester, String url, Uint8List bytes) async {
      debugNetworkImageHttpClientProvider = () => _FakeHttpClient({url: bytes});
      await _pumpGrid(tester, [
        PosPictureTile(
          name: 'X',
          imageUrl: url,
          decodeWidth: 120,
          fallback: const ColoredBox(color: Colors.red),
          onTap: () {},
        ),
      ]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      debugNetworkImageHttpClientProvider = null;
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image, isNotNull, reason: 'the picture loaded');
      expect(raw.fit, BoxFit.contain, reason: 'whole, never cut');
      // Where the picture's pixels land inside the frame (contain keeps its shape, centred).
      final box = tester.getRect(find.byType(RawImage));
      final w = raw.image!.width.toDouble(), h = raw.image!.height.toDouble();
      final scale = (box.width / w) < (box.height / h) ? box.width / w : box.height / h;
      return Rect.fromCenter(center: box.center, width: w * scale, height: h * scale);
    }

    testWidgets('a 4:3 picture fills the frame edge to edge', (tester) async {
      final drawn = await pictureRect(tester, 'https://x/43.jpg', _art(0xE53935, '5000', 0xFFFFFF, w: 800, h: 600));
      final tile = tester.getRect(find.byType(PosPictureTile));
      expect(drawn.width, closeTo(tile.width, 0.5));
      expect(drawn.height, closeTo(tile.height - kPosTileBandHeight, 0.5));
      expect(drawn.top, closeTo(tile.top, 0.5));
    });

    testWidgets('a wide picture (2:1) shows whole: full width, centred, nothing cut', (tester) async {
      final drawn = await pictureRect(tester, 'https://x/wide.jpg', _art(0x1565C0, 'KOREK', 0xFFFFFF, w: 800, h: 400));
      final tile = tester.getRect(find.byType(PosPictureTile));
      final frame = tile.height - kPosTileBandHeight;
      expect(drawn.width, closeTo(tile.width, 0.5));
      expect(drawn.height, closeTo(tile.width / 2, 0.5));
      expect(drawn.center.dy, closeTo(tile.top + frame / 2, 0.5));
    });

    testWidgets('a square logo shows whole: full height, centred', (tester) async {
      final drawn = await pictureRect(tester, 'https://x/sq.png', _art(0xFFFFFF, 'A', 0, w: 400, h: 400));
      final tile = tester.getRect(find.byType(PosPictureTile));
      expect(drawn.height, closeTo(tile.height - kPosTileBandHeight, 0.5));
      expect(drawn.center.dx, closeTo(tile.center.dx, 0.5));
    });
  });

  test('row height: a 4:3 picture plus the name band', () {
    // 3 columns over 320 dp with 12 dp gaps → 98.67 dp tiles → 74 dp picture + 50 dp band.
    expect(posTileExtent(320, 3, spacing: 12), closeTo(124, 0.01));
  });

  test('the card-type tile no longer carries the price, the stock line or a Sell button', () {
    final src = File('lib/features/pos/presentation/pos_home_page.dart').readAsStringSync();
    final start = src.indexOf('class _SkuCard');
    final end = src.indexOf('// ── Voucher sheet');
    expect(start, greaterThan(0));
    final tile = src.substring(start, end);
    expect(tile, contains('PosPictureTile('));
    for (final gone in ['Formatters.iqd', 'BrandCTAButton', 'متاح للبيع', 'posHomeSell']) {
      expect(tile, isNot(contains(gone)), reason: '$gone is back on the tile');
    }
    expect(src, isNot(contains('class _CompanyCard')), reason: 'companies use PosPictureTile too');
    final tiles = File('lib/features/pos/presentation/pos_tiles.dart').readAsStringSync();
    expect(tiles, isNot(contains('BoxFit.cover')), reason: 'a tile picture is never cut (23 Nov)');
  });

  // Picture for review, with the real fonts and made-up artwork:
  //   RENDER_GOLDENS=1 flutter test --update-goldens test/features/pos/pos_picture_tiles_test.dart
  group('picture for review', () {
    setUpAll(_loadFonts);

    testWidgets('picture: pos_tiles', (tester) async {
      final art = <String, Uint8List>{
        // The catalog's 4:3 pictures fill the frame; other shapes show whole (never cut).
        'https://x/korek.png': _art(0x1565C0, 'KOREK', 0xFFFFFF, w: 800, h: 600),
        'https://x/zain.png': _art(0xF2F2F2, 'zain', 0x8A8A8A, w: 400, h: 400),
        'https://x/asiacell.png': _art(0xD81E2C, 'Asiacell', 0xFFFFFF, w: 800, h: 400),
        'https://x/ac5000.png': _art(0xE53935, '5000', 0xFFFFFF, w: 800, h: 600),
        'https://x/ac10000.png': _art(0xB71C1C, '10000', 0xFFFFFF, w: 800, h: 600),
      };
      debugNetworkImageHttpClientProvider = () => _FakeHttpClient(art);
      Widget tile(String name, String? url, {String? notice}) => PosPictureTile(
            name: name,
            imageUrl: url,
            decodeWidth: 120,
            fallback: PosLetterArt(name: name),
            notice: notice,
            onTap: notice == null ? () {} : null,
          );
      await _pumpGrid(tester, [
        tile('KOREK', 'https://x/korek.png'),
        tile('Zain', 'https://x/zain.png'),
        tile('Asiacell', 'https://x/asiacell.png'),
        tile('Asiacell 5000 IQD', 'https://x/ac5000.png'),
        tile('Asiacell 10000 IQD', 'https://x/ac10000.png', notice: 'الرصيد لا يكفي'),
        tile('iTunes', null),
      ], size: const Size(360, 420));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pumpAndSettle();
      // The debug hook must be unset before the test ends (the binding checks it).
      debugNetworkImageHttpClientProvider = null;
      await expectLater(find.byType(GridView), matchesGoldenFile('goldens/pos_tiles.png'));
    }, skip: !Platform.environment.containsKey('RENDER_GOLDENS'));
  });
}

Future<void> _pumpGrid(WidgetTester tester, List<Widget> tiles, {Size size = const Size(360, 640)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildBrandThemes().light,
    debugShowCheckedModeBanner: false,
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: LayoutBuilder(builder: (context, c) {
          const cols = 3, spacing = 12.0;
          final width = c.maxWidth - 40;
          return GridView.count(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            crossAxisCount: cols,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: (width - spacing * (cols - 1)) / cols / posTileExtent(width, cols, spacing: spacing),
            children: tiles,
          );
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Uint8List _art(int bg, String word, int ink, {int w = 400, int h = 300}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8((bg >> 16) & 0xFF, (bg >> 8) & 0xFF, bg & 0xFF));
  // A frame marks the picture's own edges, so a review picture shows whether it was cut.
  img.drawRect(im, x1: 0, y1: 0, x2: w - 1, y2: h - 1,
      color: img.ColorRgb8((ink >> 16) & 0xFF, (ink >> 8) & 0xFF, ink & 0xFF), thickness: 6);
  img.drawString(im, word,
      font: img.arial48,
      x: 40,
      y: h ~/ 2 - 24,
      color: img.ColorRgb8((ink >> 16) & 0xFF, (ink >> 8) & 0xFF, ink & 0xFF));
  return Uint8List.fromList(img.encodePng(im));
}

Future<void> _loadFonts() async {
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
}

// ── A tiny fake HTTP client for NetworkImage (debugNetworkImageHttpClientProvider) ──────────────

class _FakeHttpClient implements HttpClient {
  final Map<String, Uint8List> files;
  _FakeHttpClient(this.files);

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(files[url.toString()]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  final Uint8List? bytes;
  _FakeRequest(this.bytes);

  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  final Uint8List? bytes;
  _FakeResponse(this.bytes);

  @override
  int get statusCode => bytes == null ? HttpStatus.notFound : HttpStatus.ok;

  @override
  int get contentLength => bytes?.length ?? 0;

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable([?bytes])
          .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
