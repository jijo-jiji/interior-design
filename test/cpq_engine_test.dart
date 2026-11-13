import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/catalog/default_catalog.g.dart';
import 'package:static_trace/features/catalog/price_catalog.dart';
import 'package:static_trace/features/viewer/models/cpq_engine.dart';

void main() {
  group('CPQEngine Tests', () {
    test('Empty room returns zero total', () {
      final summary = CPQEngine.calculate(
        placedCabinets: [],
        obstacles: [],
        styleArchetype: 'japandi',
      );

      expect(summary.totalModules, 0);
      expect(summary.totalPrice, 0.0);
      expect(summary.subtotal, 0.0);
      expect(summary.monthlyPayment, 0.0);
    });

    test('Single base_800 and wall_600 in Japandi (1.0x baseline)', () {
      final summary = CPQEngine.calculate(
        placedCabinets: [
          {'cabinet_type': 'base_800'},
          {'cabinet_type': 'wall_600'},
        ],
        obstacles: [],
        styleArchetype: 'japandi',
      );

      // base_800 (420) + wall_600 (280) = 700 materials
      // labour = 2 * 120 = 240
      // subtotal = 940
      // sst (8%) = 75.20
      // total = 1015.20
      expect(summary.totalModules, 2);
      expect(summary.baseCabinetTotal, 420.00);
      expect(summary.wallCabinetTotal, 280.00);
      expect(summary.labourTotal, 240.00);
      expect(summary.subtotal, 940.00);
      expect(summary.gst, 75.20);
      expect(summary.totalPrice, 1015.20);
      expect(summary.monthlyPayment, closeTo(1015.20 / 36 * 1.06, 0.01));
    });

    test('Industrial style applies 1.18x material multiplier', () {
      final summary = CPQEngine.calculate(
        placedCabinets: [
          {'cabinet_type': 'base_600'}, // 340 * 1.18 = 401.20
        ],
        obstacles: [],
        styleArchetype: 'industrial',
      );

      expect(summary.materialMultiplier, 1.18);
      expect(summary.baseCabinetTotal, closeTo(401.20, 0.01));
      expect(summary.labourTotal, 120.00); // labour is fixed
    });

    test('Obstacle allowances reduce subtotal appropriately', () {
      final summary = CPQEngine.calculate(
        placedCabinets: [
          {'cabinet_type': 'base_800'}, // 420
        ],
        obstacles: [
          {'type': 'window'}, // -50
          {'type': 'door'}, // -80
        ],
        styleArchetype: 'japandi',
      );

      // materials: 420
      // labour: 120
      // allowance: -130
      // subtotal: 420 + 120 - 130 = 410
      expect(summary.obstacleAllowance, -130.00);
      expect(summary.subtotal, 410.00);
      expect(summary.gst, closeTo(32.80, 0.01));
      expect(summary.totalPrice, closeTo(442.80, 0.01));
    });

    test('Benchtop calculation adds engineered quartz surface per linear metre',
        () {
      final summary = CPQEngine.calculate(
        placedCabinets: [
          {'cabinet_type': 'base_800', 'width_mm': 800.0},
          {'cabinet_type': 'base_600', 'width_mm': 600.0},
        ],
        obstacles: [],
        styleArchetype: 'japandi',
        benchtopMaterial: 'quartz_calacatta',
      );

      // 0.8m + 0.6m = 1.4 linear metres
      // 1.4m * RM380 = RM532 benchtop total
      // cabinets: 420 + 340 = 760
      // labour: 2 * 120 = 240
      // subtotal: 760 + 532 + 240 = 1532
      // sst (8%): 122.56
      // total: 1654.56
      expect(summary.benchtopLinearMetres, closeTo(1.4, 0.01));
      expect(summary.benchtopTotal, closeTo(532.00, 0.01));
      expect(summary.benchtopMaterial, 'Calacatta Engineered Quartz');
      expect(summary.subtotal, closeTo(1532.00, 0.01));
      expect(summary.totalPrice, closeTo(1654.56, 0.01));
    });
  });

  group('Wall work (sample prices)', () {
    test('an opening to be made is priced; one already there is not', () {
      final summary = CPQEngine.calculate(
        placedCabinets: [],
        obstacles: [
          {'type': 'window', 'width_mm': 1200.0, 'height_mm': 1100.0},
          {'type': 'door', 'width_mm': 800.0, 'height_mm': 2100.0, 'work': 'hidden_door'},
          {'type': 'door', 'width_mm': 800.0, 'height_mm': 2100.0, 'work': 'hidden_door'},
        ],
        styleArchetype: 'industrial',
      );
      expect(summary.wallWorkLines, hasLength(1));
      final line = summary.wallWorkLines.single;
      expect(line.description, 'Wall work \u2014 Hidden door, flush with the wall');
      expect(line.qty, 2);
      expect(line.total, 4800, reason: 'no finish multiplier on wall work');
      expect(summary.wallWorkTotal, 4800);
      // 4800 - 50 (window) - 80 - 80 (doors' allowances)
      expect(summary.subtotal, closeTo(4590, 0.001));
    });

    test('the finish is priced on the area to the hundredth', () {
      final summary = CPQEngine.calculate(
        placedCabinets: [],
        obstacles: [],
        styleArchetype: 'japandi',
        wallFinish: {'kind': 'tiles', 'area_m2': 6.254},
      );
      final line = summary.wallWorkLines.single;
      expect(line.description,
          'Wall finish \u2014 Wall tiles, supplied and laid (6.25 m\u00b2 @ RM140/m\u00b2)');
      expect(line.total, 875);
    });

    test('an unknown finish or work, or no area, prices nothing', () {
      for (final finish in [
        {'kind': 'marble', 'area_m2': 5.0},
        {'kind': 'paint', 'area_m2': 0},
        {'kind': 'paint'},
      ]) {
        final summary = CPQEngine.calculate(
          placedCabinets: [],
          obstacles: [
            {'type': 'door', 'work': 'archway'},
          ],
          styleArchetype: 'japandi',
          wallFinish: finish,
        );
        expect(summary.wallWorkLines, isEmpty, reason: '$finish');
      }
    });

    test('a catalogue saved before wall work existed prices with the samples', () {
      final doc = jsonDecode(kDefaultCatalogJson) as Map<String, dynamic>
        ..remove('wall_work');
      final old = PriceCatalog.fromJson(doc);
      expect(old.wallWork.openings['door']!.price, 1600);
      expect(old.wallWork.finishes.keys, ['paint', 'tiles', 'panels']);
    });
  });
}
