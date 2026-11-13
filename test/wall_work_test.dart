import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/catalog/price_catalog.dart';
import 'package:static_trace/features/viewer/models/wall_work.dart';

void main() {
  final catalog = PriceCatalog.builtIn();
  const wall = {'width_mm': 3600.0, 'height_mm': 2700.0};
  const window = {
    'type': 'window',
    'distance_from_left_mm': 1200.0,
    'distance_from_floor_mm': 1000.0,
    'width_mm': 1200.0,
    'height_mm': 1100.0,
  };

  Map<String, dynamic> base(String id, double xMm, {double w = 600}) => {
        'id': id,
        'cabinet_type': 'base_${w.round()}',
        'label': 'Base ${w.round()}',
        'kind': 'base',
        'run': 'main',
        'width_mm': w,
        'height_mm': 850.0,
        'depth_mm': 600.0,
        'mount_mm': 0.0,
        'x_mm': xMm,
      };
  Map<String, dynamic> wallUnit(String id, double xMm, {double w = 600}) => {
        ...base(id, xMm, w: w),
        'cabinet_type': 'wall_${w.round()}',
        'label': 'Wall ${w.round()}',
        'kind': 'wall',
        'height_mm': 700.0,
        'depth_mm': 320.0,
        'mount_mm': 1400.0,
      };

  WallWorkModel model({
    List<Map<String, dynamic>> obstacles = const [],
    List<Map<String, dynamic>> cabinets = const [],
  }) =>
      WallWorkModel(
          catalog: catalog,
          wall: wall,
          obstacles: obstacles,
          cabinets: cabinets);

  group('what is on the wall', () {
    test('names and sizes', () {
      expect(WallWorkModel.nameOf(window), 'Window');
      expect(WallWorkModel.nameOf({...window, 'work': 'window'}), 'New window');
      expect(WallWorkModel.nameOf({'type': 'door', 'work': 'hidden_door'}),
          'Hidden door');
      expect(WallWorkModel.sizeOf(window), '1200 × 1100 mm');
      expect(WallWorkModel.isNew(window), isFalse);
    });

    test('the kinds offered come from the catalogue', () {
      expect(model().kinds, ['hidden_door', 'door', 'window']);
    });
  });

  group('the finish', () {
    test('is priced on the wall less its doors and windows', () {
      // 3.6 × 2.7 = 9.72 m², less the window 1.2 × 1.1 = 1.32 → 8.40 m².
      expect(model(obstacles: [window]).finishAreaM2, 8.4);
      expect(model().finish('tiles', colour: '#f4f2ee'),
          {'kind': 'tiles', 'area_m2': 9.72, 'colour': '#f4f2ee'});
    });

    test('an opening partly off the wall counts only where it is on it', () {
      final o = {...window, 'distance_from_left_mm': 3000.0};
      // 600 of its 1200 mm are on the wall: 9.72 - 0.6 × 1.1 = 9.06.
      expect(model(obstacles: [o]).finishAreaM2, 9.06);
    });
  });

  group('adding an opening', () {
    test('a hidden door on an empty wall goes where the wall was tapped', () {
      final next = model().add('hidden_door', nearMm: 2600)!;
      final door = next.single;
      expect(door['type'], 'door', reason: 'a door to the layouts and checks');
      expect(door['work'], 'hidden_door');
      expect(door['width_mm'], 800);
      expect(door['height_mm'], 2100);
      expect(door['distance_from_floor_mm'], 0);
      expect(door['distance_from_left_mm'], 2200, reason: 'centred on 2600');
    });

    test('near the wall end it stays clear of it', () {
      final door = model().add('door', nearMm: 100)!.single;
      expect(door['distance_from_left_mm'], 50, reason: 'the door clearance');
    });

    test('a window takes its sill and height from the catalogue', () {
      final w = model().add('window')!.single;
      expect(w['type'], 'window');
      expect(w['distance_from_floor_mm'], 1050);
      expect(w['height_mm'], 1000);
      expect(w['distance_from_left_mm'], 1350,
          reason: 'the middle of the wall');
    });

    test('a door keeps clear of cabinets; a window only of those at its height',
        () {
      // Base units along the left 2400 mm; wall units only over the left 1200.
      final cabinets = [
        base('b1', -1500),
        base('b2', -900),
        base('b3', -300),
        base('b4', 300),
        wallUnit('w1', -1500),
        wallUnit('w2', -900),
      ];
      final m = model(cabinets: cabinets);
      final door = m.add('door', nearMm: 500)!.single;
      // Free for a door: from 2400 + 50 to 3600 - 50: 1100 mm; 800 wide.
      expect(door['distance_from_left_mm'], 2450);
      // A window above the worktop can go over the base units, past the
      // wall units (1200 + 50).
      final win = m.add('window', nearMm: 1500)!.single;
      expect(win['distance_from_left_mm'], 1250);
    });

    test('no room: null, and the card is told why', () {
      final full = [
        for (var i = 0; i < 6; i++) base('b$i', -1500.0 + 600 * i),
      ];
      final m = model(cabinets: full);
      expect(m.add('hidden_door'), isNull);
      expect(m.whyNot('hidden_door'),
          'No free wall for it: move or remove cabinets first');
      expect(m.whyNot('window'), isNull, reason: 'a window clears floor units');
    });

    test('a door needs a free stretch at least as wide as it', () {
      final cabinets = [
        for (var i = 0; i < 4; i++) base('b$i', -1500.0 + 600 * i),
        base('b4', 825, w: 450),
        base('b5', 1200, w: 300),
      ];
      // Base units cover 0..3150: 350 mm free before the wall end. No door.
      expect(model(cabinets: cabinets).add('door'), isNull);
      final fewer = cabinets.take(4).toList(); // 0..2400: 1100 mm free
      final d = model(cabinets: fewer).add('door', nearMm: 3000)!.single;
      expect(d['width_mm'], 800);
      expect(model(cabinets: fewer).whyNot('door'), isNull);
    });

    test('the side wall of an L does not block the main wall', () {
      final m = model(cabinets: [
        {...base('r1', 0), 'run': 'return', 'offset_mm': 1200.0},
      ]);
      expect(m.add('door', nearMm: 1800), isNotNull);
    });
  });

  group('changing one', () {
    final door = {
      'type': 'door',
      'distance_from_left_mm': 2400.0,
      'distance_from_floor_mm': 0.0,
      'width_mm': 800.0,
      'height_mm': 2100.0,
      'work': 'hidden_door',
    };

    test('moves within its free stretch, and no further', () {
      final m = model(obstacles: [
        window,
        {...door, 'distance_from_left_mm': 2600.0}
      ]);
      expect(m.move(1, 50)![1]['distance_from_left_mm'], 2650);
      expect(m.move(1, 5000)![1]['distance_from_left_mm'], 3600 - 50 - 800);
      expect(m.move(1, -5000)![1]['distance_from_left_mm'], 2450,
          reason: 'stops at the window (ends at 2400) plus clearance');
      expect(
          model(obstacles: [
            window,
            {...door, 'distance_from_left_mm': 2450.0}
          ]).move(1, -50),
          isNull,
          reason: 'already against the window');
    });

    test('resizes keeping its left edge, else its right; or says why not', () {
      final m = model(obstacles: [
        {...door, 'distance_from_left_mm': 2500.0}
      ]);
      final wider = m.resize(0, 900)!;
      expect(wider[0]['distance_from_left_mm'], 2500);
      expect(wider[0]['width_mm'], 900);
      final atEnd = model(obstacles: [
        {...door, 'distance_from_left_mm': 2750.0}
      ]);
      final w = atEnd.resize(0, 900)!;
      expect(w[0]['distance_from_left_mm'], 2650, reason: 'right edge kept');
      // A base unit from 2100 to 2700: 800 mm free to the wall end's
      // clearance, exactly the door.
      final tight = model(obstacles: [
        {...door, 'distance_from_left_mm': 2750.0}
      ], cabinets: [
        base('b', 600, w: 600)
      ]);
      expect(tight.resize(0, 900), isNull);
      final widths = tight.widthsFor(0);
      expect(widths.map((w) => w.widthMm), [700, 800, 900]);
      expect(widths.firstWhere((w) => w.widthMm == 800).current, isTrue);
      expect(widths.firstWhere((w) => w.widthMm == 900).problem,
          'Too wide for the 800 mm free here');
      expect(widths.firstWhere((w) => w.widthMm == 700).problem, isNull);
    });

    test('only an opening to be made can be taken out', () {
      final m = model(obstacles: [window, door]);
      expect(m.remove(1), [window]);
      expect(m.remove(0), [window, door],
          reason: 'the window is part of the room');
    });
  });
}
