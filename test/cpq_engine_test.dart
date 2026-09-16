import 'package:flutter_test/flutter_test.dart';
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
      // gst = 94.0
      // total = 1034.0
      expect(summary.totalModules, 2);
      expect(summary.baseCabinetTotal, 420.00);
      expect(summary.wallCabinetTotal, 280.00);
      expect(summary.labourTotal, 240.00);
      expect(summary.subtotal, 940.00);
      expect(summary.gst, 94.00);
      expect(summary.totalPrice, 1034.00);
      expect(summary.monthlyPayment, closeTo(1034.00 / 36 * 1.06, 0.01));
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
          {'type': 'door'},   // -80
        ],
        styleArchetype: 'japandi',
      );

      // materials: 420
      // labour: 120
      // allowance: -130
      // subtotal: 420 + 120 - 130 = 410
      expect(summary.obstacleAllowance, -130.00);
      expect(summary.subtotal, 410.00);
      expect(summary.gst, 41.00);
      expect(summary.totalPrice, 451.00);
    });

    test('Benchtop calculation adds engineered quartz surface per linear metre', () {
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
      // 1.4m * $380 = $532 benchtop total
      // cabinets: 420 + 340 = 760
      // labour: 2 * 120 = 240
      // subtotal: 760 + 532 + 240 = 1532
      // gst: 153.20
      // total: 1685.20
      expect(summary.benchtopLinearMetres, closeTo(1.4, 0.01));
      expect(summary.benchtopTotal, closeTo(532.00, 0.01));
      expect(summary.benchtopMaterial, 'Calacatta Engineered Quartz');
      expect(summary.subtotal, closeTo(1532.00, 0.01));
      expect(summary.totalPrice, closeTo(1685.20, 0.01));
    });
  });
}
