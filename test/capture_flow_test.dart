// Fix 5: the capture screens speak plainly and catch slips.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:static_trace/features/template/screens/template_room_screen.dart';
import 'package:static_trace/features/trace/providers/wall_provider.dart';
import 'package:static_trace/features/trace/screens/camera_screen.dart';
import 'package:static_trace/features/trace/screens/wall_setup_screen.dart';
import 'package:static_trace/features/trace/utils/opening_finder.dart';
import 'package:static_trace/shared/labels.dart';
import 'package:static_trace/shared/theme.dart';
import 'helpers/fake_corner_suggester.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [noCornerModel, noWallSegmenter]);
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => screen),
      GoRoute(
        path: '/trace',
        builder: (_, __) => const Scaffold(body: Text('Trace screen')),
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.theme, routerConfig: router),
    ));
    await tester.pump();
  }

  group('wall size', () {
    bool? returned;

    Future<void> pumpWallSize(WidgetTester tester,
        {void Function(WallSetupNotifier)? traced, WallLabels? labels}) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      container = ProviderContainer(overrides: [
        noCornerModel,
        wallSegmenterProvider.overrideWithValue(FakeWallSegmenter(labels)),
      ]);
      addTearDown(container.dispose);
      traced?.call(container.read(wallSetupProvider.notifier));
      returned = null;
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => returned =
                    await context.push<bool>('/wall-setup'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/wall-setup',
          builder: (_, __) => const WallSetupScreen(imagePath: 'wall.png'),
        ),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: AppTheme.theme, routerConfig: router),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Next: windows & doors'));
      await tester.tap(find.text('Next: windows & doors'));
      await tester.pumpAndSettle();
    }

    /// A 1600 × 1200 photo with the wall traced head-on, [w] × [h] px.
    void Function(WallSetupNotifier) tracedAt(double w, double h) => (n) {
          n.setPhoto(const Size(1600, 1200));
          final l = (1 - w / 1600) / 2, t = (1 - h / 1200) / 2;
          n.moveCorner(WallCorner.topLeft, Offset(l, t));
          n.moveCorner(WallCorner.topRight, Offset(1 - l, t));
          n.moveCorner(WallCorner.bottomRight, Offset(1 - l, 1 - t));
          n.moveCorner(WallCorner.bottomLeft, Offset(l, 1 - t));
        };

    testWidgets('no engineering jargon, no thickness field', (tester) async {
      await pumpWallSize(tester);
      expect(find.text('Wall size'), findsOneWidget);
      expect(find.textContaining('px'), findsNothing);
      expect(find.textContaining('ratio'), findsNothing);
      expect(find.textContaining('thickness'), findsNothing);
    });

    testWidgets('a measurement in cm is caught before moving on',
        (tester) async {
      await pumpWallSize(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '360');
      await next(tester);
      expect(find.textContaining('That looks small for a wall width'),
          findsOneWidget);
      expect(returned, isNull);
    });

    testWidgets('sensible sizes go back to the trace screen', (tester) async {
      await pumpWallSize(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '3600');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ceiling height'), '2800');
      await next(tester);
      expect(returned, isTrue);
      final wall = container.read(wallSetupProvider);
      expect(wall.widthMm, 3600);
      expect(wall.heightMm, 2800);
      expect(wall.depthMm, 150);
      expect(wall.sizeFromTape, isTrue);
    });

    testWidgets('nothing to measure by: the usual ceiling, the width from '
        'the traced wall', (tester) async {
      // 900 × 600 px: 1.5 wide for 1 high, so 4,050 mm for 2,700.
      await pumpWallSize(tester, traced: tracedAt(900, 600));
      expect(find.textContaining('the usual 2,700 mm ceiling'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '4050'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '2700'), findsOneWidget);
      await next(tester);
      expect(returned, isTrue);
      expect(container.read(wallSetupProvider).sizeFrom, 'assumed');
    });

    /// Labels for the 1600 × 1200 photo traced at 900 × 600 px: base
    /// cabinets along the wall, their worktop 30% of the way up it.
    WallLabels kitchenLabels() {
      const n = 128, l = 0.21875, t = 0.25, w = 0.5625, h = 0.5;
      final ids = Uint8List(n * n);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final u = ((x + 0.5) / n - l) / w, v = ((y + 0.5) / n - t) / h;
          ids[y * n + x] = v > 1
              ? WallLabels.floor
              : (v > 0.7 && u >= 0 && u <= 1)
                  ? WallLabels.cabinet
                  : WallLabels.wall;
        }
      }
      return WallLabels(n, n, ids);
    }

    testWidgets('measured from the photo by the worktop, no typing needed',
        (tester) async {
      await pumpWallSize(tester,
          traced: tracedAt(900, 600), labels: kitchenLabels());
      await tester.pumpAndSettle();
      expect(find.textContaining('using the worktop'), findsOneWidget);
      // 900 mm is 30% of the wall: about 3,000 mm high, 4,500 wide.
      expect(container.read(wallSetupProvider).heightMm, 2700); // until Next
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .map((f) => double.parse(f.controller!.text))
          .toList();
      expect(fields[1], closeTo(3000, 60));
      expect(fields[0], closeTo(fields[1] * 1.5, 10));
      await next(tester);
      expect(container.read(wallSetupProvider).sizeFrom, 'worktop');
    });

    testWidgets('halfway through typing a number, the other box is left alone',
        (tester) async {
      // A square on the photo, head-on: 2,700 × 2,700 to begin with.
      await pumpWallSize(tester, traced: tracedAt(800, 800));
      for (final partial in ['2', '25', '250']) {
        await tester.enterText(
            find.widgetWithText(TextFormField, 'Ceiling height'), partial);
        await tester.pump();
        expect(find.widgetWithText(TextFormField, '2700'), findsOneWidget,
            reason: 'width untouched at "$partial"');
      }
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ceiling height'), '2500');
      await tester.pump();
      expect(find.widgetWithText(TextFormField, '2500'), findsNWidgets(2));
    });

    testWidgets('typing one measurement works out the other', (tester) async {
      // A square on the photo, head-on.
      await pumpWallSize(tester, traced: tracedAt(800, 800));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ceiling height'), '2500');
      await tester.pump();
      expect(find.widgetWithText(TextFormField, '2500'), findsNWidgets(2));
      expect(find.textContaining('Width worked out from your height'),
          findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '2600');
      await tester.pump();
      // Both typed: both kept as typed.
      expect(find.widgetWithText(TextFormField, '2500'), findsOneWidget);
      await next(tester);
      expect(container.read(wallSetupProvider).sizeFrom, 'typed');
      expect(container.read(wallSetupProvider).widthMm, 2600);
    });

    testWidgets('untraced, nothing is guessed', (tester) async {
      await pumpWallSize(tester);
      expect(find.textContaining('From the photo'), findsNothing);
      expect(find.textContaining('Use a tape'), findsOneWidget);
    });

    testWidgets('says when the tape disagrees with the traced wall',
        (tester) async {
      // A square on the photo, head-on; both measurements typed.
      await pumpWallSize(tester, traced: tracedAt(800, 800));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ceiling height'), '2600');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '4000');
      await tester.pump();
      expect(find.textContaining('looks about 2,600 mm wide'), findsOneWidget);

      // Matching: quiet, and no tick, since proportions don't prove the
      // corners.
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '2600');
      await tester.pump();
      expect(find.textContaining('looks about'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });
  });

  group('room size', () {
    testWidgets('offers only the shapes the layouts support', (tester) async {
      await pump(tester, const TemplateRoomScreen());
      expect(find.text('Single wall'), findsOneWidget);
      expect(find.text('L-shape'), findsOneWidget);
      expect(find.textContaining('Galley'), findsNothing);
      expect(find.textContaining('Studio'), findsNothing);
    });
  });

  group('camera', () {
    testWidgets('a camera problem is explained, with a way forward',
        (tester) async {
      // There is no camera in a widget test, so it fails to start.
      await pump(tester, const CameraScreen());
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining("The camera didn't start"), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.widgetWithText(SnackBarAction, 'Gallery'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  });

  test('time-ago labels', () {
    final now = DateTime(2026, 11, 4, 12);
    String ago(Duration d) => timeAgoLabel(now.subtract(d), now: now);
    expect(ago(const Duration(seconds: 20)), 'just now');
    expect(ago(const Duration(minutes: 10)), '10 min ago');
    expect(ago(const Duration(hours: 3)), '3 h ago');
    expect(ago(const Duration(hours: 30)), 'yesterday');
    expect(ago(const Duration(days: 4)), '4 days ago');
  });
}
