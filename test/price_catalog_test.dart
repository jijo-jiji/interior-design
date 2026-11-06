import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/catalog/default_catalog.g.dart';
import 'package:static_trace/features/catalog/price_catalog.dart';
import 'package:static_trace/features/viewer/models/cpq_engine.dart';

Map<String, dynamic> sample() =>
    jsonDecode(kDefaultCatalogJson) as Map<String, dynamic>;

void main() {
  test('the embedded sample catalogue is the JSON the server seeds from', () {
    // Fails when assets/catalog/default_catalog.json changed but
    // `python tool/gen_default_catalog.py` was not run.
    final onDisk = jsonDecode(
            File('assets/catalog/default_catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(sample(), onDisk);
  });

  test('the built-in catalogue is version 1 and marked as a sample', () {
    final catalog = PriceCatalog.builtIn();
    expect(catalog.version, 1);
    expect(catalog.isPlaceholder, isTrue);
    expect(catalog.taxLabel, 'SST');
    expect(catalog.modules.map((m) => m.type),
        containsAll(['base_800', 'base_600', 'wall_600', 'tall_600']));
  });

  group('unit price (same figures as the server tests)', () {
    final catalog = PriceCatalog.builtIn();
    const cases = <(String, double, double)>[
      ('base_800', 800, 420), // fixed module
      ('base_600', 600, 340),
      ('sink_600', 600, 480), // appliance module
      ('base_450', 450, 280), // 340 + (450-600)/100*40
      ('base_drawer_900', 900, 460),
      ('base_sink_800', 800, 560),
      ('base_hob_600', 600, 520),
      ('wall_900', 900, 400),
      ('wall_450', 450, 220),
      ('tall_700', 700, 660),
      ('filler_base', 100, 40),
      ('filler_wall', 75, 30),
      ('island_1200', 1200, 300), // no family: the unknown-module price
    ];
    for (final (type, width, price) in cases) {
      test('$type at $width mm costs $price', () {
        expect(catalog.unitPrice(type, width), closeTo(price, 1e-9));
      });
    }

    test('a missing width prices at the reference width', () {
      expect(catalog.unitPrice('base_450', null), 340);
    });

    test('the longest prefix wins', () {
      expect(catalog.familyFor('base_sink_900')?.id, 'sink_unit');
      expect(catalog.familyFor('base_drawer_450')?.id, 'drawer');
      expect(catalog.familyFor('base_450')?.id, 'base');
      expect(catalog.familyFor('sink_600')?.id, 'sink');
      expect(catalog.familyFor('nothing'), isNull);
    });
  });

  test('fillers are trim: no installation labour', () {
    final summary = CPQEngine.calculate(
      placedCabinets: [
        {'cabinet_type': 'base_600', 'width_mm': 600},
        {'cabinet_type': 'filler_base', 'width_mm': 100},
      ],
      obstacles: [],
      styleArchetype: 'japandi',
    );
    expect(summary.totalModules, 2);
    expect(summary.labourModules, 1);
    expect(summary.labourTotal, 120);
    expect(summary.subtotal, 340 + 40 + 120);
  });

  test('an edited catalogue changes the price, and the quote says which', () {
    final doc = sample();
    doc['version'] = 4;
    ((doc['modules'] as List).first as Map)['price'] = 500;
    final edited = PriceCatalog.fromJson(doc);
    final cabinets = [
      {'cabinet_type': 'base_800', 'width_mm': 800},
    ];

    final before = CPQEngine.calculate(
        placedCabinets: cabinets, obstacles: [], styleArchetype: 'japandi');
    final after = CPQEngine.calculate(
        placedCabinets: cabinets,
        obstacles: [],
        styleArchetype: 'japandi',
        catalog: edited);

    expect(before.baseCabinetTotal, 420);
    expect(before.catalogVersion, 1);
    expect(after.baseCabinetTotal, 500);
    expect(after.catalogVersion, 4);
  });

  test('the screens\' price tables come from the current catalogue', () {
    final original = PriceCatalog.current;
    addTearDown(() => PriceCatalog.current = original);

    final doc = sample();
    ((doc['modules'] as List).first as Map)['price'] = 777;
    ((doc['style_options'] as Map)['japandi'] as Map)['name'] = 'Renamed';
    ((doc['tax'] as Map))['rate'] = 0.06;
    PriceCatalog.current = PriceCatalog.fromJson(doc);

    expect(CPQEngine.cabinetPrices['base_800'], 777);
    expect(CPQEngine.styleNames['japandi'], 'Renamed');
    expect(CPQEngine.gstRate, 0.06);
  });
}
