import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'kitchen_finder.dart';
import 'plan_sizes.dart';

// Reading the drawing itself: where the walls and rooms are, and how many
// millimetres one pixel is. Plain image processing, no AI:
//
//  1. Walls: dark strokes as thick as the walls. Thinner ones (text,
//     furniture, dimension lines) are removed with a morphological opening.
//  2. Rooms: doorways are closed by thickening the walls, then each room is
//     the free area under its name.
//  3. Scale: a room whose size is printed ("3600 x 3300") against its box
//     in pixels, and neighbouring dimensions along an edge. They must agree;
//     a plan whose printed sizes disagree with its drawing isn't to scale,
//     and isn't measured.

/// A greyscale image, one byte per pixel: 0 is black, 255 white.
class GrayImage {
  GrayImage(this.width, this.height, this.pixels)
      : assert(pixels.length == width * height);

  /// From straight (not premultiplied) RGBA; transparency counts as white.
  factory GrayImage.fromRgba(Uint8List rgba, int width, int height) {
    final px = Uint8List(width * height);
    for (var i = 0, j = 0; i < px.length; i++, j += 4) {
      final lum =
          (rgba[j] * 299 + rgba[j + 1] * 587 + rgba[j + 2] * 114) ~/ 1000;
      px[i] = 255 - (255 - lum) * rgba[j + 3] ~/ 255;
    }
    return GrayImage(width, height, px);
  }

  final int width, height;
  final Uint8List pixels;
}

/// A room found on the plan: its name and its inside, in plan pixels.
class PlanRoom {
  const PlanRoom(this.name, this.rect, {this.openings = const {}});
  final String name;
  final Rect rect;

  /// Gaps in the wall around the room (doorways, open sides) per side:
  /// 0 top, 1 right, 2 bottom, 3 left, as (start, end) pixels along the
  /// side, measured left to right or top to bottom.
  final Map<int, List<(double, double)>> openings;
}

/// What the drawing says, in the pixels of the image it was read from.
class PlanGeometry {
  const PlanGeometry({
    required this.imageSize,
    required this.wallThicknessPx,
    required this.walls,
    required this.rooms,
    this.mmPerPx,
    this.kitchen,
    this.kitchenIsOpenPlan = false,
  });

  final Size imageSize;

  /// 0 when no solid walls were found (a plan drawn in thin lines).
  final double wallThicknessPx;
  final List<Rect> walls;
  final List<PlanRoom> rooms;

  /// Null when nothing printed could set the scale, or the printed sizes
  /// disagree with the drawing (it isn't to scale).
  final double? mmPerPx;

  /// The kitchen's room, if its name was found inside a closed room.
  final PlanRoom? kitchen;

  /// The kitchen's box took in another room: it's open to it, so its walls
  /// can't be measured from the drawing.
  final bool kitchenIsOpenPlan;

  bool get hasWalls => walls.isNotEmpty;
}

/// Everything [analysePlan] needs, in one object so it can be handed to a
/// background isolate.
class PlanAnalysisInput {
  const PlanAnalysisInput(this.image, this.text, this.kitchenLabel);
  final GrayImage image;
  final PlanText text;
  final PlanLabel? kitchenLabel;
}

/// Printed sizes must agree with the drawing to within this to be trusted.
const double kScaleTolerance = 0.08;

/// Doorways up to this wide are closed when finding rooms.
const double kDoorwayMm = 1000;

/// A gap at least this wide in a room's wall is an opening.
const double kOpeningMm = 600;

