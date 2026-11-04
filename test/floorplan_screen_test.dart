// Sizes from a floor plan, filled in by rule: the kitchen's printed room
// size, or its walls measured from the drawing; everything stays editable.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:static_trace/features/floorplan/plan_analysis.dart';
import 'package:static_trace/features/floorplan/plan_sizes.dart';
import 'package:static_trace/features/floorplan/screens/floorplan_sizes_screen.dart';
import 'package:static_trace/shared/theme.dart';

import 'helpers/fake_plan_reader.dart';

void main() {
  setUp(() => rootBundle.clear());

  Map<String, dynamic>? sentTo3D;

  Future<void> pumpPlan(
    WidgetTester tester, {
    PlanText? text,
    PlanAnalysis? drawing,
    Completer<void>? gate,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    sentTo3D = null;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => FloorplanSizesScreen(
          imagePath: 'floor_plan/images.png',
          textReader: FakePlanTextReader(text),
          analyser: FakePlanAnalyser(drawing, gate),
        ),
      ),
      GoRoute(
        path: '/viewer',
        builder: (_, state) {
          sentTo3D = jsonDecode(state.extra! as String) as Map<String, dynamic>;
          return const Scaffold(body: Text('3D view'));
        },
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.theme, routerConfig: router),
    );
    // The text is read, then the drawing.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  String textOf(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(field(label)).controller!.text;
  bool isL(WidgetTester tester) => tester
      .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'L-shape'))
      .selected;

  Future<void> viewIn3D(WidgetTester tester) async {
    // Done typing: a focused field keeps scrolling itself back into view.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tap(tester, find.text('View in 3D'));
    await tester.pumpAndSettle();
  }

  group("the kitchen's printed room size", () {
    testWidgets('fills both walls as an L', (tester) async {
      await pumpPlan(tester);

      expect(find.textContaining("Filled in from the kitchen's room size"),
          findsOneWidget);
      expect(isL(tester), isTrue);
      expect(textOf(tester, 'Main wall'), '3000');
      expect(textOf(tester, 'Return wall'), '2400');
      expect(find.text("Printed on the plan · the kitchen's room size"),
          findsNWidgets(2));

      await viewIn3D(tester);
      expect(sentTo3D!['wall'], {
        'width_mm': 3000.0,
        'height_mm': 2700.0,
        'depth_mm': 150.0,
        'shape': 'lShape',
        'return_mm': 2400.0,
      });
      // No drawing was read: nothing for the 3D's Room and House views.
      expect(sentTo3D!.containsKey('floor_plan'), isFalse);
    });

    testWidgets('with the drawing read, the plan goes to the 3D',
        (tester) async {
      // The kitchen is drawn 300 × 240 px at 10 mm/px: 3000 across, 2400
      // down, with a 900 mm doorway 600 mm along its top wall.
      await pumpPlan(tester, drawing: measuredPlan());

      expect(textOf(tester, 'Main wall'), '3000');
      await viewIn3D(tester);
      final plan = sentTo3D!['floor_plan'] as Map<String, dynamic>;
      expect(plan['kitchen_mm'], [0, 0, 3000, 2400]);
      expect(plan['image'], startsWith('data:image/png'));
      expect(sentTo3D!['obstacles'], [
        {
          'type': 'door',
          'distance_from_left_mm': 600.0,
          'distance_from_floor_mm': 0.0,
          'width_mm': 900.0,
          'height_mm': 2100.0,
        }
      ]);
    });

    testWidgets('Turn makes the side wall the main one', (tester) async {
      await pumpPlan(tester, drawing: measuredPlan());

      await tap(tester, find.text('Turn'));
      expect(textOf(tester, 'Main wall'), '2400');
      expect(textOf(tester, 'Return wall'), '3000');
    });
  });

  group('no size printed for the kitchen', () {
    testWidgets('its walls are measured from the drawing', (tester) async {
      await pumpPlan(tester,
          text: unsizedKitchenText(),
          drawing:
              measuredPlan(kitchen: const Rect.fromLTRB(400, 100, 690, 345)));

      expect(find.textContaining('Measured from the drawing'), findsOneWidget);
      expect(isL(tester), isTrue);
      // 290 × 245 px at 10 mm/px, to the nearest 10 mm.
      expect(textOf(tester, 'Main wall'), '2900');
      expect(textOf(tester, 'Return wall'), '2450');
      expect(find.text('Measured on the plan; check it on site'),
          findsNWidgets(2));
    });

    testWidgets('an open-plan kitchen is left for typing', (tester) async {
      await pumpPlan(tester,
          text: unsizedKitchenText(), drawing: measuredPlan(openPlan: true));
      expect(find.textContaining('open to the next room'), findsOneWidget);
      expect(textOf(tester, 'Main wall'), isEmpty);
      expect(find.text('Turn'), findsNothing);
    });

    testWidgets("a plan that isn't to scale isn't measured", (tester) async {
      await pumpPlan(tester,
          text: unsizedKitchenText(), drawing: measuredPlan(mmPerPx: null));
      expect(find.textContaining("isn't to scale"), findsOneWidget);
      expect(textOf(tester, 'Main wall'), isEmpty);
    });
  });

  testWidgets('a size typed while the drawing is read is kept', (tester) async {
    final gate = Completer<void>();
    await pumpPlan(tester,
        text: unsizedKitchenText(), drawing: measuredPlan(), gate: gate);
    expect(find.textContaining('Reading the drawing'), findsOneWidget);

    await tester.enterText(field('Main wall'), '3200');
    gate.complete();
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(textOf(tester, 'Main wall'), '3200');
    expect(textOf(tester, 'Return wall'), '2400');
  });

  testWidgets('a filled-in size can be edited', (tester) async {
    await pumpPlan(tester);

    await tester.enterText(field('Return wall'), '2.6 m');
    await tester.pump();
    expect(find.text("Printed on the plan · the kitchen's room size"),
        findsOneWidget);
    expect(find.text('= 2,600 mm'), findsOneWidget);

    await viewIn3D(tester);
    expect(sentTo3D!['wall']['return_mm'], 2600.0);
  });

  testWidgets('another printed size can be tapped in, or added on',
      (tester) async {
    await pumpPlan(tester);

    await tap(tester, field('Return wall'));
    await tap(tester, find.widgetWithText(ActionChip, '2900'));
    expect(textOf(tester, 'Return wall'), '2900');

    await tap(tester, find.byTooltip('Add another size to the return wall'));
    await tap(tester, find.widgetWithText(ActionChip, '1700'));
    expect(textOf(tester, 'Return wall'), '2900 + 1700');
    expect(find.text('= 4,600 mm'), findsOneWidget);
  });

  testWidgets('no kitchen name: nothing is guessed', (tester) async {
    await pumpPlan(
      tester,
      text: findPlanText(const [
        [PlanWord('BILIK', Rect.fromLTWH(0.2, 0.2, 0.1, 0.02))],
        [PlanWord('3000', Rect.fromLTWH(0.5, 0.02, 0.1, 0.02))],
      ]),
    );
    expect(find.textContaining("Couldn't find the kitchen's name"),
        findsOneWidget);
    expect(textOf(tester, 'Main wall'), isEmpty);

    await viewIn3D(tester);
    expect(find.text('Enter the main wall'), findsOneWidget);
    expect(sentTo3D, isNull);
  });

  testWidgets('a plan too small to read says so, and how to get a sharper one',
      (tester) async {
    // Like floor_plan/images.png, the 447 px WhatsApp plan: a room name or
    // two can be read off it, but no sizes.
    await pumpPlan(
      tester,
      text: const PlanText(
        labels: [PlanLabel('KITCHEN', Rect.fromLTWH(0.5, 0.3, 0.1, 0.02))],
        planSize: Size(447, 447),
      ),
    );
    expect(
      find.text('This plan is too small to read (447 px wide). Ask for the '
          'original (on WhatsApp: send it as a document), or type the sizes '
          'below.'),
      findsOneWidget,
    );
  });

  testWidgets('no text at all: say so', (tester) async {
    await pumpPlan(tester, text: const PlanText());
    expect(find.textContaining("Couldn't read any text on this plan"),
        findsOneWidget);
  });

  testWidgets('metres typed without the "m" are caught', (tester) async {
    await pumpPlan(tester);

    await tester.enterText(field('Main wall'), '3.6');
    await viewIn3D(tester);

    expect(find.textContaining('For metres, type "3.6 m"'), findsOneWidget);
    expect(sentTo3D, isNull);
  });
}
