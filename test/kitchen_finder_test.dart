// Finding the kitchen and its room size on a plan by rule (no AI).
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/floorplan/kitchen_finder.dart';
import 'package:static_trace/features/floorplan/plan_sizes.dart';

import 'helpers/fake_plan_reader.dart';

Rect box(double x, double y, [double w = 0.08, double h = 0.02]) =>
    Rect.fromCenter(center: Offset(x, y), width: w, height: h);

PlanText plan(List<List<PlanWord>> lines) => findPlanText(lines);

void main() {
  group('the kitchen', () {
    test('is found by its name, English or Malay', () {
      for (final name in ['KITCHEN', 'Kitchen', 'DAPUR', 'PANTRY']) {
        final walls = findKitchen(plan([
          [PlanWord(name, box(0.5, 0.5))],
          [PlanWord('BEDROOM', box(0.2, 0.2))],
        ]));
        expect(walls?.kitchenLabel.text, name, reason: name);
      }
    });

    test('survives one misread letter', () {
      for (final misread in ['KITCHEM', 'KlTCHEN', 'KITCHN', 'DAPOR']) {
        expect(
            findKitchen(plan([
              [PlanWord(misread, box(0.5, 0.5))]
            ])),
            isNotNull,
            reason: misread);
      }
      // Two letters off is something else.
      expect(
          findKitchen(plan([
            [PlanWord('KETCHUP', box(0.5, 0.5))]
          ])),
          isNull);
      expect(
          findKitchen(plan([
            [PlanWord('BEDROOM', box(0.5, 0.5))]
          ])),
          isNull);
    });

    test('a wet kitchen wins over a dry one', () {
      final walls = findKitchen(plan([
        [PlanWord('DRY', box(0.2, 0.5)), PlanWord('KITCHEN', box(0.3, 0.5))],
        [PlanWord('WET', box(0.7, 0.5)), PlanWord('KITCHEN', box(0.8, 0.5))],
      ]));
      expect(walls!.kitchenLabel.text, 'WET KITCHEN');
    });
  });

  group('its room size', () {
    test('printed on its line gives both walls, and starts as an L', () {
      final walls = findKitchen(lKitchenText())!;
      expect(walls.isLShape, isTrue);
      expect(walls.mainWall.text, '3000');
      expect(walls.returnWall!.text, '2400');
    });

    test('printed just under its name', () {
      final walls = findKitchen(plan([
        [PlanWord('KITCHEN', box(0.5, 0.40))],
        [
          PlanWord('3.0', box(0.48, 0.43)),
          PlanWord('x', box(0.5, 0.43)),
          PlanWord('2.4m', box(0.53, 0.43))
        ],
      ]))!;
      expect(walls.mainWall.text, '3.0m');
      expect(walls.returnWall!.text, '2.4m');
    });

    test("another room's size is never the kitchen's", () {
      final walls = findKitchen(plan([
        [PlanWord('KITCHEN', box(0.7, 0.4))],
        // Under the bedroom, nowhere near the kitchen.
        [PlanWord('BEDROOM', box(0.2, 0.4))],
        [PlanWord('3600x3300', box(0.2, 0.43))],
        // Under the kitchen, but far below: a different room.
        [PlanWord('4200x3600', box(0.7, 0.8))],
      ]))!;
      expect(walls.mainWall.sizes, isEmpty);
      expect(walls.isLShape, isFalse);
    });

    test('none printed: the kitchen is found, its walls are left empty', () {
      final walls = findKitchen(unsizedKitchenText())!;
      expect(walls.kitchenLabel.text, 'KITCHEN');
      expect(walls.mainWall.text, isNull);
    });
  });

  group('sizeChoices', () {
    // The living room's 6900 x 3000 is read before DAPUR's 3000 x 2400, so
    // there are two 3000s.
    PlanText twoThrees() => plan(const [
          [
            PlanWord('RUANG', Rect.fromLTWH(0.4, 0.6, 0.1, 0.02)),
            PlanWord('6900x3000', Rect.fromLTWH(0.4, 0.63, 0.1, 0.02)),
          ],
          [
            PlanWord('DAPUR', Rect.fromLTWH(0.7, 0.3, 0.1, 0.02)),
            PlanWord('3000x2400', Rect.fromLTWH(0.7, 0.33, 0.1, 0.02)),
          ],
        ]);

    test('one button per value, in reading order', () {
      final text = twoThrees();
      expect(
          sizeChoices(text, null).map((s) => s.text), ['6900', '3000', '2400']);
    });

    test("the kitchen's 3000 wins over another room's", () {
      final text = twoThrees();
      final choices = sizeChoices(text, findKitchen(text));
      final three = choices.singleWhere((s) => s.text == '3000');
      expect(three.line, 'DAPUR 3000x2400');
    });
  });
}
