// The trace screen without dragging: every corner, window and door can be
// placed with taps, arrow buttons or typed sizes (WCAG 2.5.7); and the wall
// is measured from its four corners, so an angled photo still measures true.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/providers/wall_provider.dart';
import 'package:static_trace/features/trace/screens/trace_screen.dart';
import 'package:static_trace/features/trace/utils/homography.dart';
import 'package:static_trace/features/trace/utils/corner_suggestion.dart';
import 'package:static_trace/features/trace/utils/wall_lean.dart';
import 'package:static_trace/shared/theme.dart';

import 'helpers/fake_corner_suggester.dart';

void main() {
  late ProviderContainer container;

  setUp(() => rootBundle.clear());

  /// [lean]: what the lean check finds (none by default: no photo is read).
  Future<void> pumpTrace(WidgetTester tester,
      {double? lean, CornerSuggester? suggester}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [
      cornerSuggesterProvider
          .overrideWithValue(suggester ?? FakeCornerSuggester()),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: TraceScreen(
            imagePath: 'floor_plan/images.png',
            leanCheck: (_, __, ___) async => lean,
          ),
        ),
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
      expect(find.text('Step 1 of 2'), findsOneWidget);

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

  group('size check', () {
    testWidgets('says when the corners disagree with the tape',
        (tester) async {
      await pumpTrace(tester);
      // A square on a 1600 × 1200 photo, head-on, for a 4000 × 2700 wall.
      await photo(tester, const Size(1600, 1200), const [
        Offset(0.25, 1 / 6),
        Offset(0.75, 1 / 6),
        Offset(0.75, 5 / 6),
        Offset(0.25, 5 / 6),
      ]);
      expect(
          find.textContaining('looks about 2,700 mm wide'), findsOneWidget);
    });

    testWidgets('and stays quiet when they match', (tester) async {
      await pumpTrace(tester);
      // 960 × 648 px: the 4000 × 2700 wall's proportions.
      await photo(tester, const Size(1600, 1200), const [
        Offset(0.2, 0.23),
        Offset(0.8, 0.23),
        Offset(0.8, 0.77),
        Offset(0.2, 0.77),
      ]);
      // Quiet: no tick, since matching proportions don't prove the corners.
      expect(find.textContaining('looks about'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('stays quiet until the corners have moved', (tester) async {
      await pumpTrace(tester);
      notifier().setPhoto(const Size(1600, 1200));
      await tester.pump();
      expect(find.textContaining('looks about'), findsNothing);
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
      await tapPanel(tester, find.text('Next'));
      await tester.pump();

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
      await tapPanel(tester, find.text('Next'));
      expect(find.text('Step 2 of 2'), findsOneWidget);

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
      await tapPanel(tester, find.text('Next'));
      await tester.pump();
      expect(find.textContaining('Upright edges lean about 4.2°'),
          findsOneWidget);
    });

    testWidgets('says nothing when they stand upright', (tester) async {
      await pumpTrace(tester, lean: 0.6);
      await tapPanel(tester, find.text('Next'));
      await tester.pump();
      expect(find.textContaining('Upright edges lean'), findsNothing);
      expect(kLeanWarnDeg, greaterThan(0.6));
    });

    testWidgets('Edit corners goes back to step 1', (tester) async {
      await pumpTrace(tester);
      await tapPanel(tester, find.text('Next'));
      await tapPanel(tester, find.text('Edit corners'));
      expect(find.text('Step 1 of 2'), findsOneWidget);
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
