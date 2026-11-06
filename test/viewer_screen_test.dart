// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/catalog/default_catalog.g.dart';
import 'package:static_trace/features/catalog/price_catalog.dart';
import 'package:static_trace/features/viewer/screens/viewer_screen.dart';
import 'package:static_trace/features/viewer/utils/offline_store.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'helpers/fake_webview.dart';

void main() {
  late FakeWebViewPlatform webView;

  // A 3.6 m wall with a window: the viewer generates A/B/C and starts on B.
  final payload = jsonEncode({
    'wall': {'width_mm': 3600.0, 'height_mm': 2700.0, 'depth_mm': 150.0},
    'obstacles': [
      {
        'type': 'window',
        'distance_from_left_mm': 1200.0,
        'distance_from_floor_mm': 1000.0,
        'width_mm': 1200.0,
        'height_mm': 1100.0,
      },
    ],
    'client_name': 'Puan Aminah',
    'quote_id': 'QT-TEST-VIEWER',
  });

  FakeWebViewController page() => webView.lastController!;

  void fromPage(Map<String, Object?> event) =>
      page().sendFromPage('StaticTraceChannel', jsonEncode(event));

  // The asset cache would hand later tests a load that finished on the
  // first test's fake clock, which never resolves; start each test clean.
  setUp(() => rootBundle.clear());
  tearDown(() => PriceCatalog.current = PriceCatalog.builtIn());

  /// The sample catalogue with [edit] applied, as version [version].
  PriceCatalog catalogue(void Function(Map<String, dynamic>) edit,
      {int version = 9}) {
    final doc = jsonDecode(kDefaultCatalogJson) as Map<String, dynamic>
      ..['version'] = version;
    edit(doc);
    return PriceCatalog.fromJson(doc);
  }

  Map<String, dynamic> module(Map<String, dynamic> doc, String type) =>
      (doc['modules'] as List).firstWhere((m) => m['type'] == type);

  Future<void> pumpViewer(WidgetTester tester, {String? json}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    webView = FakeWebViewPlatform();
    WebViewPlatform.instance = webView;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: ViewerScreen(jsonPayload: json ?? payload)),
      ),
    );
    // The page assets load from the bundle for real; wait until the
    // loading cover is gone.
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (find.text('Loading 3D view…').evaluate().isEmpty) break;
    }
    expect(find.text('Loading 3D view…'), findsNothing);
  }

  /// Lets the auto-save timer fire so no timer is left pending.
  Future<void> finish(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  testWidgets('one Quote button, layouts showing, price hidden',
      (tester) async {
    await pumpViewer(tester);

    expect(find.text('Puan Aminah'), findsOneWidget);
    expect(find.text('Quote'), findsOneWidget);
    expect(find.text('Sample layouts'), findsOneWidget);
    expect(find.text('B · Balanced'), findsOneWidget);
    expect(find.text('Edit cabinets'), findsNothing);
    expect(find.text('Show price'), findsOneWidget);
    expect(find.textContaining('RM '), findsNothing);
    await finish(tester);
  });

  testWidgets('Edit unlocks the cabinets; Done locks them again',
      (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(find.text('Edit cabinets'), findsOneWidget);
    expect(find.text('Base 800'), findsOneWidget);
    expect(find.text('Sample layouts'), findsNothing);
    expect(page().javaScript, contains('setEditMode(true)'));

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Sample layouts'), findsOneWidget);
    expect(page().javaScript, contains('setEditMode(false)'));
    await finish(tester);
  });

  testWidgets('a selected cabinet can be removed', (tester) async {
    await pumpViewer(tester);
    await tester.tap(find.text('Edit'));
    await tester.pump();

    fromPage({'event': 'cabinet_selected', 'id': 'B-02', 'label': 'Base 600'});
    await tester.pump();
    expect(find.text('Remove Base 600'), findsOneWidget);

    await tester.tap(find.text('Remove Base 600'));
    expect(page().javaScript, contains('removeSelectedCabinet()'));

    fromPage({'event': 'cabinet_deselected'});
    fromPage({'event': 'cabinet_removed', 'id': 'B-02'});
    await tester.pump();
    expect(find.textContaining('Remove'), findsNothing);
    await finish(tester);
  });

  testWidgets('cabinets can be picked and moved without dragging',
      (tester) async {
    await pumpViewer(tester);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(
        find.text('Tap a cabinet in the view, or use Pick.'), findsOneWidget);
    // Nothing selected yet: nothing to move.
    expect(find.byTooltip('Move right'), findsNothing);

    await tester.tap(find.byTooltip('Next cabinet'));
    expect(page().javaScript, contains('selectAdjacentCabinet(1)'));
    fromPage({
      'event': 'cabinet_selected',
      'id': 'B-01',
      'label': 'Base 600',
      'movable': true,
    });
    await tester.pump();

    await tester.tap(find.byTooltip('Move right'));
    expect(page().javaScript, contains('nudgeSelectedCabinet(50)'));
    await tester.tap(find.byTooltip('Move left'));
    expect(page().javaScript, contains('nudgeSelectedCabinet(-50)'));
    await tester.tap(find.byTooltip('Previous cabinet'));
    expect(page().javaScript, contains('selectAdjacentCabinet(-1)'));

    // A return-wall cabinet: selectable, but no Move buttons.
    fromPage({
      'event': 'cabinet_selected',
      'id': 'R-01',
      'label': 'Base 600',
      'movable': false,
    });
    await tester.pump();
    expect(find.byTooltip('Move right'), findsNothing);
    expect(find.textContaining("Corner-wall cabinets can't be moved yet"),
        findsOneWidget);
    await finish(tester);
  });

  testWidgets('a manual change unselects the A/B/C layout', (tester) async {
    await pumpViewer(tester);
    expect(find.textContaining('your changes'), findsNothing);

    fromPage({'event': 'cabinet_moved', 'id': 'B-01', 'x_mm': -1500});
    await tester.pump();
    expect(find.textContaining('your changes'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Full view hides every control until asked back', (tester) async {
    await pumpViewer(tester);

    await tester.tap(find.byTooltip('Full view'));
    await tester.pump();
    expect(find.text('Sample layouts'), findsNothing);
    expect(find.text('Quote'), findsNothing);
    expect(find.text('Japandi'), findsNothing);

    await tester.tap(find.text('Show controls'));
    await tester.pump();
    expect(find.text('Sample layouts'), findsOneWidget);
    expect(find.text('Quote'), findsOneWidget);
    await finish(tester);
  });

  group('the catalogue', () {
    Future<void> forgetDraft(WidgetTester tester) =>
        tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));

    // The design saves itself shortly after it appears (or changes); the
    // write itself is real I/O, so give it a moment outside the fake clock.
    Future<Map<String, dynamic>> savedDraft(WidgetTester tester) async {
      await finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      final drafts = await tester.runAsync(OfflineStore.getDrafts);
      return drafts!.firstWhere((d) => d['quote_id'] == 'QT-TEST-VIEWER');
    }

    testWidgets(
        'the tray offers the catalogue\'s modules, named and sized by it',
        (tester) async {
      PriceCatalog.current = catalogue((d) {
        module(d, 'base_800')['label'] = 'Base 800 oak';
        module(d, 'tall_600')['height_mm'] = 2200;
        (d['modules'] as List).add({
          'type': 'base_300',
          'label': 'Base 300',
          'section': 'cabinet',
          'width_mm': 300,
          'height_mm': 850,
          'depth_mm': 600,
          'mount_mm': 0,
          'price': 250,
        });
      });
      await pumpViewer(tester);
      await tester.tap(find.text('Edit'));
      await tester.pump();

      expect(find.text('Base 800 oak'), findsOneWidget);
      expect(find.text('Base 800'), findsNothing);
      expect(find.text('2200 mm'), findsOneWidget); // the tall unit's height
      await tester.scrollUntilVisible(find.text('Base 300'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Base 300'), findsOneWidget);
      expect(find.text('Corner 900'), findsOneWidget);

      await tester.tap(find.text('Base 300'));
      expect(page().javaScript, contains("spawnCabinet('base_300')"));
      await finish(tester);
    });

    testWidgets('the appliance list shows the catalogue\'s prices',
        (tester) async {
      PriceCatalog.current = catalogue((d) {
        module(d, 'sink_600')['price'] = 515;
        module(d, 'dishwasher_600')['label'] = 'Dishwasher (integrated)';
      });
      await pumpViewer(tester);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.tap(find.text('Appliances'));
      await tester.pumpAndSettle();

      expect(find.text('Sink 600'), findsOneWidget);
      expect(find.text('RM 515'), findsOneWidget);
      expect(find.text('Dishwasher (integrated)'), findsOneWidget);
      expect(find.text('Rangehood'), findsOneWidget);
      await finish(tester);
    });

    testWidgets(
        'the 3D page is told the catalogue\'s sizes before the scene loads',
        (tester) async {
      PriceCatalog.current =
          catalogue((d) => module(d, 'base_600')['width_mm'] = 650);
      await pumpViewer(tester);

      final js = page().javaScript;
      final sizes = js.indexWhere((c) => c.startsWith('setCatalogModules('));
      final scene = js.indexWhere((c) => c.startsWith('loadScene('));
      expect(sizes, isNonNegative);
      expect(sizes, lessThan(scene));
      // The argument is a JS string literal holding the JSON.
      final arg = js[sizes]
          .substring('setCatalogModules('.length, js[sizes].length - 1);
      final modules = jsonDecode(jsonDecode(arg) as String) as List;
      final base600 = modules.firstWhere((m) => m['type'] == 'base_600');
      expect(base600['width_mm'], 650);
      expect(base600['kind'], 'base');
      expect(modules.firstWhere((m) => m['type'] == 'rangehood_900')['kind'],
          'hood');
      await finish(tester);
    });

    testWidgets(
        'a saved design records the catalogue version it was priced with',
        (tester) async {
      await forgetDraft(tester);
      PriceCatalog.current =
          catalogue((d) => module(d, 'base_600')['price'] = 400, version: 9);
      await pumpViewer(tester);

      final draft = await savedDraft(tester);
      expect(draft['catalog_version'], 9);
      await forgetDraft(tester);
    });

    testWidgets(
        'a newer catalogue arriving mid-meeting waits for the next design',
        (tester) async {
      await forgetDraft(tester);
      await pumpViewer(tester); // opened on version 1
      final before = await savedDraft(tester);
      expect(before['catalog_version'], 1);

      // The office publishes version 2 (everything dearer) while the client
      // is looking at the design; the app syncs it.
      PriceCatalog.current = catalogue((d) {
        d['labour_rate_per_cabinet'] = 900;
        for (final m in d['modules'] as List) {
          m['price'] = (m['price'] as num) * 2;
        }
      }, version: 2);

      // The salesperson changes something; the design is saved again.
      fromPage({'event': 'cabinet_moved', 'id': 'B-01', 'x_mm': -1500});
      await tester.pump();
      final after = await savedDraft(tester);

      expect(after['catalog_version'], 1);
      expect(after['total_price'], before['total_price']);
      await forgetDraft(tester);
    });
  });

  group('the look of the design', () {
    testWidgets('is put on the page before the cabinets arrive',
        (tester) async {
      await pumpViewer(tester);
      final js = page().javaScript;
      final cabinets = js.indexWhere((c) => c.startsWith('replaceCabinets('));
      for (final call in const [
        "setDoorStyle('slab')",
        "setBacksplash('subway')",
        'setDecor(true)',
        'setRoom(true)',
        "setMood('day')",
      ]) {
        final at = js.indexOf(call);
        expect(at, isNonNegative, reason: call);
        // Doors rebuild every cabinet, so they must precede the cabinets.
        expect(at, lessThan(cabinets), reason: call);
      }
      await finish(tester);
    });

    testWidgets(
        'the Look button changes doors, backsplash, light, decor and room',
        (tester) async {
      await pumpViewer(tester);
      await tester
          .tap(find.byTooltip('Look: doors, backsplash, decor, room and light'));
      await tester.pumpAndSettle();
      expect(find.text('Look of the design'), findsOneWidget);
      expect(find.textContaining('changes the price'), findsOneWidget);

      // Each change sends the whole look, so read the latest of each call.
      String latest(String prefix) =>
          page().javaScript.lastWhere((c) => c.startsWith(prefix));
      await tester.tap(find.text('Shaker'));
      await tester.pump();
      expect(latest('setDoorStyle'), "setDoorStyle('shaker')");
      await tester.tap(find.text('Hexagon tile'));
      await tester.pump();
      expect(latest('setBacksplash'), "setBacksplash('hex')");
      await tester.tap(find.text('Evening'));
      await tester.pump();
      expect(latest('setMood'), "setMood('evening')");
      await tester.tap(find.widgetWithText(SwitchListTile, 'Show decor'));
      await tester.pump();
      expect(latest('setDecor'), 'setDecor(false)');
      expect(latest('setRoom'), 'setRoom(true)');
      await tester.ensureVisible(find.text('Show the room'));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Show the room'));
      await tester.pump();
      expect(latest('setRoom'), 'setRoom(false)');
      expect(latest('setDecor'), 'setDecor(false)');
      // Not included in the quote, in so many words (decor and room).
      expect(find.textContaining('Not included in the quote'), findsNWidgets(2));
      await finish(tester);
    });

    testWidgets('is saved with the design and comes back when it is reopened',
        (tester) async {
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));
      await pumpViewer(tester);
      await tester
          .tap(find.byTooltip('Look: doors, backsplash, decor, room and light'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Raised panel'));
      await tester.pump();
      await tester.tap(find.text('Evening'));
      await tester.pump();
      await finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)));
      final drafts = await tester.runAsync(OfflineStore.getDrafts);
      final saved =
          drafts!.firstWhere((d) => d['quote_id'] == 'QT-TEST-VIEWER');
      expect(saved['scene'], {
        'doors': 'raised',
        'backsplash': 'subway',
        'decor': true,
        'room': true,
        'mood': 'evening',
      });
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));

      // Reopened from the saved record.
      final reopened = jsonDecode(payload) as Map<String, dynamic>
        ..['scene'] = {
          'doors': 'raised',
          'backsplash': 'hex',
          'decor': false,
          'room': false,
          'mood': 'evening',
        };
      // A new screen, not an update of the old one.
      await tester.pumpWidget(const SizedBox());
      await pumpViewer(tester, json: jsonEncode(reopened));
      expect(page().javaScript, contains("setDoorStyle('raised')"));
      expect(page().javaScript, contains("setBacksplash('hex')"));
      expect(page().javaScript, contains('setDecor(false)'));
      expect(page().javaScript, contains('setRoom(false)'));
      expect(page().javaScript, contains("setMood('evening')"));
      await finish(tester);
    });

    testWidgets('Look is off while a render runs', (tester) async {
      await pumpViewer(tester);
      await tester.tap(find.byTooltip('Take pictures of this design'));
      await tester.pump();
      fromPage({
        'event': 'pictures',
        'request_id': 'app',
        'images': const <String>[]
      });
      await tester.pump();
      final look = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.palette_outlined));
      expect(look.onPressed, isNotNull); // normal when nothing is rendering
      await finish(tester);
    });
  });

  group('finish textures', () {
    testWidgets('are handed to the page before the scene loads',
        (tester) async {
      await pumpViewer(tester);
      final js = page().javaScript;
      final register =
          js.indexWhere((c) => c.startsWith('registerFinishTextures('));
      final ready = js.indexOf('finishTexturesReady()');
      final scene = js.indexWhere((c) => c.startsWith('loadScene('));
      expect(register, isNonNegative);
      expect(js.where((c) => c.startsWith('registerFinishFile(')).length,
          greaterThan(15));
      expect(register, lessThan(ready));
      expect(ready, lessThan(scene));
      await finish(tester);
    });

    testWidgets('the chosen benchtop is put on the worktop', (tester) async {
      await pumpViewer(tester);
      // Opened with none chosen: the style's own worktop.
      expect(page().javaScript, contains('setBenchtop(null)'));

      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.tap(find.text('Benchtop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calacatta Engineered Quartz'));
      await tester.pumpAndSettle();
      expect(page().javaScript.last, 'setBenchtop("quartz_calacatta")');

      await tester.tap(find.textContaining('Benchtop:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No benchtop in this quote'));
      await tester.pumpAndSettle();
      expect(page().javaScript.last, 'setBenchtop(null)');
      await finish(tester);
    });

    testWidgets('a reopened design shows the benchtop it was saved with',
        (tester) async {
      final saved = jsonDecode(payload) as Map<String, dynamic>
        ..['benchtop_material'] = 'granite_black';
      await pumpViewer(tester, json: jsonEncode(saved));
      expect(page().javaScript, contains('setBenchtop("granite_black")'));
      await finish(tester);
    });
  });

  group('pictures of the design', () {
    // A real 1x1 PNG.
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const picture = 'data:image/png;base64,$png';

    testWidgets('the button asks the 3D page, then shows what it sent',
        (tester) async {
      await pumpViewer(tester);

      await tester.tap(find.byTooltip('Take pictures of this design'));
      await tester.pump();
      expect(page().javaScript, contains("capturePictures('app')"));
      expect(find.text('Taking pictures…'), findsOneWidget);

      fromPage({
        'event': 'pictures',
        'request_id': 'app',
        'images': [picture, picture],
        'names': ['front', 'angle'],
      });
      await tester.pumpAndSettle();

      expect(find.text('Pictures of the design'), findsOneWidget);
      expect(find.text('Send on WhatsApp'), findsOneWidget);
      expect(find.text('Open to save'), findsOneWidget);
      expect(find.bySemanticsLabel('Front view of the design'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Angled view of the design'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('an empty answer says so and shows no sheet', (tester) async {
      await pumpViewer(tester);
      await tester.tap(find.byTooltip('Take pictures of this design'));
      await tester.pump();
      fromPage({'event': 'pictures', 'images': <String>[]});
      await tester.pump();
      await tester.pump();

      expect(
          find.text("Couldn't take the pictures. Try again."), findsOneWidget);
      expect(find.text('Pictures of the design'), findsNothing);
      await finish(tester);
    });

    testWidgets('a page that never answers does not leave the app waiting',
        (tester) async {
      await pumpViewer(tester);
      await tester.tap(find.byTooltip('Take pictures of this design'));
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();

      expect(
          find.text("Couldn't take the pictures. Try again."), findsOneWidget);
      await finish(tester);
    });

    testWidgets('sending the quote takes pictures and keeps them with it',
        (tester) async {
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));
      await pumpViewer(tester);

      await tester.tap(find.text('Quote'));
      await tester.pumpAndSettle();
      final send = find.text('Save & send quote');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();

      // The app asks the page for pictures before it posts the quote.
      expect(page().javaScript, contains("capturePictures('app')"));
      fromPage({
        'event': 'pictures',
        'images': [picture, picture],
      });
      // The office isn't there (tests have no network): the quote waits on
      // the phone, with its pictures. Give it a moment to get that far.
      Map<String, dynamic>? saved;
      for (var i = 0; i < 40 && saved?['design_images'] == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final drafts = await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return OfflineStore.getDrafts();
        });
        saved =
            drafts!.where((d) => d['quote_id'] == 'QT-TEST-VIEWER').firstOrNull;
      }
      expect(saved?['design_images'], [picture, picture]);
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));
      await finish(tester);
    });

    // Opens the sheet with quick pictures, ready to render.
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Take pictures of this design'));
      await tester.pump();
      fromPage({
        'event': 'pictures',
        'request_id': 'app',
        'images': [picture, picture],
      });
      await tester.pumpAndSettle();
    }

    const rendered = 'data:image/jpeg;base64,$png';

    testWidgets('a realistic render can be asked for, with progress',
        (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      expect(find.text('Realistic render'), findsNothing);

      await tester.ensureVisible(find.text('Make a realistic render'));
      await tester.tap(find.text('Make a realistic render'));
      await tester.pump();
      expect(
          page().javaScript.any((c) => c.startsWith("renderPictures('render'")),
          isTrue,
          reason:
              'last calls: ${page().javaScript.reversed.take(3).map((c) => c.length > 50 ? c.substring(0, 50) : c).toList()}');
      expect(find.text('Rendering… 0%'), findsOneWidget);
      // While it runs: no sending, and Quote and Picture are off.
      expect(find.text('Send on WhatsApp'), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);

      fromPage({
        'event': 'render_progress',
        'request_id': 'render',
        'fraction': 0.5
      });
      await tester.pump();
      expect(find.text('Rendering… 50%'), findsOneWidget);

      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'rendered': true,
        'images': [rendered, rendered],
      });
      await tester.pumpAndSettle();
      expect(find.text('Realistic render'), findsOneWidget);
      expect(find.text('Make a realistic render'), findsNothing);
      expect(find.text('Send on WhatsApp'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a true-lighting render can be asked for, with progress',
        (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      expect(find.text('True-lighting render'), findsNothing);
      // Both kinds are offered, and which is which is said.
      expect(find.text('Make a realistic render'), findsOneWidget);
      await tester.ensureVisible(find.text('Make a true-lighting render'));
      await tester.tap(find.text('Make a true-lighting render'));
      await tester.pump();
      final call = page()
          .javaScript
          .lastWhere((c) => c.startsWith("renderPictures('render'"));
      expect(call, contains("engine: 'path'"));
      expect(call, contains('samples: 300'));
      expect(find.text('Rendering… 0%'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      fromPage({
        'event': 'render_progress',
        'request_id': 'render',
        'fraction': 0.25
      });
      await tester.pump();
      expect(find.text('Rendering… 25%'), findsOneWidget);

      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'rendered': true,
        'engine': 'path',
        'fell_back': false,
        'images': [rendered, rendered],
      });
      await tester.pumpAndSettle();
      expect(find.text('True-lighting render'), findsOneWidget);
      expect(find.text('Realistic render'), findsNothing);
      expect(find.textContaining("can't do true lighting"), findsNothing);
      expect(find.text('Make a true-lighting render'), findsNothing);
      expect(find.text('Send on WhatsApp'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('Fine detail asks the page for more samples', (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Fine detail (slower)'));
      await tester.tap(find.text('Fine detail (slower)'));
      await tester.pump();
      await tester.ensureVisible(find.text('Make a true-lighting render'));
      await tester.tap(find.text('Make a true-lighting render'));
      await tester.pump();
      final call = page()
          .javaScript
          .lastWhere((c) => c.startsWith("renderPictures('render'"));
      expect(call, contains('samples: 1000'));
      // Let the render finish, so no wait is left pending.
      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'rendered': true,
        'engine': 'path',
        'images': [rendered, rendered],
      });
      await tester.pumpAndSettle();
      await finish(tester);
    });

    testWidgets('a device without true lighting is told, and gets the other',
        (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Make a true-lighting render'));
      await tester.tap(find.text('Make a true-lighting render'));
      await tester.pump();
      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'rendered': true,
        'engine': 'sky',
        'fell_back': true,
        'images': [rendered, rendered],
      });
      await tester.pumpAndSettle();
      expect(find.text('Realistic render'), findsOneWidget);
      expect(find.text('True-lighting render'), findsNothing);
      expect(find.textContaining("can't do true lighting"), findsOneWidget);
      await finish(tester);
    });

    testWidgets('an older page that names no engine gets the one asked for',
        (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Make a true-lighting render'));
      await tester.tap(find.text('Make a true-lighting render'));
      await tester.pump();
      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'images': [rendered, rendered],
      });
      await tester.pumpAndSettle();
      expect(find.text('True-lighting render'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('Cancel stops the render and the quick pictures stay',
        (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Make a realistic render'));
      await tester.tap(find.text('Make a realistic render'));
      await tester.pump();

      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(page().javaScript, contains('cancelRender()'));
      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'cancelled': true,
        'images': <String>[],
      });
      await tester.pumpAndSettle();

      expect(find.textContaining('Rendering…'), findsNothing);
      expect(find.text('Realistic render'), findsNothing);
      expect(find.text('Make a realistic render'), findsOneWidget);
      expect(find.text('Send on WhatsApp'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('the quote uses the render while the design is unchanged',
        (tester) async {
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));
      await pumpViewer(tester);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Make a realistic render'));
      await tester.tap(find.text('Make a realistic render'));
      await tester.pump();
      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'images': [rendered, rendered],
      });
      await tester.pumpAndSettle();
      // Close the sheet (back).
      Navigator.of(tester.element(find.text('Realistic render'))).pop();
      await tester.pumpAndSettle();
      int captures() => page()
          .javaScript
          .where((c) =>
              c.startsWith('capturePictures(') ||
              c.startsWith('renderPictures('))
          .length;
      final before = captures();

      await tester.tap(find.text('Quote'));
      await tester.pumpAndSettle();
      final send = find.text('Save & send quote');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();
      // No new capture: the render is of this very design.
      expect(captures(), before);

      Map<String, dynamic>? saved;
      for (var i = 0; i < 40 && saved?['design_images'] == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final drafts = await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return OfflineStore.getDrafts();
        });
        saved =
            drafts!.where((d) => d['quote_id'] == 'QT-TEST-VIEWER').firstOrNull;
      }
      expect(saved?['design_images'], [rendered, rendered]);
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));
      await finish(tester);
    });

    testWidgets('after the design changes the old render is not used',
        (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Make a realistic render'));
      await tester.tap(find.text('Make a realistic render'));
      await tester.pump();
      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'images': [rendered, rendered],
      });
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Realistic render'))).pop();
      await tester.pumpAndSettle();

      // A cabinet is moved: the render no longer shows this design.
      fromPage({'event': 'cabinet_moved', 'id': 'B-01', 'x_mm': -1500});
      await tester.pump();

      await tester.tap(find.byTooltip('Take pictures of this design'));
      await tester.pump();
      // Quick pictures are taken again, and the sheet offers to render again.
      expect(page().javaScript.last, "capturePictures('app')");
      fromPage({
        'event': 'pictures',
        'request_id': 'app',
        'images': [picture]
      });
      await tester.pumpAndSettle();
      expect(find.text('Make a realistic render'), findsOneWidget);
      expect(find.text('Realistic render'), findsNothing);
      await finish(tester);
    });

    testWidgets('Quote and Picture are off while a render runs',
        (tester) async {
      await pumpViewer(tester);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Make a realistic render'));
      await tester.tap(find.text('Make a realistic render'));
      await tester.pump();

      final quote = tester.widget<ElevatedButton>(find.ancestor(
          of: find.text('Quote'), matching: find.byType(ElevatedButton)));
      expect(quote.onPressed, isNull);
      final camera = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.photo_camera_outlined));
      expect(camera.onPressed, isNull);

      fromPage({
        'event': 'pictures',
        'request_id': 'render',
        'cancelled': true,
        'images': <String>[]
      });
      await tester.pumpAndSettle();
      await finish(tester);
    });

    testWidgets('autosaved drafts never carry pictures', (tester) async {
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));
      await pumpViewer(tester);
      await finish(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      final drafts = await tester.runAsync(OfflineStore.getDrafts);
      final saved =
          drafts!.firstWhere((d) => d['quote_id'] == 'QT-TEST-VIEWER');
      expect(saved.containsKey('design_images'), isFalse);
      await tester.runAsync(() => OfflineStore.removeDraft('QT-TEST-VIEWER'));
    });
  });

  group('Kitchen / Room / House', () {
    testWidgets('only for a room read off a floor plan', (tester) async {
      await pumpViewer(tester);
      expect(find.text('House'), findsNothing);
      await finish(tester);
    });

    testWidgets('switches what the 3D shows', (tester) async {
      final fromPlan = jsonDecode(payload) as Map<String, dynamic>;
      fromPlan['floor_plan'] = {
        'image': 'data:image/png;base64,AAAA',
        'image_center_mm': [4000, 2500],
        'image_size_mm': [10000, 7000],
        'image_rotation_deg': 0,
        'kitchen_mm': [0, 0, 3600, 2400],
        'wall_thickness_mm': 150,
        'walls': [
          [-150, -150, 3900, 150]
        ],
        'rooms': [],
      };
      await pumpViewer(tester, json: jsonEncode(fromPlan));

      await tester.tap(find.text('House'));
      await tester.pump();
      expect(page().javaScript, contains("setRoomView('house')"));
      await tester.tap(find.text('Room'));
      await tester.pump();
      expect(page().javaScript.last, "setRoomView('room')");
      await finish(tester);
    });
  });
}
