// Reading walls, rooms and the scale off a plan's drawing (no AI), on test
// plans drawn here, to scale at 10 mm per pixel.
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/floorplan/kitchen_finder.dart';
import 'package:static_trace/features/floorplan/plan_geometry.dart';
import 'package:static_trace/features/floorplan/plan_sizes.dart';

const int W = 1000, H = 700, T = 15; // 150 mm walls

/// A white page to draw on.
class Page {
  final pixels = Uint8List(W * H)..fillRange(0, W * H, 255);

  void fill(int x0, int y0, int x1, int y1, [int v = 0]) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        pixels[y * W + x] = v;
      }
    }
  }

  /// A one-pixel outline, like counters and furniture.
  void outline(int x0, int y0, int x1, int y1) {
    fill(x0, y0, x1, y0 + 1);
    fill(x0, y1 - 1, x1, y1);
    fill(x0, y0, x0 + 1, y1);
    fill(x1 - 1, y0, x1, y1);
  }

  GrayImage get image => GrayImage(W, H, pixels);
}

// Bedroom inside 360 × 330 px (3600 × 3300 mm), kitchen inside 300 × 330 px
// (3000 × 3300 mm), a corridor below both, a 900 mm door from the kitchen to
// the corridor.
const bedroom = Rect.fromLTRB(65, 65, 425, 395);
const kitchen = Rect.fromLTRB(440, 65, 740, 395);

Page twoRoomPlan(
    {int wall = T, bool kitchenDoor = true, bool wallBetween = true}) {
  final p = Page();
  const x0 = 50, y0 = 50;
  final bx1 = x0 + wall + 360, kx1 = bx1 + wall + 300, top1 = y0 + wall + 330;
  p.fill(x0, y0, kx1 + wall, y0 + wall); // top
  p.fill(x0, y0, x0 + wall, top1 + wall + 200); // left
  p.fill(kx1, y0, kx1 + wall, top1 + wall + 200); // right
  if (wallBetween) p.fill(bx1, y0, bx1 + wall, top1); // bedroom | kitchen
  p.fill(x0, top1, kx1 + wall, top1 + wall); // rooms | corridor
  p.fill(x0, top1 + wall + 200, kx1 + wall, top1 + 2 * wall + 200); // bottom
  if (kitchenDoor) p.fill(bx1 + 60, top1, bx1 + 150, top1 + wall, 255);
  // Furniture: counters and a sink, thin lines that aren't walls.
  p.outline(bx1 + wall + 2, y0 + wall + 2, kx1 - 2, y0 + wall + 62);
  p.outline(bx1 + 100, y0 + 25, bx1 + 150, y0 + 55);
  return p;
}

Rect frac(Rect px) =>
    Rect.fromLTRB(px.left / W, px.top / H, px.right / W, px.bottom / H);

/// The plan's text: the room names, and the bedroom's printed size.
PlanText twoRoomText({String bedroomSize = '3600x3300'}) => findPlanText([
      [PlanWord('BEDROOM', frac(const Rect.fromLTWH(200, 200, 80, 14)))],
      [PlanWord(bedroomSize, frac(const Rect.fromLTWH(200, 218, 80, 14)))],
      [PlanWord('KITCHEN', frac(const Rect.fromLTWH(550, 220, 80, 14)))],
    ]);

PlanGeometry read(Page page, PlanText text) => analysePlan(
    PlanAnalysisInput(page.image, text, findKitchen(text)?.kitchenLabel));

void expectRect(Rect actual, Rect expected, {double within = 3}) {
  for (final (a, e) in [
    (actual.left, expected.left),
    (actual.top, expected.top),
    (actual.right, expected.right),
    (actual.bottom, expected.bottom),
  ]) {
    expect(a, closeTo(e, within), reason: '$actual vs $expected');
  }
}

