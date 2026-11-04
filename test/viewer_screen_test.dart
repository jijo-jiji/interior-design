// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/screens/viewer_screen.dart';
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
