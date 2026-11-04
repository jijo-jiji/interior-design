// Measuring a wall from a floor plan without dragging (WCAG 2.5.7): pick a
// mark, then tap the plan or use the arrow buttons.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/floorplan/screens/floorplan_calibrate_screen.dart';
import 'package:static_trace/shared/theme.dart';

void main() {
  setUp(() => rootBundle.clear());

  Future<void> pumpPlan(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home:
            const FloorplanCalibrateScreen(imagePath: 'floor_plan/images.png'),
      ),
    );
    await tester.pump();
  }

  Future<void> tapPanel(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  /// The "Wall width (1–2)" readout, in mm.
  int wallMm(WidgetTester tester) {
    final text = tester
        .widgetList<Text>(find.textContaining(RegExp(r'^\d+ mm$')))
        .single
        .data!;
    return int.parse(text.split(' ').first);
  }

  testWidgets('the arrows lengthen and shorten the wall', (tester) async {
    await pumpPlan(tester);
    final start = wallMm(tester);

    // Wall end is selected to begin with; moving it right lengthens the wall.
    for (var i = 0; i < 5; i++) {
      await tapPanel(tester, find.byTooltip('Move wall end right'));
    }
    final longer = wallMm(tester);
    expect(longer, greaterThan(start));

    await tapPanel(tester, find.widgetWithText(ChoiceChip, 'Wall start'));
    for (var i = 0; i < 5; i++) {
      await tapPanel(tester, find.byTooltip('Move wall start right'));
    }
    expect(wallMm(tester), lessThan(longer));
  });

  testWidgets('the same marks with a shorter A–B length give a shorter wall',
      (tester) async {
    await pumpPlan(tester);
    final at900 = wallMm(tester);
    await tester.enterText(find.byType(TextField), '450');
    await tester.pump();
    expect(wallMm(tester), closeTo(at900 / 2, 2));
  });

  testWidgets('tapping the plan places the selected mark', (tester) async {
    await pumpPlan(tester);
    final before = wallMm(tester);

    // Put the wall end right on top of the wall start: the wall shrinks to
    // almost nothing.
    await tapPanel(tester, find.widgetWithText(ChoiceChip, 'Wall end'));
    // The wall start mark is the badge labelled 1.
    final startMark = tester.getCenter(find.text('1'));
    await tester.tapAt(startMark + const Offset(30, 0));
    await tester.pump();
    expect(wallMm(tester), lessThan(before / 4));
  });
}