PlanGeometry analysePlan(PlanAnalysisInput input) {
  final img = input.image;
  final w = img.width, h = img.height;
  final size = Size(w.toDouble(), h.toDouble());
  final dark = _darkMask(img);
  final t = _wallThickness(dark, w, h);
  if (t == 0) {
    return PlanGeometry(
        imageSize: size, wallThicknessPx: 0, walls: const [], rooms: const []);
  }

  // Strokes thinner than about half a wall go; walls stay.
  final k = math.max(3, (t * 0.6).round());
  final walls = _dilate(_erode(dark, w, h, k), w, h, k);

  Rect toPx(Rect f) =>
      Rect.fromLTRB(f.left * w, f.top * h, f.right * w, f.bottom * h);
  final labels = [
    for (final l in input.text.labels) (l, toPx(l.box)),
  ];

  // First pass: close gaps up to 9% of the plan's long side (a doorway is
  // 6-9% of a typical house plan's width), then close exactly 1 m once the
  // scale is known.
  var closeR = (math.max(w, h) * 0.045).round();
  var rooms = _findRooms(walls, w, h, closeR, labels);
  var scale = _scale(input.text, rooms, labels, w, h);
  if (scale != null) {
    final r = (kDoorwayMm / 2 / scale).round();
    if ((r - closeR).abs() > closeR * 0.3) {
      closeR = r;
      rooms = _findRooms(walls, w, h, closeR, labels);
      scale = _scale(input.text, rooms, labels, w, h);
    }
  }

  PlanRoom? kitchen;
  var openPlan = false;
  if (input.kitchenLabel case final label?) {
    final found = rooms.where((r) => identical(r.$1, label)).toList();
    if (found.isNotEmpty) {
      final rect = found.first.$2;
      // Another room's name inside the kitchen's box: it's open to it.
      openPlan = labels.any((l) =>
          !identical(l.$1, label) &&
          _isRoomName(l.$1.text) &&
          rect.contains(l.$2.center));
      if (!openPlan) {
        final minGap = scale == null ? t * 4.0 : kOpeningMm / scale;
        kitchen = PlanRoom(label.text, rect,
            openings: _openings(walls, w, h, rect, t, minGap));
      }
    }
  }

  return PlanGeometry(
    imageSize: size,
    wallThicknessPx: t.toDouble(),
    walls: _rectangles(walls, w, h, minSide: (t * 0.5).ceil()),
    rooms: [for (final r in rooms) PlanRoom(r.$1.text, r.$2)],
    mmPerPx: scale,
    kitchen: kitchen,
    kitchenIsOpenPlan: openPlan,
  );
}

/// A label that names a room rather than an area or a note ("85 sq ft").
bool _isRoomName(String text) =>
    RegExp(r'[A-Za-z]{3,}').hasMatch(text) &&
    !RegExp(r'\b(sq|sqft|m2)\b', caseSensitive: false).hasMatch(text);

Uint8List _darkMask(GrayImage img) {
  final m = Uint8List(img.width * img.height);
  for (var i = 0; i < m.length; i++) {
    if (img.pixels[i] < 128) m[i] = 1;
  }
  return m;
}

/// The thickness of the plan's solid walls in pixels, or 0 if it has none:
/// the most common dark run length that's thicker than a drawn line.
int _wallThickness(Uint8List dark, int w, int h) {
  final maxT = math.max(6, math.min(w, h) ~/ 15);
  final hist = List<int>.filled(maxT + 1, 0);
  var darkTotal = 0;
  void run(int len) {
    if (len >= 1 && len <= maxT) hist[len]++;
  }

  for (var y = 0; y < h; y++) {
    var len = 0;
    for (var x = 0; x < w; x++) {
      if (dark[y * w + x] == 1) {
        len++;
        darkTotal++;
      } else {
        run(len);
        len = 0;
      }
    }
    run(len);
  }
  for (var x = 0; x < w; x++) {
    var len = 0;
    for (var y = 0; y < h; y++) {
      if (dark[y * w + x] == 1) {
        len++;
      } else {
        run(len);
        len = 0;
      }
    }
    run(len);
  }
  if (darkTotal == 0) return 0;

  // Weighted by length, so a wall's few long crossings outweigh the many
  // one-pixel lines of text and furniture.
  var best = 0, bestScore = 0;
  for (var len = 4; len <= maxT; len++) {
    final score = hist[len] * len;
    if (score > bestScore) {
      bestScore = score;
      best = len;
    }
  }
  // Too few dark pixels in thick runs: the plan is drawn in thin lines.
  var thick = 0;
  for (var len = 4; len <= maxT; len++) {
    thick += hist[len] * len;
  }
  return thick * 2 < darkTotal * 0.15 ? 0 : best;
}

/// Box sums over a binary mask, for erosion and dilation in O(pixels).
Int32List _integral(Uint8List m, int w, int h) {
  final s = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      row += m[y * w + x];
      s[(y + 1) * (w + 1) + x + 1] = s[y * (w + 1) + x + 1] + row;
    }
  }
  return s;
}

int _boxSum(Int32List s, int w, int x0, int y0, int x1, int y1) =>
    s[y1 * (w + 1) + x1] -
    s[y0 * (w + 1) + x1] -
    s[y1 * (w + 1) + x0] +
    s[y0 * (w + 1) + x0];

