import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/layout/kitchen_catalog.dart';
import 'package:static_trace/features/layout/kitchen_layout_generator.dart';
import 'package:static_trace/features/layout/kitchen_layout_models.dart';

const _tol = 10.5; // scribing tolerance + rounding
const _catalog = KitchenCatalog.placeholder;
const _rules = KitchenRules.placeholder;
const _generator = KitchenLayoutGenerator();

WallOpening _window(double left, double width,
        {double sill = 1000, double height = 1100}) =>
    WallOpening(
        type: OpeningType.window,
        leftMm: left,
        floorMm: sill,
        widthMm: width,
        heightMm: height);

WallOpening _door(double left, double width) => WallOpening(
    type: OpeningType.door,
    leftMm: left,
    floorMm: 0,
    widthMm: width,
    heightMm: 2100);

bool _overlaps(double a0, double a1, double b0, double b1) =>
    a0 < b1 - 0.5 && a1 > b0 + 0.5;

/// Rules every generated layout must satisfy, whatever the room.
void _expectValid(KitchenRoom room, LayoutVariant v) {
  final reason = '${v.key} ${v.name}';
  final floor = v.modules.where((m) => !m.isWallMounted).toList();
  final hung = v.modules.where((m) => m.isWallMounted).toList();

  // Inside the walls.
  for (final m in v.modules) {
    final len = m.wall == RunWall.main ? room.mainWallMm : room.returnWallMm;
    expect(m.startMm, greaterThanOrEqualTo(-0.5),
        reason: '$reason ${m.label} starts before the wall');
    expect(m.endMm, lessThanOrEqualTo(len + 0.5),
        reason: '$reason ${m.label} runs past the wall');
  }

  // No overlaps on the same wall and level.
  for (final group in [floor, hung]) {
    for (final wall in RunWall.values) {
      final onWall = group.where((m) => m.wall == wall).toList()
        ..sort((a, b) => a.startMm.compareTo(b.startMm));
      for (var i = 1; i < onWall.length; i++) {
        expect(
            onWall[i].startMm, greaterThanOrEqualTo(onWall[i - 1].endMm - 0.5),
            reason:
                '$reason ${onWall[i - 1].label} overlaps ${onWall[i].label}');
      }
    }
  }

  // Nothing on the return wall within the main run's depth of the corner.
  for (final m in floor.where((m) => m.wall == RunWall.returnWall)) {
    expect(m.startMm, greaterThanOrEqualTo(_catalog.baseDepthMm - 0.5),
        reason: reason);
  }

  // Floor modules stay clear of doors and low windows.
  for (final o in room.openings) {
    final isDoor = o.type == OpeningType.door;
    final lowWindow = !isDoor && o.floorMm < _catalog.counterHeightMm;
    if (!isDoor && !lowWindow) continue;
    final clr = isDoor ? _rules.doorClearanceMm : 0.0;
    for (final m in floor.where((m) => m.wall == RunWall.main)) {
      expect(_overlaps(m.startMm, m.endMm, o.leftMm - clr, o.rightMm + clr),
          isFalse,
          reason: '$reason ${m.label} blocks a ${o.type.name}');
    }
  }

  final windowZones = [
    for (final o in room.openings.where((o) => o.type == OpeningType.window))
      (
        o.leftMm - _rules.windowClearanceMm,
        o.rightMm + _rules.windowClearanceMm
      ),
  ];

  // Hob: at most one, not under a window, worktop on both sides, far enough from the sink.
  final hobs = v.ofKind(ModuleKind.hob).toList();
  expect(hobs.length, lessThanOrEqualTo(1), reason: reason);
  for (final h in hobs) {
    if (h.wall == RunWall.main) {
      for (final z in windowZones) {
        expect(_overlaps(h.startMm, h.endMm, z.$1, z.$2), isFalse,
            reason: '$reason hob under a window');
      }
    }
    double counter(bool right) {
      var total = 0.0;
      var edge = right ? h.endMm : h.startMm;
      while (true) {
        final next = floor.where((m) =>
            m.wall == h.wall &&
            m.kind != ModuleKind.tall &&
            ((right ? m.startMm - edge : edge - m.endMm).abs() <= _tol));
        if (next.isEmpty) return total;
        final n = next.first;
        total += n.widthMm;
        edge = right ? n.endMm : n.startMm;
      }
    }

    expect(counter(false), greaterThanOrEqualTo(_rules.minHobSideCounterMm),
        reason: '$reason worktop left of hob');
    expect(counter(true), greaterThanOrEqualTo(_rules.minHobSideCounterMm),
        reason: '$reason worktop right of hob');

    for (final s in v.ofKind(ModuleKind.sink).where((s) => s.wall == h.wall)) {
      final gap =
          s.endMm <= h.startMm ? h.startMm - s.endMm : s.startMm - h.endMm;
      expect(gap, greaterThanOrEqualTo(_rules.minSinkToHobMm - 0.5),
          reason: '$reason sink too close to hob');
    }
  }

  // Tall units never in front of a window, and never right against the sink.
  for (final t in v.ofKind(ModuleKind.tall)) {
    if (t.wall == RunWall.main) {
      for (final z in windowZones) {
        expect(_overlaps(t.startMm, t.endMm, z.$1, z.$2), isFalse,
            reason: '$reason tall unit over a window');
      }
    }
    for (final s in v.ofKind(ModuleKind.sink).where((s) => s.wall == t.wall)) {
      final gap =
          s.endMm <= t.startMm ? t.startMm - s.endMm : s.startMm - t.endMm;
      expect(gap, greaterThanOrEqualTo(_rules.minSinkToTallMm - 0.5),
          reason: '$reason sink against a tall unit');
    }
  }

  // Wall cabinets: not over the hob, a tall unit, a door, or a window in their band.
  for (final w in hung) {
    for (final m in floor.where((m) =>
        m.wall == w.wall &&
        (m.kind == ModuleKind.hob || m.kind == ModuleKind.tall))) {
      expect(_overlaps(w.startMm, w.endMm, m.startMm, m.endMm), isFalse,
          reason: '$reason ${w.label} over ${m.label}');
    }
    if (w.wall != RunWall.main) continue;
    for (final o in room.openings) {
      final inBand = o.type == OpeningType.door ||
          (o.floorMm < _catalog.wallBandTopMm &&
              o.topMm > _catalog.wallMountMm);
      if (!inBand) continue;
      final clr = o.type == OpeningType.door
          ? _rules.doorClearanceMm
          : _rules.windowClearanceMm;
      expect(_overlaps(w.startMm, w.endMm, o.leftMm - clr, o.rightMm + clr),
          isFalse,
          reason: '$reason ${w.label} over a ${o.type.name}');
    }
  }
}

