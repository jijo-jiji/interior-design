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
