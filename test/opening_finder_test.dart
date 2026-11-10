// Windows and doors from the segmentation labels: regions on the wall the
// corners mark, mapped onto the straightened wall in millimetres.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/models/obstacle.dart';
import 'package:static_trace/features/trace/utils/homography.dart';
import 'package:static_trace/features/trace/utils/opening_finder.dart';

/// A 128 × 128 label map: wall everywhere, with [boxes] (photo fractions)
/// painted in their class.
WallLabels labelsWith(List<(int, Rect)> boxes) {
  const n = 128;
  final ids = Uint8List(n * n)..fillRange(0, n * n, WallLabels.wall);
  for (final (id, r) in boxes) {
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final p = Offset((x + 0.5) / n, (y + 0.5) / n);
        if (r.contains(p)) ids[y * n + x] = id;
      }
    }
  }
  return WallLabels(n, n, ids);
}

void main() {
  // The wall fills the middle of the photo head-on: x 0.1–0.9, y 0.1–0.9,
  // 4000 × 2700 mm, so 0.2 of the photo is 1000 mm across, 675 mm down.
  const corners = [
    Offset(0.1, 0.1),
    Offset(0.9, 0.1),
    Offset(0.9, 0.9),
    Offset(0.1, 0.9),
  ];

  test('a window comes back at its size and place, to a few cm', () {
    // 1200 mm wide from 1000 mm in; 1000 mm tall from 675 mm down.
    final labels = labelsWith([
      (WallLabels.window, const Rect.fromLTRB(0.3, 0.3, 0.54, 0.5963)),
    ]);
    final found = findOpenings(labels, corners, 4000, 2700);
    expect(found, hasLength(1));
    final r = found.single.rectMm;
    expect(found.single.type, ObstacleType.window);
    expect(r.left, closeTo(1000, 40));
    expect(r.width, closeTo(1200, 60));
    expect(r.top, closeTo(675, 40));
    expect(r.height, closeTo(1000, 60));
  });

  test('a curtain counts as the window behind it', () {
    final labels = labelsWith([
      (WallLabels.curtain, const Rect.fromLTRB(0.2, 0.2, 0.4, 0.5)),
    ]);
    final found = findOpenings(labels, corners, 4000, 2700);
    expect(found.single.type, ObstacleType.window);
  });

  test('a door reaching near the floor stands on it', () {
    // Bottom at 0.88: 2,565 mm down, 135 mm off the floor.
    final labels = labelsWith([
      (WallLabels.door, const Rect.fromLTRB(0.65, 0.35, 0.8, 0.88)),
    ]);
    final found = findOpenings(labels, corners, 4000, 2700);
    expect(found.single.type, ObstacleType.door);
    expect(found.single.rectMm.bottom, 2700);
  });

  test('openings come back left to right, each its own box', () {
    final labels = labelsWith([
      (WallLabels.window, const Rect.fromLTRB(0.6, 0.3, 0.75, 0.55)),
      (WallLabels.window, const Rect.fromLTRB(0.2, 0.3, 0.35, 0.55)),
    ]);
    final found = findOpenings(labels, corners, 4000, 2700);
    expect(found, hasLength(2));
    expect(found[0].rectMm.left, lessThan(found[1].rectMm.left));
  });

  test("a window in a side wall isn't this wall's", () {
    // Left of the wall's left corner.
    final labels = labelsWith([
      (WallLabels.window, const Rect.fromLTRB(0.0, 0.3, 0.08, 0.6)),
    ]);
    expect(findOpenings(labels, corners, 4000, 2700), isEmpty);
  });

  test('specks are noise', () {
    final labels = labelsWith([
      (WallLabels.window, const Rect.fromLTRB(0.5, 0.5, 0.52, 0.52)),
    ]);
    expect(findOpenings(labels, corners, 4000, 2700), isEmpty);
  });

  test('an angled photo still gives true millimetres', () {
    // The wall seen from the left: its right side farther, so smaller.
    const angled = [
      Offset(0.1, 0.1),
      Offset(0.85, 0.2),
      Offset(0.85, 0.8),
      Offset(0.1, 0.9),
    ];
    // Paint the window where a 1000 mm square at (1500, 800) mm lands.
    final toPhoto = Homography.between(const [
      Offset.zero,
      Offset(4000, 0),
      Offset(4000, 2700),
      Offset(0, 2700),
    ], angled)!;
    final quad = [
      toPhoto.map(const Offset(1500, 800)),
      toPhoto.map(const Offset(2500, 800)),
      toPhoto.map(const Offset(2500, 1800)),
      toPhoto.map(const Offset(1500, 1800)),
    ];
    const n = 128;
    final ids = Uint8List(n * n)..fillRange(0, n * n, WallLabels.wall);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (_inside(quad, Offset((x + 0.5) / n, (y + 0.5) / n))) {
          ids[y * n + x] = WallLabels.window;
        }
      }
    }
    final found = findOpenings(WallLabels(n, n, ids), angled, 4000, 2700);
    final r = found.single.rectMm;
    expect(r.left, closeTo(1500, 60));
    expect(r.right, closeTo(2500, 60));
    expect(r.top, closeTo(800, 60));
    expect(r.bottom, closeTo(1800, 60));
  });
}

bool _inside(List<Offset> quad, Offset p) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = quad[i], b = quad[(i + 1) % 4];
    final c = (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    final s = c > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}
