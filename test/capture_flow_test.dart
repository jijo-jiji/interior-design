// Fix 5: the capture screens speak plainly and catch slips.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:static_trace/features/template/screens/template_room_screen.dart';
import 'package:static_trace/features/trace/providers/wall_provider.dart';
import 'package:static_trace/features/trace/screens/camera_screen.dart';
import 'package:static_trace/features/trace/screens/wall_setup_screen.dart';
import 'package:static_trace/shared/labels.dart';
import 'package:static_trace/shared/theme.dart';

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer();
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
    testWidgets('no engineering jargon, no thickness field', (tester) async {
      await pump(tester, const WallSetupScreen(imagePath: 'wall.png'));
      expect(find.text('Wall size'), findsOneWidget);
      expect(find.textContaining('px'), findsNothing);
      expect(find.textContaining('ratio'), findsNothing);
      expect(find.textContaining('thickness'), findsNothing);
    });

    testWidgets('a measurement in cm is caught before moving on',
        (tester) async {
      await pump(tester, const WallSetupScreen(imagePath: 'wall.png'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '360');
      await tester.tap(find.text('Next: line up the photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('That looks small for a wall width'),
          findsOneWidget);
      expect(find.text('Trace screen'), findsNothing);
    });

    testWidgets('sensible sizes go on to the trace screen', (tester) async {
      await pump(tester, const WallSetupScreen(imagePath: 'wall.png'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Wall width'), '3600');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Ceiling height'), '2800');
      await tester.tap(find.text('Next: line up the photo'));
      await tester.pumpAndSettle();
      expect(find.text('Trace screen'), findsOneWidget);
      final wall = container.read(wallSetupProvider);
      expect(wall.widthMm, 3600);
      expect(wall.heightMm, 2800);
      expect(wall.depthMm, 150);
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
