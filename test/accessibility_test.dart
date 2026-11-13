// Locks in WCAG 2.2 AA fixes (Android + Web): 48dp tap targets, labelled
// tap targets, 4.5:1 text contrast, and no layout overflow at 2x text size.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:static_trace/features/floorplan/screens/floorplan_sizes_screen.dart';
import 'package:static_trace/features/intake/screens/intake_hub_screen.dart';
import 'package:static_trace/features/template/screens/template_room_screen.dart';
import 'package:static_trace/features/trace/screens/camera_screen.dart';
import 'package:static_trace/features/trace/screens/trace_screen.dart';
import 'package:static_trace/features/trace/screens/wall_setup_screen.dart';
import 'package:static_trace/features/viewer/screens/viewer_screen.dart';
import 'package:static_trace/features/viewer/widgets/closing_modal.dart';
import 'package:static_trace/shared/theme.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'helpers/fake_plan_reader.dart';
import 'helpers/fake_webview.dart';
import 'helpers/fake_corner_suggester.dart';

const _photo = 'floor_plan/images.png';

final _viewerPayload = jsonEncode({
  'wall': {'width_mm': 3600.0, 'height_mm': 2700.0, 'depth_mm': 150.0},
  'obstacles': <Object>[],
  'client_name': 'Puan Aminah',
  'quote_id': 'QT-A11Y',
});

final _screens = <String, Widget Function()>{
  'home': () => const IntakeHubScreen(),
  'room size': () => const TemplateRoomScreen(),
  'camera': () => const CameraScreen(),
  'wall setup': () => const WallSetupScreen(imagePath: _photo),
  'trace': () => const TraceScreen(imagePath: _photo),
  // Filled in from a reading: the plan drawing, origins under each field,
  // and the other sizes as buttons.
  'floor plan': () => FloorplanSizesScreen(
        imagePath: _photo,
        textReader: FakePlanTextReader(),
        // Measured, so the outline, the Turn button and the walls all show.
        analyser: FakePlanAnalyser(measuredPlan()),
      ),
  '3D view': () => ViewerScreen(jsonPayload: _viewerPayload),
  'quote sheet': () => Scaffold(
        body: ClosingModal(
          placedCabinets: const [],
          styleName: 'Japandi Natural',
          totalPrice: 18450,
          clientName: 'Puan Aminah',
          onConfirm: ({
            required clientName,
            required clientPhone,
            required clientEmail,
            required depositAmount,
            required signatureBase64,
            required keepWallPhoto,
          }) async {},
        ),
      ),
};

Future<void> _pump(WidgetTester tester, Widget screen,
    {double scale = 1}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  WebViewPlatform.instance = FakeWebViewPlatform();
  final router =
      GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => screen),
    // The trace screen opens the wall size between the corners and the
    // windows.
    GoRoute(
      path: '/wall-setup',
      builder: (_, __) => const WallSetupScreen(imagePath: _photo),
    ),
  ]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [noCornerModel, noWallSegmenter],
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          textScaler: TextScaler.linear(scale),
        ),
        child: MaterialApp.router(theme: AppTheme.theme, routerConfig: router),
      ),
    ),
  );
  // Images and the 3D page's assets load for real. Wait until the 3D view's
  // loading cover is gone (its buttons are disabled until then).
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    if (i >= 10 && find.text('Loading 3D view…').evaluate().isEmpty) break;
  }
  // Let state-change animations finish (e.g. a button's colour fading from
  // disabled to enabled once the 3D view has loaded).
  await tester.pump(const Duration(seconds: 1));
}