/// A pixel stays only if the k×k square around it is all set.
Uint8List _erode(Uint8List m, int w, int h, int k) {
  final s = _integral(m, w, h);
  final out = Uint8List(w * h);
  final r0 = k ~/ 2, r1 = k - r0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final x0 = x - r0, y0 = y - r0, x1 = x + r1, y1 = y + r1;
      if (x0 < 0 || y0 < 0 || x1 > w || y1 > h) continue;
      if (_boxSum(s, w, x0, y0, x1, y1) == k * k) out[y * w + x] = 1;
    }
  }
  return out;
}

/// A pixel is set if anything in the k×k square around it is.
Uint8List _dilate(Uint8List m, int w, int h, int k) {
  final s = _integral(m, w, h);
  final out = Uint8List(w * h);
  final r0 = k ~/ 2, r1 = k - r0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - r1 + 1), y0 = math.max(0, y - r1 + 1);
      final x1 = math.min(w, x + r0 + 1), y1 = math.min(h, y + r0 + 1);
      if (_boxSum(s, w, x0, y0, x1, y1) > 0) out[y * w + x] = 1;
    }
  }
  return out;
}

/// Each named room's inside, in pixels: the free area under the label once
/// doorways are closed (walls thickened by [r]), with the thickening undone.
List<(PlanLabel, Rect)> _findRooms(
    Uint8List walls, int w, int h, int r, List<(PlanLabel, Rect)> labels) {
  final closed = _dilate(walls, w, h, 2 * r + 1);
  final id = Int32List(w * h);
  final queue = Int32List(w * h);
  final boxes = <Rect>[];
  final touchesEdge = <bool>[];

  int componentAt(int sx, int sy) {
    final start = sy * w + sx;
    if (closed[start] == 1) return 0;
    if (id[start] != 0) return id[start];
    final n = boxes.length + 1;
    var minX = sx, maxX = sx, minY = sy, maxY = sy;
    var edge = false;
    var head = 0, tail = 0;
    queue[tail++] = start;
    id[start] = n;
    while (head < tail) {
      final p = queue[head++];
      final x = p % w, y = p ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) edge = true;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (final q in [p - 1, p + 1, p - w, p + w]) {
        if (q < 0 || q >= w * h) continue;
        if ((q == p - 1 && x == 0) || (q == p + 1 && x == w - 1)) continue;
        if (closed[q] == 0 && id[q] == 0) {
          id[q] = n;
          queue[tail++] = q;
        }
      }
    }
    boxes.add(Rect.fromLTRB(
      math.max(0, minX - r).toDouble(),
      math.max(0, minY - r).toDouble(),
      math.min(w, maxX + 1 + r).toDouble(),
      math.min(h, maxY + 1 + r).toDouble(),
    ));
    touchesEdge.add(edge);
    return n;
  }

  final rooms = <(PlanLabel, Rect)>[];
  for (final (label, box) in labels) {
    if (!_isRoomName(label.text)) continue;
    // The label's centre can sit on a thickened wall; look around it.
    final c = box.center;
    int n = 0;
    for (final (dx, dy) in [(0, 0), (0, 1), (0, -1), (1, 0), (-1, 0)]) {
      final x = (c.dx + dx * box.height).round().clamp(0, w - 1);
      final y = (c.dy + dy * box.height).round().clamp(0, h - 1);
      n = componentAt(x, y);
      if (n != 0) break;
    }
    // Outside the house (the margin around it) isn't a room.
    if (n == 0 || touchesEdge[n - 1]) continue;
    rooms.add((label, boxes[n - 1]));
  }
  return rooms;
}