void main() {
  test('finds the walls and leaves out furniture and text', () {
    final g = read(twoRoomPlan(), twoRoomText());
    expect(g.wallThicknessPx, T);
    expect(g.walls, isNotEmpty);
    // Every wall piece is at least half a wall thick: the one-pixel
    // counters and sink are gone.
    for (final w in g.walls) {
      expect(w.shortestSide, greaterThanOrEqualTo(T / 2), reason: '$w');
    }
  });

  test('finds each room under its name', () {
    final g = read(twoRoomPlan(), twoRoomText());
    final names = {for (final r in g.rooms) r.name: r.rect};
    expectRect(names['BEDROOM']!, bedroom);
    expectRect(names['KITCHEN']!, kitchen);
  });

  test('sets the scale from a printed room size, and measures the kitchen', () {
    final g = read(twoRoomPlan(), twoRoomText());
    expect(g.mmPerPx, closeTo(10, 0.1));
    final frame = KitchenFrame(g.kitchen!.rect, 0, g.mmPerPx!);
    // The kitchen's size isn't printed; it's drawn 3000 × 3300.
    expect(frame.mainMm, closeTo(3000, 30));
    expect(frame.returnMm, closeTo(3300, 30));
  });

  test("finds the kitchen's doorway", () {
    final g = read(twoRoomPlan(), twoRoomText());
    final bottom = g.kitchen!.openings[2]!;
    expect(bottom, hasLength(1));
    final (a, b) = bottom.single;
    expect((b - a) * g.mmPerPx!, closeTo(900, 30));
    expect(g.kitchen!.openings[0], isNull); // the top wall is solid
  });

  test("a plan that isn't to scale isn't measured", () {
    // The bedroom is drawn 3600 × 3300 but labelled 3600 × 2000.
    final g = read(twoRoomPlan(), twoRoomText(bedroomSize: '3600x2000'));
    expect(g.mmPerPx, isNull);
  });

  test('with nothing printed to scale it by, nothing is measured', () {
    final text = findPlanText([
      [PlanWord('BEDROOM', frac(const Rect.fromLTWH(200, 200, 80, 14)))],
      [PlanWord('KITCHEN', frac(const Rect.fromLTWH(550, 220, 80, 14)))],
    ]);
    final g = read(twoRoomPlan(), text);
    expect(g.mmPerPx, isNull);
    expect(g.kitchen, isNotNull); // still found, just not measured
  });

  test('a plan drawn in thin lines has no solid walls', () {
    final g = read(twoRoomPlan(wall: 2), twoRoomText());
    expect(g.wallThicknessPx, 0);
    expect(g.hasWalls, isFalse);
  });

  test('an open-plan kitchen is not measured', () {
    // No wall between the kitchen and the bedroom: one big room.
    final g = read(twoRoomPlan(wallBetween: false), twoRoomText());
    expect(g.kitchenIsOpenPlan, isTrue);
    expect(g.kitchen, isNull);
  });

  group('the kitchen frame', () {
    const k = Rect.fromLTRB(100, 100, 400, 300); // 3000 × 2000 at 10 mm/px

    test('any side can be the main wall, with the side wall on its left', () {
      // (main side, corner shared with the side wall, the main wall's other
      // end, a point into the room)
      final cases = [
        (0, k.topLeft, k.topRight, k.bottomLeft),
        (1, k.topRight, k.bottomRight, k.topLeft),
        (2, k.bottomRight, k.bottomLeft, k.topRight),
        (3, k.bottomLeft, k.topLeft, k.bottomRight),
      ];
      for (final (side, corner, mainEnd, intoRoom) in cases) {
        final f = KitchenFrame(k, side, 10);
        expect(f.toKitchen(corner), Offset.zero, reason: 'side $side');
        expect(f.toKitchen(mainEnd), Offset(f.mainMm, 0), reason: 'side $side');
        expect(f.toKitchen(intoRoom), Offset(0, f.returnMm),
            reason: 'side $side');
      }
      expect(const KitchenFrame(k, 0, 10).mainMm, 3000);
      expect(const KitchenFrame(k, 1, 10).mainMm, 2000);
    });

    test("a doorway is measured from the main wall's side-wall end", () {
      // A 900 mm gap 600 mm from the left end of the top wall.
      const room = PlanRoom('KITCHEN', k, openings: {
        0: [(60.0, 150.0)],
        2: [(60.0, 150.0)],
      });
      final top = const KitchenFrame(k, 0, 10).mainWallDoors(room).single;
      expect(top['distance_from_left_mm'], 600);
      expect(top['width_mm'], 900);
      // On the bottom wall the main wall runs right to left, so the same
      // gap is 3000 - 1500 = 1500 mm from its start.
      final bottom = const KitchenFrame(k, 2, 10).mainWallDoors(room).single;
      expect(bottom['distance_from_left_mm'], 1500);
    });

    test('the plan for the 3D is in kitchen mm', () {
      const g = PlanGeometry(
        imageSize: Size(1000, 700),
        wallThicknessPx: 15,
        walls: [Rect.fromLTRB(85, 85, 415, 100)],
        rooms: [PlanRoom('KITCHEN', k)],
        mmPerPx: 10,
        kitchen: PlanRoom('KITCHEN', k),
      );
      final json = const KitchenFrame(k, 0, 10).floorPlanJson(g, image: 'data:x');
      expect(json['kitchen_mm'], [0, 0, 3000, 2000]);
      expect(json['walls'], [
        [-150, -150, 3300, 150]
      ]);
      expect(json['image_size_mm'], [10000, 7000]);
      expect(json['image_center_mm'], [4000, 2500]);
      expect(json['image_rotation_deg'], 0);
      expect((json['rooms'] as List).single['name'], 'KITCHEN');
    });
  });
}
