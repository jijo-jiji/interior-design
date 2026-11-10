// The trace screen without dragging: every corner, window and door can be
// placed with taps, arrow buttons or typed sizes (WCAG 2.5.7); and the wall
// is measured from its four corners, so an angled photo still measures true.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:static_trace/features/trace/models/obstacle.dart';
import 'package:static_trace/features/trace/providers/wall_provider.dart';
import 'package:static_trace/features/trace/screens/trace_screen.dart';
import 'package:static_trace/features/trace/screens/wall_setup_screen.dart';
import 'package:static_trace/features/trace/utils/homography.dart';
import 'package:static_trace/features/trace/utils/opening_finder.dart';
import 'package:static_trace/features/trace/utils/corner_suggestion.dart';
import 'package:static_trace/features/trace/utils/wall_lean.dart';
import 'package:static_trace/shared/theme.dart';

import 'helpers/fake_corner_suggester.dart';

void main() {
  late ProviderContainer container;

  setUp(() => rootBundle.clear());

  /// [lean]: what the lean check finds (none by default: no photo is read).
  Future<void> pumpTrace(WidgetTester tester,
      {double? lean, CornerSuggester? suggester, WallLabels? labels}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [
      cornerSuggesterProvider
          .overrideWithValue(suggester ?? FakeCornerSuggester()),
      wallSegmenterProvider.overrideWithValue(FakeWallSegmenter(labels)),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => TraceScreen(
          imagePath: 'floor_plan/images.png',
          leanCheck: (_, __, ___) async => lean,
        ),
      ),
      GoRoute(
        path: '/wall-setup',
        builder: (_, __) =>
            const WallSetupScreen(imagePath: 'floor_plan/images.png'),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.theme, routerConfig: router),
      ),
    );
    // The canvas size lands in the provider after the first frame.
    await tester.pump();
    await tester.pump();
  }

  WallSetup wall() => container.read(wallSetupProvider);
  WallSetupNotifier notifier() => container.read(wallSetupProvider.notifier);

  /// Taps something in the bottom panel, scrolling it into view first.
  Future<void> tapPanel(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  /// Step 1's Next: the wall-size screen, confirmed as it is, then back to
  /// the windows and doors.
  Future<void> toWindows(WidgetTester tester) async {
    await tapPanel(tester, find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Wall size'), findsOneWidget);
    await tester.ensureVisible(find.text('Next: windows & doors'));
    await tester.tap(find.text('Next: windows & doors'));
    await tester.pumpAndSettle();
  }

  /// A photo the test decides the size of (the widget test can't decode
  /// one), with the wall's corners at [corners].
  Future<void> photo(WidgetTester tester, Size size, List<Offset> corners) async {
    notifier().setPhoto(size);
    for (final c in WallCorner.values) {
      notifier().moveCorner(c, corners[c.index]);
    }
    await tester.pump();
  }

  group('corners', () {
    testWidgets('the arrows move the selected corner', (tester) async {
      await pumpTrace(tester);
      expect(find.text('Step 1 of 3'), findsOneWidget);

      final before = wall().corner(WallCorner.topLeft);
      await tapPanel(tester, find.byTooltip('Move top left corner right'));
      expect(wall().corner(WallCorner.topLeft).dx,
          closeTo(before.dx + kCornerNudge, 1e-9));

      await tapPanel(
          tester, find.widgetWithText(ChoiceChip, 'Bottom right'));
      final br = wall().corner(WallCorner.bottomRight);
      await tapPanel(tester, find.byTooltip('Move bottom right corner up'));
      expect(wall().corner(WallCorner.bottomRight).dy,
          closeTo(br.dy - kCornerNudge, 1e-9));
    });

    testWidgets('tapping the photo moves the selected corner there',
        (tester) async {
      await pumpTrace(tester);
      await tapPanel(tester, find.widgetWithText(ChoiceChip, 'Top right'));

      final canvas = tester.getRect(find.byType(Stack).first);
      await tester.tapAt(Offset(
          canvas.left + canvas.width * 0.7, canvas.top + canvas.height * 0.2));
      await tester.pump();
      final tr = wall().corner(WallCorner.topRight);
      expect(tr.dx, closeTo(0.7, 0.01));
      expect(tr.dy, closeTo(0.2, 0.01));
    });

    testWidgets('each corner is a labelled 48dp target', (tester) async {
      await pumpTrace(tester);
      for (final c in WallCorner.values) {
        final handle = find.bySemanticsLabel('${c.label} corner');
        expect(handle, findsOneWidget);
        expect(tester.getSize(handle).shortestSide, greaterThanOrEqualTo(48));
      }
    });

    test('corners stay on their side, and the wall stays four-sided', () {
      final n = WallSetupNotifier();
      n.moveCorner(WallCorner.topLeft, const Offset(0.99, 0.08));
      // Kept left of the top-right corner.
      expect(n.state.corner(WallCorner.topLeft).dx,
          closeTo(n.state.corner(WallCorner.topRight).dx - kMinEdgeGap, 1e-9));

      // Into the middle of the other three: not a wall shape, so refused.
      final n2 = WallSetupNotifier();
      n2.moveCorner(WallCorner.topLeft, const Offset(0.85, 0.85));
      expect(n2.state.corner(WallCorner.topLeft), kStartCorners[0]);

      // Off the photo: kept on it.
      n2.moveCorner(WallCorner.bottomLeft, const Offset(-0.3, 1.4));
      expect(n2.state.corner(WallCorner.bottomLeft), const Offset(0, 1));
    });

    test('a new photo starts the corners afresh and keeps the tilt', () {
      final n = WallSetupNotifier();
      n.moveCorner(WallCorner.topLeft, const Offset(0.2, 0.2));
      n.setPhoto(const Size(1920, 1080));
      n.startPhoto(tilt: const CaptureTilt(rollDeg: 1, pitchDeg: -2));
      expect(n.state.corners, kStartCorners);
      expect(n.state.photoSize, isNull);
      expect(n.state.tilt?.pitchDeg, -2);
    });
  });

  group('the straightened wall', () {
    testWidgets('is drawn at its true proportions, through the corners',
        (tester) async {
      await pumpTrace(tester);
      // An angled photo: the wall narrower on the right.
      const corners = [
        Offset(0.1, 0.1),
        Offset(0.8, 0.22),
        Offset(0.8, 0.78),
        Offset(0.1, 0.9),
      ];
      await photo(tester, const Size(1600, 1200), corners);
      await toWindows(tester);

      // One scale both ways: the wall is shown at 4000 × 2700.
      expect(wall().scaleRatioX, closeTo(wall().scaleRatioY, 1e-6));

      // The photo goes through a perspective mapping that puts the corners
      // on the straightened wall's corners.
      final transforms = tester
          .widgetList<Transform>(find.byType(Transform))
          .where((t) => t.transform.entry(3, 0) != 0 || t.transform.entry(3, 1) != 0)
          .toList();
      expect(transforms, hasLength(1));
      final m = transforms.single.transform;
      final rect = Rect.fromLTRB(wall().leftLinePx, wall().topLinePx,
          wall().rightLinePx, wall().bottomLinePx);
      Offset apply(Offset p) {
        final w = m.entry(3, 0) * p.dx + m.entry(3, 1) * p.dy + m.entry(3, 3);
        return Offset(
          (m.entry(0, 0) * p.dx + m.entry(0, 1) * p.dy + m.entry(0, 3)) / w,
          (m.entry(1, 0) * p.dx + m.entry(1, 1) * p.dy + m.entry(1, 3)) / w,
        );
      }

      final expected = [
        Offset.zero,
        Offset(rect.width, 0),
        Offset(rect.width, rect.height),
        Offset(0, rect.height),
      ];
      for (var i = 0; i < 4; i++) {
        final px = Offset(corners[i].dx * 1600, corners[i].dy * 1200);
        expect((apply(px) - expected[i]).distance, lessThan(0.01));
      }
    });

    testWidgets('windows can be added, resized by typing, and removed',
        (tester) async {
      await pumpTrace(tester);
      await toWindows(tester);
      expect(find.text('Step 3 of 3'), findsOneWidget);

      await tapPanel(tester, find.text('Add window'));
      expect(container.read(obstaclesProvider), hasLength(1));
      expect(find.textContaining('Window 1 · 1200 × 1000 mm'), findsOneWidget);

      // The chip opens the exact-size editor.
      await tapPanel(tester,
          find.widgetWithText(ActionChip, 'Window 1 · 1200 × 1000 mm'));
      await tester.pumpAndSettle();
      expect(find.text('Window 1 · size and position'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Width'), '1500');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Window 1 · 1500 × 1000 mm'), findsOneWidget);

      // A second window is numbered and placed beside the first.
      await tapPanel(tester, find.text('Add window'));
      final items = container.read(obstaclesProvider);
      expect(items[1].leftPx, greaterThan(items[0].leftPx));
      expect(find.textContaining('Window 2'), findsWidgets);

      await tester.tap(find.byTooltip('Remove window 2'));
      await tester.pump();
      expect(container.read(obstaclesProvider), hasLength(1));

      await tapPanel(tester,
          find.widgetWithText(ActionChip, 'Window 1 · 1500 × 1000 mm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove window 1'));
      await tester.pumpAndSettle();
      expect(container.read(obstaclesProvider), isEmpty);
    });

    testWidgets('warns when upright edges lean: a corner is off',
        (tester) async {
      await pumpTrace(tester, lean: -4.2);
      await toWindows(tester);
      expect(find.textContaining('Upright edges lean about 4.2°'),
          findsOneWidget);
    });

    testWidgets('says nothing when they stand upright', (tester) async {
      await pumpTrace(tester, lean: 0.6);
      await toWindows(tester);
      expect(find.textContaining('Upright edges lean'), findsNothing);
      expect(kLeanWarnDeg, greaterThan(0.6));
    });

    group('windows and doors found on the photo', () {
      // The wall over the whole photo (start corners 0.08–0.92), a window
      // in its upper middle and a door on the right.
      WallLabels kitchenWall() {
        const n = 128;
        final ids = Uint8List(n * n)..fillRange(0, n * n, WallLabels.wall);
        void paint(int id, Rect r) {
          for (var y = 0; y < n; y++) {
            for (var x = 0; x < n; x++) {
              if (r.contains(Offset((x + 0.5) / n, (y + 0.5) / n))) {
                ids[y * n + x] = id;
              }
            }
          }
        }

        paint(WallLabels.window, const Rect.fromLTRB(0.3, 0.25, 0.5, 0.5));
        paint(WallLabels.door, const Rect.fromLTRB(0.7, 0.3, 0.85, 0.9));
        return WallLabels(n, n, ids);
      }

      testWidgets('are placed as boxes to check', (tester) async {
        await pumpTrace(tester, labels: kitchenWall());
        await toWindows(tester);
        final boxes = container.read(obstaclesProvider);
        expect(boxes.map((b) => b.type),
            [ObstacleType.window, ObstacleType.door]);
        expect(find.textContaining('Found a window and a door'),
            findsOneWidget);
        // In the panel too, with their sizes.
        expect(find.textContaining('Window 1 ·'), findsOneWidget);
        expect(find.textContaining('Door 1 ·'), findsOneWidget);
      });

      testWidgets('only once: going back and forth adds none again',
          (tester) async {
        await pumpTrace(tester, labels: kitchenWall());
        await toWindows(tester);
        await tapPanel(tester, find.text('Edit size'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Next: windows & doors'));
        await tester.tap(find.text('Next: windows & doors'));
        await tester.pumpAndSettle();
        expect(container.read(obstaclesProvider), hasLength(2));
      });

      testWidgets('none on the wall: said so', (tester) async {
        const n = 128;
        await pumpTrace(tester,
            labels: WallLabels(
                n, n, Uint8List(n * n)..fillRange(0, n * n, WallLabels.wall)));
        await toWindows(tester);
        expect(container.read(obstaclesProvider), isEmpty);
        expect(find.textContaining('No windows or doors found'),
            findsOneWidget);
      });

      testWidgets('no model here: nothing said, nothing placed',
          (tester) async {
        await pumpTrace(tester);
        await toWindows(tester);
        expect(container.read(obstaclesProvider), isEmpty);
        expect(find.textContaining('windows and doors…'), findsNothing);
        expect(find.textContaining('No windows or doors found'), findsNothing);
      });
    });

    testWidgets('Edit corners goes back to step 1', (tester) async {
      await pumpTrace(tester);
      await toWindows(tester);
      await tapPanel(tester, find.text('Edit corners'));
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('the wall is traced first, then measured', (tester) async {
      await pumpTrace(tester);
      // 960 × 648 px on a 1600 × 1200 photo, head-on: 1.48 wide for 1 high.
      await photo(tester, const Size(1600, 1200), const [
        Offset(0.2, 0.23),
        Offset(0.8, 0.23),
        Offset(0.8, 0.77),
        Offset(0.2, 0.77),
      ]);
      await tapPanel(tester, find.text('Next'));
      await tester.pumpAndSettle();
      // The width comes from the traced corners: 2700 × 1.48 ≈ 4000.
      expect(find.textContaining('From the photo, this wall is about 4,000 mm'),
          findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '4100');
      await tester.ensureVisible(find.text('Next: windows & doors'));
      await tester.tap(find.text('Next: windows & doors'));
      await tester.pumpAndSettle();
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(wall().widthMm, 4100);
      expect(wall().sizeFromTape, isTrue);

      // Edit size: the tape's numbers, not a new estimate.
      await tapPanel(tester, find.text('Edit size'));
      await tester.pumpAndSettle();
      expect(find.textContaining('From the photo'), findsNothing);
      expect(find.widgetWithText(TextFormField, '4100'), findsOneWidget);
    });

    testWidgets('a box stays on its spot of the wall when the size changes',
        (tester) async {
      await pumpTrace(tester);
      await toWindows(tester);
      await tapPanel(tester, find.text('Add window'));
      Rect fraction(WallSetup w, Rect box) => Rect.fromLTRB(
            (box.left - w.leftLinePx) / (w.rightLinePx - w.leftLinePx),
            (box.top - w.topLinePx) / (w.bottomLinePx - w.topLinePx),
            (box.right - w.leftLinePx) / (w.rightLinePx - w.leftLinePx),
            (box.bottom - w.topLinePx) / (w.bottomLinePx - w.topLinePx),
          );
      Rect box() {
        final o = container.read(obstaclesProvider).single;
        return Rect.fromLTWH(o.leftPx, o.topPx, o.widthPx, o.heightPx);
      }

      final before = fraction(wall(), box());
      // A much narrower wall: the straightened wall is redrawn taller.
      notifier().updateDimensions(widthMm: 2500, heightMm: 2700, depthMm: 150);
      await tester.pump();
      await tester.pump();
      final after = fraction(wall(), box());
      expect(after.left, closeTo(before.left, 1e-6));
      expect(after.top, closeTo(before.top, 1e-6));
      expect(after.right, closeTo(before.right, 1e-6));
      expect(after.bottom, closeTo(before.bottom, 1e-6));
    });
  });

  group('corners found by the model', () {
    const found = [
      Offset(0.21, 0.2),
      Offset(0.76, 0.18),
      Offset(0.75, 0.66),
      Offset(0.23, 0.67),
    ];

    testWidgets('are placed on the photo, and said so', (tester) async {
      await pumpTrace(tester,
          suggester: FakeCornerSuggester(const CornerSuggestion(found)));
      await tester.pump();
      expect(wall().corners, found);
      expect(wall().suggestedCorners, found);
      expect(find.textContaining('Corners placed for you'), findsOneWidget);
    });

    testWidgets('none found: place them by hand', (tester) async {
      await pumpTrace(tester,
          suggester: FakeCornerSuggester(const CornerSuggestion(null)));
      await tester.pump();
      expect(wall().corners, kStartCorners);
      expect(find.textContaining('Place them by hand'), findsOneWidget);
    });

    testWidgets('no model here: nothing is said', (tester) async {
      await pumpTrace(tester);
      await tester.pump();
      expect(find.textContaining('corners on this photo'), findsNothing);
      expect(find.textContaining('Corners placed'), findsNothing);
      expect(find.textContaining('Looking for'), findsNothing);
    });

    testWidgets("found after marking started: offered, not moved under the "
        'finger', (tester) async {
      final gate = Completer<void>();
      await pumpTrace(tester,
          suggester:
              FakeCornerSuggester(const CornerSuggestion(found), gate));
      expect(find.textContaining('Looking for the wall'), findsOneWidget);

      await tapPanel(tester, find.byTooltip('Move top left corner right'));
      final mine = wall().corners;
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(wall().corners, mine);
      expect(find.text('Found the wall’s corners.'), findsOneWidget);

      await tapPanel(tester, find.text('Use them'));
      expect(wall().corners, found);
      expect(find.textContaining('Corners placed for you'), findsOneWidget);
    });

    test('kept with the quote beside the corners confirmed', () {
      final n = WallSetupNotifier()..suggest(found, place: true);
      n.moveCorner(WallCorner.topLeft, const Offset(0.2, 0.21));
      final record = captureRecord(n.state);
      expect(record['suggested_corners'][0], [0.21, 0.2]);
      expect(record['corners'][0], [0.2, 0.21]);
    });

    test('a suggestion that is not a proper wall is kept, not placed', () {
      final n = WallSetupNotifier();
      const twisted = [Offset(0.8, 0.2), Offset(0.2, 0.2), Offset(0.8, 0.8), Offset(0.2, 0.8)];
      expect(n.suggest(twisted, place: true), isFalse);
      expect(n.state.corners, kStartCorners);
      expect(n.state.suggestedCorners, twisted);
    });
  });

  test('the measurement is recorded with the design', () {
    final n = WallSetupNotifier()
      ..setPhoto(const Size(1920, 1080), focalPx: 1555)
      ..moveCorner(WallCorner.topRight, const Offset(0.9, 0.12));
    final record = captureRecord(n.state);
    expect(record['method'], 'corners');
    expect(record['corners'], hasLength(4));
    expect(record['corners'][1], [0.9, 0.12]);
    expect(record['photo_px'], [1920, 1080]);
    expect(record['focal_px'], 1555);
    expect(record['focal_source'], FocalSource.photo.name);
    expect(record['photo_aspect'], isA<double>());
    expect(record.containsKey('tilt_deg'), isFalse);
  });

  test('photoRectIn: a photo is contained and centred on the canvas', () {
    final r = photoRectIn(const Size(400, 600), const Size(1600, 1200));
    expect(r.width, 400);
    expect(r.height, closeTo(300, 1e-9));
    expect(r.top, closeTo(150, 1e-9));
    expect(photoRectIn(const Size(400, 600), null), Offset.zero & const Size(400, 600));
    expect(math.max(r.left, 0), 0);
  });
}