/// Millimetres per pixel from what's printed, or null if nothing printed
/// sets it or the printed sizes disagree with the drawing.
double? _scale(PlanText text, List<(PlanLabel, Rect)> rooms,
    List<(PlanLabel, Rect)> labels, int w, int h) {
  final estimates = <double>[];

  // Room sizes against their rooms' boxes, whichever way round fits.
  for (final (label, rect) in rooms) {
    final pair = roomSizeOf(label, text);
    if (pair == null) continue;
    final (a, b) = (pair.$1.mm, pair.$2.mm);
    final across = [a / rect.width, b / rect.height];
    final turned = [a / rect.height, b / rect.width];
    double spread(List<double> s) => (s[0] - s[1]).abs() / math.max(s[0], s[1]);
    final s = spread(across) <= spread(turned) ? across : turned;
    if (spread(s) > kScaleTolerance) return null; // the room isn't to scale
    estimates.add((s[0] + s[1]) / 2);
  }

  // Neighbouring dimensions in a row along an edge: the distance between
  // their centres is half of each one added together.
  final dims = [
    for (final s in text.sizes)
      if (!RegExp(r'[x×]', caseSensitive: false).hasMatch(s.line))
        (
          s.mm,
          Rect.fromLTRB(
              s.box.left * w, s.box.top * h, s.box.right * w, s.box.bottom * h)
        ),
  ];
  for (final vertical in [false, true]) {
    final used = <int>{};
    for (var i = 0; i < dims.length; i++) {
      if (used.contains(i)) continue;
      final rowOf = dims[i].$2;
      final row = [
        for (var j = 0; j < dims.length; j++)
          if (vertical
              ? (dims[j].$2.center.dx - rowOf.center.dx).abs() < rowOf.width
              : (dims[j].$2.center.dy - rowOf.center.dy).abs() < rowOf.height)
            j,
      ];
      used.addAll(row);
      if (row.length < 2) continue;
      row.sort((p, q) => vertical
          ? dims[p].$2.center.dy.compareTo(dims[q].$2.center.dy)
          : dims[p].$2.center.dx.compareTo(dims[q].$2.center.dx));
      for (var j = 0; j + 1 < row.length; j++) {
        final (m1, b1) = dims[row[j]];
        final (m2, b2) = dims[row[j + 1]];
        final gap = vertical
            ? b2.center.dy - b1.center.dy
            : b2.center.dx - b1.center.dx;
        if (gap > 0) estimates.add(((m1 + m2) / 2) / gap);
      }
    }
  }

  if (estimates.isEmpty) return null;
  estimates.sort();
  final median = estimates[estimates.length ~/ 2];
  final agree = [
    for (final e in estimates)
      if ((e - median).abs() / median <= kScaleTolerance) e,
  ];
  // Most printed sizes must agree, or the drawing isn't to scale. (A row of
  // dimensions with one missing gives a stray estimate; that's allowed.)
  if (agree.length * 2 < estimates.length) return null;
  return agree.reduce((a, b) => a + b) / agree.length;
}