/// Floor modules on the main wall cover [from, to] with no gap above the scribing tolerance.
void _expectCovered(LayoutVariant v, double from, double to) {
  final floor = v.modules
      .where((m) => !m.isWallMounted && m.wall == RunWall.main)
      .toList()
    ..sort((a, b) => a.startMm.compareTo(b.startMm));
  var edge = from;
  for (final m in floor.where((m) => m.endMm > from && m.startMm < to)) {
    expect(m.startMm - edge, lessThanOrEqualTo(_tol),
        reason: '${v.key}: gap before ${m.label} at ${m.startMm}');
    edge = m.endMm;
  }
  expect(to - edge, lessThanOrEqualTo(_tol),
      reason: '${v.key}: gap at the end of the run');
}

void main() {
  group('single wall with a window', () {
    final room = KitchenRoom(
        mainWallMm: 3600, wallHeightMm: 2700, openings: [_window(1200, 1200)]);
    final variants = _generator.generateAll(room);

    test('produces A/B/C variants that all follow the rules', () {
      expect(variants.map((v) => v.key), ['A', 'B', 'C']);
      for (final v in variants) {
        _expectValid(room, v);
        _expectCovered(v, 0, room.mainWallMm);
      }
    });

    test('centres the sink under the window', () {
      for (final v in variants) {
        final sink = v.ofKind(ModuleKind.sink).single;
        expect((sink.centerMm - 1800).abs(),
            lessThanOrEqualTo(_rules.maxSinkShiftFromWindowMm),
            reason: v.key);
      }
    });

    test('every variant has a hob', () {
      for (final v in variants) {
        expect(v.ofKind(ModuleKind.hob), hasLength(1), reason: v.key);
      }
    });

    test(
        'variants differ: Value has no tall unit, Balanced has one, Premium uses drawers',
        () {
      expect(variants[0].ofKind(ModuleKind.tall), isEmpty);
      expect(variants[1].ofKind(ModuleKind.tall), hasLength(1));
      final premiumBase = variants[2].modules.where(
          (m) => m.kind == ModuleKind.base || m.kind == ModuleKind.drawer);
      expect(
          premiumBase.where((m) => m.kind == ModuleKind.drawer).length,
          greaterThan(
              premiumBase.where((m) => m.kind == ModuleKind.base).length));
    });

    test('adds wall cabinets beside the window', () {
      for (final v in variants) {
        expect(v.ofKind(ModuleKind.wall), isNotEmpty, reason: v.key);
      }
    });
  });

  test('long plain wall fits two tall units in Premium', () {
    const room = KitchenRoom(mainWallMm: 5000, wallHeightMm: 2700);
    final variants = _generator.generateAll(room);
    for (final v in variants) {
      _expectValid(room, v);
      _expectCovered(v, 0, room.mainWallMm);
    }
    expect(variants[2].ofKind(ModuleKind.tall), hasLength(2));
    expect(variants[0].warnings, isEmpty);
  });

  test('L-shape gets a corner unit and uses the return wall', () {
    const room = KitchenRoom(
      mainWallMm: 3000,
      wallHeightMm: 2700,
      shape: KitchenShape.lShape,
      returnWallMm: 2400,
    );
    for (final v in _generator.generateAll(room)) {
      _expectValid(room, v);
      final corner = v.ofKind(ModuleKind.corner).single;
      expect(corner.startMm, 0);
      expect(corner.wall, RunWall.main);
      final returnFloor = v.modules
          .where((m) => m.wall == RunWall.returnWall && !m.isWallMounted);
      expect(returnFloor, isNotEmpty, reason: v.key);
      expect(returnFloor.every((m) => m.startMm >= _catalog.cornerSizeMm - 0.5),
          isTrue,
          reason: v.key);
      _expectCovered(v, 0, room.mainWallMm);
    }
  });

  test('keeps cabinets clear of a door and splits the run around it', () {
    final room = KitchenRoom(
        mainWallMm: 4200,
        wallHeightMm: 2700,
        openings: [_door(3300, 800), _window(800, 1000)]);
    for (final v in _generator.generateAll(room)) {
      _expectValid(room, v);
      _expectCovered(v, 0, 3300 - _rules.doorClearanceMm);
    }
  });

  test('a window with a low sill blocks the base run in front of it', () {
    final room = KitchenRoom(
        mainWallMm: 4000,
        wallHeightMm: 2700,
        openings: [_window(2800, 900, sill: 400, height: 1500)]);
    for (final v in _generator.generateAll(room)) {
      _expectValid(room, v);
    }
  });

  test('short wall drops the hob and says why', () {
    const room = KitchenRoom(mainWallMm: 1500, wallHeightMm: 2700);
    for (final v in _generator.generateAll(room)) {
      _expectValid(room, v);
      expect(v.ofKind(ModuleKind.hob), isEmpty, reason: v.key);
      expect(v.ofKind(ModuleKind.sink), hasLength(1), reason: v.key);
      expect(v.warnings.join(' '), contains('sink only'), reason: v.key);
    }
  });

  test('a wall too short for any module stays empty and says so', () {
    const room = KitchenRoom(mainWallMm: 250, wallHeightMm: 2700);
    for (final v in _generator.generateAll(room)) {
      expect(v.modules, isEmpty);
      expect(v.warnings.join(' '), contains('storage only'));
    }
  });

  test('low ceiling: no tall units or wall cabinets', () {
    const room = KitchenRoom(mainWallMm: 3600, wallHeightMm: 2000);
    final v = _generator.generate(room, LayoutTier.balanced);
    _expectValid(room, v);
    expect(v.ofKind(ModuleKind.tall), isEmpty);
    expect(v.ofKind(ModuleKind.wall), isEmpty);
    expect(v.warnings, isNotEmpty);
  });

  test('is deterministic', () {
    final room = KitchenRoom(
        mainWallMm: 3725, wallHeightMm: 2600, openings: [_window(900, 1100)]);
    final a =
        _generator.generateAll(room).map((v) => v.toPlacedCabinets()).toList();
    final b =
        _generator.generateAll(room).map((v) => v.toPlacedCabinets()).toList();
    expect(a, b);
  });

  test('handles awkward wall lengths in 5 mm steps without breaking the rules',
      () {
    for (var w = 1800.0; w <= 4800; w += 5) {
      final room = KitchenRoom(
          mainWallMm: w,
          wallHeightMm: 2700,
          openings: [_window(w / 2 - 500, 1000)]);
      for (final v in _generator.generateAll(room)) {
        _expectValid(room, v);
        _expectCovered(v, 0, w);
      }
    }
  });

  group('payload', () {
    test('reads the template (L-shape) payload', () {
      final room = KitchenRoom.fromPayload({
        'wall': {
          'width_mm': 4000.0,
          'height_mm': 2700.0,
          'depth_mm': 150.0,
          'shape': 'lShape',
          'return_mm': 2500.0
        },
        'obstacles': <Map<String, dynamic>>[],
      });
      expect(room.shape, KitchenShape.lShape);
      expect(room.returnWallMm, 2500);
    });

    test('reads traced obstacles', () {
      final room = KitchenRoom.fromPayload({
        'wall': {'width_mm': 3600.0, 'height_mm': 2700.0, 'depth_mm': 150.0},
        'obstacles': [
          {
            'type': 'window',
            'distance_from_left_mm': 1200.0,
            'distance_from_floor_mm': 1000.0,
            'width_mm': 1200.0,
            'height_mm': 1100.0
          },
          {
            'type': 'door',
            'distance_from_left_mm': 0.0,
            'distance_from_floor_mm': 0.0,
            'width_mm': 800.0,
            'height_mm': 2100.0
          },
        ],
      });
      expect(room.shape, KitchenShape.singleWall);
      expect(room.openings.map((o) => o.type),
          [OpeningType.window, OpeningType.door]);
      expect(room.openings.first.centerMm, 1800);
    });

    test('galley falls back to the main wall with a note', () {
      final room = KitchenRoom.fromPayload({
        'wall': {
          'width_mm': 3000.0,
          'height_mm': 2700.0,
          'shape': 'galley',
          'aisle_mm': 1200.0
        },
      });
      expect(room.shape, KitchenShape.singleWall);
      expect(_generator.generate(room, LayoutTier.value).warnings.first,
          contains('galley'));
    });

    test(
        'placed cabinets use the viewer\'s x_mm convention and offset_mm on the return wall',
        () {
      const room = KitchenRoom(
          mainWallMm: 3000,
          wallHeightMm: 2700,
          shape: KitchenShape.lShape,
          returnWallMm: 2400);
      final v = _generator.generate(room, LayoutTier.balanced);
      final cabinets = v.toPlacedCabinets();
      expect(cabinets.map((c) => c['id']).toSet(), hasLength(cabinets.length));
      for (var i = 0; i < v.modules.length; i++) {
        final m = v.modules[i];
        final c = cabinets[i];
        expect(c['width_mm'], m.widthMm);
        if (m.wall == RunWall.main) {
          expect(c['run'], 'main');
          expect(c['x_mm'], (m.centerMm - 1500).round());
        } else {
          expect(c['run'], 'return');
          expect(c['offset_mm'], m.centerMm.round());
          expect(c.containsKey('x_mm'), isFalse);
        }
      }
      expect(cabinets.first['cabinet_type'], 'corner_900');
    });
  });
}