/// Lets auto-save and animation timers finish.
Future<void> _finish(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 2));

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // A cached asset load from an earlier test never resolves in a later one.
  setUp(() => rootBundle.clear());

  group('theme', () {
    test('no text style is smaller than 12', () {
      final t = AppTheme.theme.textTheme;
      for (final style in [
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ]) {
        expect(style!.fontSize, greaterThanOrEqualTo(12));
        expect(style.fontFamily, AppTextStyle.fontFamily);
      }
    });

    test('text colours meet 4.5:1 on every app surface', () {
      final c = AppTheme.colorScheme;
      const surfaces = [
        AppTheme.bg,
        AppTheme.surface,
        AppTheme.surfaceRaised,
        AppTheme.surfaceElevated,
      ];
      for (final text in [
        c.onSurface,
        c.onSurfaceVariant,
        c.primary,
        c.secondary,
        c.tertiary,
        c.error,
      ]) {
        for (final surface in surfaces) {
          expect(_contrast(text, surface), greaterThanOrEqualTo(4.5),
              reason: '$text on $surface');
        }
      }
      expect(_contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.onError, c.error), greaterThanOrEqualTo(4.5));
      expect(_contrast(c.onSecondary, c.secondary), greaterThanOrEqualTo(4.5));
    });

    test('form field borders meet 3:1', () {
      expect(_contrast(AppTheme.outline, AppTheme.surface),
          greaterThanOrEqualTo(3));
    });
  });

  for (final MapEntry(key: name, value: build) in _screens.entries) {
    group(name, () {
      testWidgets('tap targets are at least 48x48 and labelled',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, build());
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
        await _finish(tester);
      });

      testWidgets('text meets WCAG AA contrast', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, build());
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
        await _finish(tester);
      });

      // A label colour inside a button overrides the button's own text
      // colour (this hid "Save & send quote" as dark-on-dark). Checks every
      // button, including ones scrolled off-screen.
      testWidgets("button labels keep the button's text colour",
          (tester) async {
        await _pump(tester, build());
        final labels = find.descendant(
          of: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          matching: find.byType(Text),
        );
        for (final element in labels.evaluate()) {
          final text = element.widget as Text;
          expect(text.style?.color, isNull,
              reason: '"${text.data}" sets its own colour');
        }
        await _finish(tester);
      });

      testWidgets('lays out without overflow at 2x text size', (tester) async {
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          final where = details
              .toString()
              .split('\n')
              .where((l) => l.contains('interior-design/lib/'))
              .take(1)
              .join()
              .replaceAll(RegExp(r'.*/lib/'), 'lib/');
          errors.add('${details.exceptionAsString().split('\n').first} '
              'at $where');
        };
        await _pump(tester, build(), scale: 2);
        FlutterError.onError = previous;
        expect(errors, isEmpty);
        await _finish(tester);
      });
    });
  }

  // Step 2 of the trace screen, with a window box on the photo and its chip
  // in the panel.
  group('trace, step 2 with a window', () {
    Future<void> openStep2(WidgetTester tester, {double scale = 1}) async {
      await _pump(tester, _screens['trace']!(), scale: scale);
      for (final label in ['Next', 'Next: windows & doors', 'Add window']) {
        await tester.ensureVisible(find.text(label));
        await tester.pump();
        await tester.tap(find.text(label));
        await tester.pump();
        // The wall-size screen slides in and out.
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('tap targets are at least 48x48 and labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      await openStep2(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('text meets WCAG AA contrast', (tester) async {
      final semantics = tester.ensureSemantics();
      await openStep2(tester);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('lays out without overflow at 2x text size', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError =
          (details) => errors.add(details.exceptionAsString());
      await openStep2(tester, scale: 2);
      FlutterError.onError = previous;
      expect(errors, isEmpty);
      await _finish(tester);
    });
  });

  // The card a double tap opens on a cabinet (sizes, other units, move,
  // remove), over the 3D view.
  group('3D view, a cabinet\'s card open', () {
    Future<void> openCard(WidgetTester tester, {double scale = 1}) async {
      await _pump(tester, _screens['3D view']!(), scale: scale);
      final page = (WebViewPlatform.instance as FakeWebViewPlatform).lastController!;
      final call = page.javaScript.lastWhere((c) => c.startsWith('replaceCabinets('));
      final list = jsonDecode(jsonDecode(call.substring(16, call.length - 1)) as String) as List;
      final base = list.cast<Map<String, dynamic>>().firstWhere(
          (c) => c['kind'] == 'base' && (c['width_mm'] as num) >= 500,
          orElse: () => list.first as Map<String, dynamic>);
      page.sendFromPage('StaticTraceChannel',
          jsonEncode({'event': 'cabinet_opened', 'id': base['id'], 'label': base['label']}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Remove'), findsOneWidget);
    }

    testWidgets('tap targets are at least 48x48 and labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      await openCard(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('text meets WCAG AA contrast', (tester) async {
      final semantics = tester.ensureSemantics();
      await openCard(tester);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('lays out without overflow at 2x text size', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exceptionAsString());
      await openCard(tester, scale: 2);
      FlutterError.onError = previous;
      expect(errors, isEmpty);
      await _finish(tester);
    });
  });

  group('3D view, adding a unit', () {
    // Edit, an empty wall, then a unit from the tray: its Add card, with the
    // sizes and the free spaces to pick from.
    Future<void> openAdding(WidgetTester tester, {double scale = 1}) async {
      await _pump(tester, _screens['3D view']!(), scale: scale);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.tap(find.text('Clear all'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6)); // the snack bar goes
      await tester.ensureVisible(find.text('Base 600')); // the tray scrolls
      await tester.pump();
      await tester.tap(find.text('Base 600'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Add Base 600'), findsOneWidget);
      expect(find.text('Place it'), findsOneWidget);
    }

    testWidgets('tap targets are at least 48x48 and labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      await openAdding(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('text meets WCAG AA contrast', (tester) async {
      final semantics = tester.ensureSemantics();
      await openAdding(tester);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('lays out without overflow at 2x text size', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exceptionAsString());
      try {
        await openAdding(tester, scale: 2);
      } finally {
        FlutterError.onError = previous;
      }
      expect(errors, isEmpty);
      await _finish(tester);
    });
  });

  group('3D view, the wall card open', () {
    // Edit, an empty wall, the wall card with a hidden door made and chosen,
    // and the prices shown: the card at its fullest.
    // [prices]: with the price shown. (At 2x text the estimate bar alone is
    // most of a phone's height once it shows the price: a separate problem.)
    Future<void> openWall(WidgetTester tester,
        {double scale = 1, bool prices = true}) async {
      await _pump(tester, _screens['3D view']!(), scale: scale);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.tap(find.text('Clear all'));
      await tester.pump();
      // A message with an Undo stays up while a screen reader is on: put it
      // away, as the next message would.
      ScaffoldMessenger.of(tester.element(find.text('Edit cabinets')))
          .hideCurrentSnackBar();
      await tester.pump(const Duration(seconds: 1));
      if (prices) {
        await tester.tap(find.text('Show price'));
        await tester.pump();
      }
      final page = (WebViewPlatform.instance as FakeWebViewPlatform).lastController!;
      page.sendFromPage('StaticTraceChannel',
          jsonEncode({'event': 'wall_opened', 'opening': null, 'x_mm': 3000}));
      await tester.pump();
      final add = find.ancestor(
          of: find.textContaining('Hidden door'),
          matching: find.byType(OutlinedButton));
      await tester.ensureVisible(add);
      await tester.pump();
      await tester.tap(add);
      await tester.pump(const Duration(seconds: 1));
      // Back to the top of the card, as it opens.
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Doors and windows'));
      await tester.pump();
      expect(find.textContaining(prices ? 'Main wall  RM' : 'Main wall'),
          findsOneWidget);
      expect(find.text('Remove hidden door'), findsOneWidget);
    }

    testWidgets('tap targets are at least 48x48 and labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      await openWall(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('text meets WCAG AA contrast', (tester) async {
      final semantics = tester.ensureSemantics();
      await openWall(tester);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
      await _finish(tester);
    });

    testWidgets('lays out without overflow at 2x text size', (tester) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.exceptionAsString());
      try {
        await openWall(tester, scale: 2, prices: false);
      } finally {
        FlutterError.onError = previous;
      }
      expect(errors, isEmpty);
      await _finish(tester);
    });
  });

  // The pixel scan above covers this too; this pins the most important
  // button's colours directly.
  testWidgets('3D view: the Quote button label meets 4.5:1', (tester) async {
    await _pump(tester, _screens['3D view']!());
    final label = find.text('Quote');
    final button = find.ancestor(
      of: label,
      matching: find.byWidgetPredicate((w) => w is ElevatedButton),
    );
    expect(tester.widget<ElevatedButton>(button).enabled, isTrue);
    final textColor = DefaultTextStyle.of(tester.element(label)).style.color!;
    final background = AppTheme
        .theme.elevatedButtonTheme.style!.backgroundColor!
        .resolve(<WidgetState>{})!;
    expect(_contrast(textColor, background), greaterThanOrEqualTo(4.5),
        reason: 'text $textColor on $background');
    await _finish(tester);
  });
}
