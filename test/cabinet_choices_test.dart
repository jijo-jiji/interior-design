import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/catalog/price_catalog.dart';
import 'package:static_trace/features/layout/kitchen_layout_generator.dart';
import 'package:static_trace/features/layout/kitchen_layout_models.dart';
import 'package:static_trace/features/viewer/models/cabinet_choices.dart';

final catalog = PriceCatalog.builtIn();

Map<String, dynamic> unit(String id, String type, double left, double width,
        {double height = 850, double depth = 600, double mount = 0, String? kind, String run = 'main'}) =>
    {
      'id': id,
      'cabinet_type': type,
      if (kind != null) 'kind': kind,
      'run': run,
      'width_mm': width,
      'height_mm': height,
      'depth_mm': depth,
      'mount_mm': mount,
      if (run == 'main') 'x_mm': left + width / 2 else 'offset_mm': left + width / 2,
    };

// A 3.6 m wall (−1800 … 1800 from its centre).
const wall = {'width_mm': 3600.0, 'height_mm': 2700.0};

void main() {
  group('what a cabinet is', () {
    final choices = CabinetChoices(catalog: catalog, cabinets: [
      unit('a', 'base_600', -1800, 600),
      unit('b', 'base_400', -1200, 400, kind: 'base'),
      unit('c', 'base_drawer_600', -800, 600, kind: 'drawer'),
      unit('w', 'wall_600', -1800, 600, height: 700, depth: 320, mount: 1400),
    ], wall: wall);

    test('says what is in it, from what the 3D view draws', () {
      expect(choices.describe(choices.find('a')!), 'Floor unit with 2 doors');
      expect(choices.describe(choices.find('b')!), 'Floor unit with 1 door');
      expect(choices.describe(choices.find('c')!), 'Floor unit with 3 drawers');
      expect(choices.describe(choices.find('w')!), contains('light strip'));
      expect(choices.sizeOf(choices.find('w')!), '600 × 700 × 320 mm');
    });

    test('reads the kind of a hand-added unit from the catalogue', () {
      expect(choices.kindOf(choices.find('a')!), 'base');
      expect(choices.kindOf(choices.find('w')!), 'wall');
    });
  });

  group('its other sizes', () {
    test('are the catalogue widths of the same unit, the current one marked', () {
      final choices = CabinetChoices(
          catalog: catalog, cabinets: [unit('a', 'base_600', -1800, 600)], wall: wall);
      final sizes = choices.sizesFor('a');
      expect(sizes.map((s) => s.widthMm), catalog.layout.baseDoorWidthsMm);
      expect(sizes.where((s) => s.current).single.widthMm, 600);
      expect(sizes.map((s) => s.type), contains('base_450'));
      expect(sizes.every((s) => s.fits), isTrue, reason: 'an empty wall has room');
    });

    test('that need more room than there is say how much there is', () {
      // 600 between two neighbours: 800 and 900 can't go in.
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('l', 'base_600', -1800, 600),
        unit('m', 'base_600', -1200, 600),
        unit('r', 'base_600', -600, 600),
      ], wall: wall);
      final sizes = {for (final s in choices.sizesFor('m')) s.widthMm: s};
      expect(sizes[500]!.fits, isTrue);
      expect(sizes[800]!.fits, isFalse);
      expect(sizes[800]!.problem, 'Too wide for the 600 mm free here');
    });

    test('wall units and floor units do not get in each other\'s way', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('base', 'base_600', -1800, 600),
        unit('next', 'base_600', -1200, 600),
        unit('w', 'wall_600', -1800, 600, height: 700, depth: 320, mount: 1400),
      ], wall: wall);
      // The wall unit can widen over the floor unit next door.
      expect({for (final s in choices.sizesFor('w')) s.widthMm: s.fits}[900], isTrue);
    });

    test('a wall filler strip above does not stand in a floor unit\'s way', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('l', 'base_600', -1800, 600),
        unit('m', 'base_600', -1200, 600),
        unit('r', 'tall_600', -600, 600, height: 2100, kind: 'tall'),
        unit('f', 'filler_wall', -900, 50, height: 700, depth: 320, mount: 1400, kind: 'filler'),
      ], wall: wall);
      final m = {for (final s in choices.sizesFor('m')) s.widthMm: s};
      expect(m[600]!.fits, isTrue, reason: 'it fits where it is');
      expect(m[800]!.problem, 'Too wide for the 600 mm free here');
      // A base filler strip, though, does.
      final withBaseFiller = CabinetChoices(catalog: catalog, cabinets: [
        ...choices.cabinets.where((c) => c['id'] != 'f'),
        unit('fb', 'filler_base', -650, 50, kind: 'filler'),
      ], wall: wall);
      expect({for (final s in withBaseFiller.sizesFor('m')) s.widthMm: s.fits}[600], isFalse);
    });

    test('a tall unit has only one width, so it offers no sizes', () {
      final choices = CabinetChoices(catalog: catalog,
          cabinets: [unit('t', 'tall_600', 0, 600, height: 2100)], wall: wall);
      expect(choices.sizesFor('t'), isEmpty);
    });
  });

  group('what else goes in its place', () {
    test('a base unit can be drawers, a sink, a hob or a dishwasher', () {
      final choices = CabinetChoices(
          catalog: catalog, cabinets: [unit('a', 'base_600', -1800, 600)], wall: wall);
      final types = choices.typesFor('a');
      expect(types.first.current, isTrue, reason: 'what it is now comes first');
      expect(types.map((t) => t.kind),
          containsAll(['base', 'drawer', 'sink', 'hob', 'dishwasher']));
      // Each at the width nearest its own: a sink unit is made 800 or 900.
      expect(types.firstWhere((t) => t.kind == 'sink').widthMm, 800);
      expect(types.firstWhere((t) => t.kind == 'drawer').type, 'base_drawer_600');
      expect(types.firstWhere((t) => t.kind == 'dishwasher').type, 'dishwasher_600');
      // Not the wall or tall kinds.
      expect(types.map((t) => t.kind), isNot(contains('wall')));
      expect(types.map((t) => t.kind), isNot(contains('oven')));
    });

    test('a tall unit can be an oven tower or a fridge recess', () {
      final choices = CabinetChoices(catalog: catalog,
          cabinets: [unit('t', 'tall_600', 0, 600, height: 2100)], wall: wall);
      expect(choices.typesFor('t').map((t) => t.kind), containsAll(['tall', 'oven', 'fridge']));
    });

    test('a wall unit can be a rangehood', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('w', 'wall_600', 0, 600, height: 700, depth: 320, mount: 1400)
      ], wall: wall);
      expect(choices.typesFor('w').map((t) => t.kind), contains('hood'));
    });

    test('a corner unit and a filler offer nothing to change', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('k', 'corner_900', -1800, 900, kind: 'corner'),
        unit('f', 'filler_base', -900, 50, kind: 'filler'),
      ], wall: wall);
      expect(choices.sizesFor('k'), isEmpty);
      expect(choices.typesFor('k'), isEmpty);
      expect(choices.typesFor('f'), isEmpty);
    });
  });

  group('making the change', () {
    test('keeps the cabinet in its place: its left end stays put', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('a', 'base_600', -1800, 600),
        unit('b', 'base_600', -1000, 600),
      ], wall: wall);
      final to = choices.sizesFor('a').firstWhere((s) => s.widthMm == 800);
      final after = choices.swap('a', to)!;
      final a = after.firstWhere((c) => c['id'] == 'a');
      expect(a['x_mm'], -1400, reason: 'left end still at −1800');
      expect(a['cabinet_type'], 'base_800');
      expect(a['label'], 'Base 800');
      expect(a['width_mm'], 800);
      expect(a['generated'], isTrue);
      expect(after.length, 2);
      expect(after.firstWhere((c) => c['id'] == 'b'), choices.find('b'),
          reason: 'neighbours are not moved');
    });

    test('grows the other way when the right side is taken', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('a', 'base_600', -600, 600), // free to its left
        unit('b', 'base_600', 0, 600),
      ], wall: wall);
      final to = choices.sizesFor('a').firstWhere((s) => s.widthMm == 900);
      final a = choices.swap('a', to)!.firstWhere((c) => c['id'] == 'a');
      expect(a['x_mm'], -450, reason: 'right end stays at 0');
    });

    test('a type change keeps its height band and its id', () {
      final choices = CabinetChoices(
          catalog: catalog, cabinets: [unit('a', 'base_600', -1800, 600)], wall: wall);
      final drawers = choices.typesFor('a').firstWhere((t) => t.kind == 'drawer');
      final a = choices.swap('a', drawers)!.single;
      expect(a['id'], 'a');
      expect(a['kind'], 'drawer');
      expect(a['cabinet_type'], 'base_drawer_600');
      expect(a['height_mm'], 850);
    });

    test('refuses what does not fit (and changes nothing)', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('l', 'base_600', -1800, 600),
        unit('m', 'base_600', -1200, 600),
        unit('r', 'base_600', -600, 600),
      ], wall: wall);
      final wide = choices.sizesFor('m').firstWhere((s) => s.widthMm == 900);
      expect(choices.swap('m', wide), isNull);
      expect(choices.swap('nobody', wide), isNull);
    });

    test('a priced unit of a new width is priced by width', () {
      expect(catalog.unitPrice('base_450', 450), 340 - 1.5 * 40);
    });
  });

  group('doors and windows on the wall', () {
    // A door 900 wide, 1000 mm from the left end of the wall: −800 … 100.
    const door = {
      'type': 'door',
      'distance_from_left_mm': 1000.0,
      'distance_from_floor_mm': 0.0,
      'width_mm': 900.0,
      'height_mm': 2100.0,
    };
    // A window from 1000 up, over the worktop.
    const window = {
      'type': 'window',
      'distance_from_left_mm': 1000.0,
      'distance_from_floor_mm': 1000.0,
      'width_mm': 900.0,
      'height_mm': 1200.0,
    };

    test('a floor unit can\'t grow into a door (or its clearance)', () {
      // A neighbour on its left, the door (from −850 with clearance) on its right.
      final choices = CabinetChoices(
          catalog: catalog,
          cabinets: [
            unit('l', 'base_400', -1800, 400, kind: 'base'),
            unit('a', 'base_500', -1400, 500, kind: 'base'),
          ],
          wall: wall,
          obstacles: [door]);
      final sizes = {for (final s in choices.sizesFor('a')) s.widthMm: s};
      expect(sizes[500]!.fits, isTrue);
      expect(sizes[600]!.problem, 'Too wide for the 550 mm free here');
      // Without the door, there would be room.
      final open = CabinetChoices(catalog: catalog, cabinets: choices.cabinets, wall: wall);
      expect({for (final s in open.sizesFor('a')) s.widthMm: s.fits}[600], isTrue);
    });

    test('a window blocks wall units but not the floor units under it', () {
      final cabinets = [
        unit('lb', 'base_400', -1800, 400, kind: 'base'),
        unit('base', 'base_500', -1400, 500, kind: 'base'),
        unit('lw', 'wall_400', -1800, 400, height: 700, depth: 320, mount: 1400, kind: 'wall'),
        unit('w', 'wall_500', -1400, 500, height: 700, depth: 320, mount: 1400, kind: 'wall'),
      ];
      final choices = CabinetChoices(catalog: catalog, cabinets: cabinets, wall: wall, obstacles: [window]);
      final base = {for (final s in choices.sizesFor('base')) s.widthMm: s.fits};
      expect(base[900], isTrue, reason: 'a floor unit may go under the window');
      final wallUnit = {for (final s in choices.sizesFor('w')) s.widthMm: s.problem};
      expect(wallUnit[500], isNull);
      expect(wallUnit[600], 'Too wide for the 550 mm free here',
          reason: 'a wall unit may not cover the window');
    });
  });

  group('the side wall of an L', () {
    test('runs from past the corner unit to the end of the side wall', () {
      final choices = CabinetChoices(catalog: catalog, cabinets: [
        unit('k', 'corner_900', -1800, 900, kind: 'corner'),
        unit('s', 'base_600', 900, 600, run: 'return'),
      ], wall: {...wall, 'shape': 'lShape', 'return_mm': 2000.0});
      final sizes = {for (final s in choices.sizesFor('s')) s.widthMm: s};
      // 900 … 2000: 1100 mm of side wall.
      expect(sizes[900]!.fits, isTrue);
      final s = choices.swap('s', sizes[900]!)!.firstWhere((c) => c['id'] == 's');
      expect(s['offset_mm'], 1350);
      expect(s['run'], 'return');
      expect(s.containsKey('x_mm'), isFalse);
    });
  });

  group('every layout the app makes', () {
    test('every unit fits as it is, in every A, B and C, single wall and L', () {
      final rooms = <Map<String, dynamic>>[
        {
          'wall': {'width_mm': 3600.0, 'height_mm': 2700.0},
          'obstacles': [
            {'type': 'window', 'distance_from_left_mm': 1200.0, 'distance_from_floor_mm': 1000.0, 'width_mm': 1200.0, 'height_mm': 1100.0},
          ],
        },
        {
          'wall': {'width_mm': 3000.0, 'height_mm': 2700.0, 'shape': 'lShape', 'return_mm': 2400.0},
          'obstacles': [],
        },
        {
          'wall': {'width_mm': 4200.0, 'height_mm': 2700.0},
          'obstacles': [
            {'type': 'door', 'distance_from_left_mm': 3000.0, 'distance_from_floor_mm': 0.0, 'width_mm': 900.0, 'height_mm': 2100.0},
          ],
        },
      ];
      for (final room in rooms) {
        final variants = KitchenLayoutGenerator.forCatalog(catalog).generateAll(KitchenRoom.fromPayload(room));
        for (final v in variants) {
          final cabinets = v.toPlacedCabinets();
          final choices = CabinetChoices(
              catalog: catalog,
              cabinets: cabinets,
              wall: room['wall'] as Map<String, dynamic>,
              obstacles: room['obstacles'] as List);
          for (final c in cabinets) {
            final id = c['id'] as String;
            final current = [...choices.sizesFor(id), ...choices.typesFor(id)].where((o) => o.current);
            for (final o in current) {
              expect(o.fits, isTrue, reason: '${room['wall']} ${v.key} $id ${o.label}: ${o.problem}');
            }
          }
        }
      }
    });
  });
}
