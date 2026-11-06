// The trace screen without dragging: every edge, window and door can be
// placed with taps, arrow buttons or typed sizes (WCAG 2.5.7).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/providers/wall_provider.dart';
import 'package:static_trace/features/trace/screens/trace_screen.dart';
import 'package:static_trace/shared/theme.dart';

void main() {
  late ProviderContainer container;

  setUp(() => rootBundle.clear());

  Future<void> pumpTrace(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.theme,
          home: const TraceScreen(imagePath: 'floor_plan/images.png'),
        ),
      ),
    );
    // The canvas size lands in the provider after the first frame.
    await tester.pump();
    await tester.pump();
  }

  WallSetup wall() => container.read(wallSetupProvider);

  /// Taps something in the bottom panel, scrolling it into view first.
  Future<void> tapPanel(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('the arrows move the selected wall edge', (tester) async {
    await pumpTrace(tester);
    expect(find.text('Step 1 of 2'), findsOneWidget);

    final before = wall().leftLineRatio;
    await tapPanel(tester, find.byTooltip('Move left wall edge right'));
    expect(wall().leftLineRatio, closeTo(before + kEdgeNudge, 1e-9));

    await tapPanel(tester, find.widgetWithText(ChoiceChip, 'Ceiling'));
    // The ceiling is horizontal: only up and down arrows.
    expect(find.byTooltip('Move ceiling edge left'), findsNothing);
    final top = wall().topLineRatio;
    await tapPanel(tester, find.byTooltip('Move ceiling edge down'));
    expect(wall().topLineRatio, closeTo(top + kEdgeNudge, 1e-9));
  });

  testWidgets('tapping the photo moves the selected edge there',
      (tester) async {
    await pumpTrace(tester);
    await tapPanel(tester, find.widgetWithText(ChoiceChip, 'Right'));

    final canvas = tester.getRect(find.byType(Stack).first);
    await tester.tapAt(Offset(
        canvas.left + canvas.width * 0.7, canvas.top + canvas.height / 3));
    await tester.pump();
    expect(wall().rightLineRatio, closeTo(0.7, 0.01));
  });

  testWidgets('edges keep their minimum gap', (tester) async {
    await pumpTrace(tester);
    container.read(wallSetupProvider.notifier).moveEdge(WallEdge.left, 0.99);
    expect(wall().leftLineRatio,
        closeTo(wall().rightLineRatio - kMinEdgeGap, 1e-9));
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
    await tapPanel(
        tester, find.widgetWithText(ActionChip, 'Window 1 · 1200 × 1000 mm'));
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

    await tapPanel(
        tester, find.widgetWithText(ActionChip, 'Window 1 · 1500 × 1000 mm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove window 1'));
    await tester.pumpAndSettle();
    expect(container.read(obstaclesProvider), isEmpty);
  });

  testWidgets('Edit wall edges goes back to step 1', (tester) async {
    await pumpTrace(tester);
    await tapPanel(tester, find.text('Next'));
    await tapPanel(tester, find.text('Edit wall edges'));
    expect(find.text('Step 1 of 2'), findsOneWidget);
  });
}