/// Gaps of at least [minGap] pixels in the wall just outside each side of
/// [room].
Map<int, List<(double, double)>> _openings(
    Uint8List walls, int w, int h, Rect room, int t, double minGap) {
  final out = <int, List<(double, double)>>{};
  final band = math.max(2, t);
  bool wallAt(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && walls[y * w + x] == 1;

  for (var side = 0; side < 4; side++) {
    final horizontal = side == 0 || side == 2;
    final from = (horizontal ? room.left : room.top).round();
    final to = (horizontal ? room.right : room.bottom).round();
    final gaps = <(double, double)>[];
    int? gapStart;
    for (var p = from; p <= to; p++) {
      var solid = false;
      if (p < to) {
        for (var d = 0; d < band && !solid; d++) {
          solid = switch (side) {
            0 => wallAt(p, room.top.round() - 1 - d),
            1 => wallAt(room.right.round() + d, p),
            2 => wallAt(p, room.bottom.round() + d),
            _ => wallAt(room.left.round() - 1 - d, p),
          };
        }
      } else {
        solid = true; // close a gap that runs to the corner
      }
      if (!solid) {
        gapStart ??= p;
      } else if (gapStart != null) {
        if (p - gapStart >= minGap) {
          gaps.add(((gapStart - from).toDouble(), (p - from).toDouble()));
        }
        gapStart = null;
      }
    }
    if (gaps.isNotEmpty) out[side] = gaps;
  }
  return out;
}

/// The wall mask as axis-aligned rectangles: runs in each row, merged down
/// while they keep the same ends.
List<Rect> _rectangles(Uint8List m, int w, int h, {required int minSide}) {
  final done = <Rect>[];
  var open = <(int, int), int>{}; // run (x0, x1) → row it started
  for (var y = 0; y <= h; y++) {
    final runs = <(int, int)>{};
    if (y < h) {
      var x = 0;
      while (x < w) {
        if (m[y * w + x] == 0) {
          x++;
          continue;
        }
        final x0 = x;
        while (x < w && m[y * w + x] == 1) {
          x++;
        }
        runs.add((x0, x));
      }
    }
    final next = <(int, int), int>{};
    for (final entry in open.entries) {
      if (runs.contains(entry.key)) {
        next[entry.key] = entry.value;
      } else {
        final (x0, x1) = entry.key;
        final y0 = entry.value;
        if (x1 - x0 >= minSide && y - y0 >= minSide) {
          done.add(Rect.fromLTRB(
              x0.toDouble(), y0.toDouble(), x1.toDouble(), y.toDouble()));
        }
      }
    }
    for (final run in runs) {
      next.putIfAbsent(run, () => y);
    }
    open = next;
  }
  // Biggest first; a plan has a few hundred wall pieces at most.
  done.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
  return done.take(600).toList();
}

// ── The kitchen's frame: what the 3D views use ───────────────────────────

/// The 3D views measure from the kitchen's corner: x along the main wall
/// (from the end where the side wall is), z into the room, in mm. The main
/// wall is one of the kitchen room's four sides (0 top, 1 right, 2 bottom,
/// 3 left), chosen so the side wall is on its left, as the 3D and the layout
/// generator expect; a rotation lines up any side, with no mirroring.
class KitchenFrame {
  const KitchenFrame(this.kitchen, this.mainSide, this.mmPerPx);

  /// The kitchen's inside, in plan pixels.
  final Rect kitchen;
  final int mainSide;
  final double mmPerPx;

  /// The main wall's length in mm, and the side wall's.
  double get mainMm =>
      (mainSide.isEven ? kitchen.width : kitchen.height) * mmPerPx;
  double get returnMm =>
      (mainSide.isEven ? kitchen.height : kitchen.width) * mmPerPx;

  /// A plan pixel in kitchen mm.
  Offset toKitchen(Offset p) {
    final s = mmPerPx, k = kitchen;
    return switch (mainSide) {
      0 => Offset((p.dx - k.left) * s, (p.dy - k.top) * s),
      1 => Offset((p.dy - k.top) * s, (k.right - p.dx) * s),
      2 => Offset((k.right - p.dx) * s, (k.bottom - p.dy) * s),
      _ => Offset((k.bottom - p.dy) * s, (p.dx - k.left) * s),
    };
  }

  Rect rectToKitchen(Rect px) =>
      Rect.fromPoints(toKitchen(px.topLeft), toKitchen(px.bottomRight));

  /// The plan picture's turn about the vertical axis in the 3D (three.js
  /// rotation.y), so its right edge points along the kitchen's x.
  double get imageRotationDeg => const [0.0, 90.0, 180.0, -90.0][mainSide];

  /// The doorways in the main wall, as the 3D's wall obstacles.
  List<Map<String, dynamic>> mainWallDoors(PlanRoom room) {
    final gaps = room.openings[mainSide] ?? const [];
    final length = mainSide.isEven ? kitchen.width : kitchen.height;
    // Sides are measured left to right or top to bottom; the main wall's x
    // runs from its side-wall end, which is the other end on the right and
    // bottom walls.
    final flipped = mainSide == 1 || mainSide == 2;
    return [
      for (final (a, b) in gaps)
        if ((b - a) * mmPerPx <= 1500) // wider is an open side, not a door
          {
            'type': 'door',
            'distance_from_left_mm':
                ((flipped ? length - b : a) * mmPerPx).roundToDouble(),
            'distance_from_floor_mm': 0.0,
            'width_mm': ((b - a) * mmPerPx).roundToDouble(),
            'height_mm': 2100.0,
          },
    ];
  }

  /// The plan for the 3D's Room and House views: the walls and rooms in
  /// kitchen mm, and where the picture goes on the floor. [image] is the
  /// picture as a data URL, the same pixels the geometry was read from.
  Map<String, dynamic> floorPlanJson(PlanGeometry g, {required String image}) {
    List<double> rect(Rect r) => [
          r.left.roundToDouble(),
          r.top.roundToDouble(),
          r.width.roundToDouble(),
          r.height.roundToDouble(),
        ];
    final centre = toKitchen(g.imageSize.center(Offset.zero));
    return {
      'image': image,
      'image_center_mm': [centre.dx.roundToDouble(), centre.dy.roundToDouble()],
      'image_size_mm': [
        (g.imageSize.width * mmPerPx).roundToDouble(),
        (g.imageSize.height * mmPerPx).roundToDouble(),
      ],
      'image_rotation_deg': imageRotationDeg,
      'kitchen_mm': rect(rectToKitchen(kitchen)),
      'wall_thickness_mm': (g.wallThicknessPx * mmPerPx).roundToDouble(),
      'walls': [for (final w in g.walls) rect(rectToKitchen(w))],
      'rooms': [
        for (final r in g.rooms)
          {'name': r.name, 'rect_mm': rect(rectToKitchen(r.rect))},
      ],
    };
  }
}

/// The kitchen's frame with its longest wall as the main wall.
int longestSide(Rect kitchen) => kitchen.width >= kitchen.height ? 0 : 3;
