import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/models/cpq_engine.dart';

/// Mobile half of the pricing contract. It prices with the built-in sample
/// catalogue, the same one the other two engines use.
///
/// The figures live in test/fixtures/pricing_cases.json and are shared with
/// backend/test_pricing_contract.py. The app shows the client a price; the
/// backend prints the one they sign. If the two engines drift apart, one of
/// these two suites fails.
void main() {
  final fixtureFile = File('test/fixtures/pricing_cases.json');
  final fixture =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  group('Pricing contract — CPQEngine matches the backend quote', () {
    for (final testCase in cases) {
      test(testCase['name'] as String, () {
        final expected = testCase['expected'] as Map<String, dynamic>;

        final summary = CPQEngine.calculate(
          placedCabinets: (testCase['placed_cabinets'] as List)
              .map((c) => Map<String, dynamic>.from(c as Map))
              .toList(),
          obstacles: testCase['obstacles'] as List,
          styleArchetype: testCase['style_archetype'] as String,
          benchtopMaterial: testCase['benchtop_material'] as String?,
          wallFinish: (testCase['wall_finish'] as Map?)?.cast<String, dynamic>(),
        );

        expect(
          summary.subtotal,
          closeTo((expected['subtotal'] as num).toDouble(), 0.01),
          reason: 'subtotal disagrees with the backend quote',
        );
        expect(
          summary.gst,
          closeTo((expected['gst'] as num).toDouble(), 0.01),
          reason: 'SST disagrees with the backend quote',
        );
        expect(
          summary.totalPrice,
          closeTo((expected['total_price'] as num).toDouble(), 0.01),
          reason: 'total disagrees with the backend quote — the client would '
              'sign a different number than the app displayed',
        );
      });
    }
  });

  test('fixture covers the cases that have broken before', () {
    final names = cases.map((c) => c['name'] as String).toSet();
    expect(names, contains('two_base_japandi_quartz')); // benchtop priced
    expect(names, contains('mixed_nordic_quartz')); // corner run + multiplier
    expect(names, contains('unknown_type_falls_back')); // unpriced type
    expect(names, contains('empty_layout')); // nothing placed yet
    // Sizes the layout generator makes that are not fixed modules.
    expect(names, contains('generated_l_kitchen_priced_by_width'));
    expect(names, contains('generated_kitchen_minimalist_granite_window'));
    expect(names, contains('filler_widths_round_to_the_sen'));
  });
}
