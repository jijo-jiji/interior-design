// The perspective maths behind "mark the wall's corners": a simulated
// camera photographs a 4000 × 2700 wall with a window, from straight on and
// at angles, and the corners on that photo must give back true millimetres.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/utils/homography.dart';

const wallW = 4000.0, wallH = 2700.0;
const photo = Size(1920, 1080);

/// A window 1200 × 1000, 1500 from the left, sill at 1000 (y down from the
/// ceiling: top at 2700 - 1000 - 1000 = 700).
const window = [
  Offset(1500, 700),
  Offset(2700, 700),
  Offset(2700, 1700),
  Offset(1500, 1700),
];

const wallCorners = [
  Offset(0, 0),
  Offset(wallW, 0),
  Offset(wallW, wallH),
  Offset(0, wallH),
];

/// A pinhole camera [distance] mm from the wall's centre, turned [yawDeg]
/// sideways and [pitchDeg] up or down, with focal length [f] in pixels.
class Camera {
  Camera({
    required double yawDeg,
    required double pitchDeg,
    required double distance,
    this.f = 1500,
  }) {
    final y = yawDeg * math.pi / 180, p = pitchDeg * math.pi / 180;
    // World to camera: pitch after yaw. Rows are the camera's axes.
    final ry = [
      [math.cos(y), 0.0, -math.sin(y)],
      [0.0, 1.0, 0.0],
      [math.sin(y), 0.0, math.cos(y)],
    ];
    final rx = [
      [1.0, 0.0, 0.0],
      [0.0, math.cos(p), math.sin(p)],
      [0.0, -math.sin(p), math.cos(p)],
    ];
    r = [
      for (var i = 0; i < 3; i++)
        [
          for (var j = 0; j < 3; j++)
            rx[i][0] * ry[0][j] + rx[i][1] * ry[1][j] + rx[i][2] * ry[2][j]
        ]
    ];
    // Looking at the wall's centre from [distance] away.
    final centre = [wallW / 2, wallH / 2, 0.0];
    c = [for (var i = 0; i < 3; i++) centre[i] - distance * r[2][i]];
  }

  final double f;
  late final List<List<double>> r;
  late final List<double> c;

  Offset project(Offset wallPoint) {
    final d = [wallPoint.dx - c[0], wallPoint.dy - c[1], -c[2]];
    double dot(List<double> a) => a[0] * d[0] + a[1] * d[1] + a[2] * d[2];
    final z = dot(r[2]);
    return Offset(f * dot(r[0]) / z + photo.width / 2,
        f * dot(r[1]) / z + photo.height / 2);
  }
}

/// Window corners measured through the photo, worst error in mm.
double windowError(List<Offset> cornersPx, Camera cam) {
  final toWall = Homography.between(cornersPx, wallCorners)!;
  var worst = 0.0;
  for (final p in window) {
    final back = toWall.map(cam.project(p));
    worst = math.max(worst, (back - p).distance);
  }
  return worst;
}

void main() {
  final views = {
    'head-on': Camera(yawDeg: 0, pitchDeg: 0, distance: 3500),
    'turned 30°': Camera(yawDeg: 30, pitchDeg: 0, distance: 3500),
    'turned 25°, tilted 12°': Camera(yawDeg: 25, pitchDeg: 12, distance: 3800),
  };

  group('Homography', () {
    test('maps the four points it was built from, and back', () {
      const from = [
        Offset(120, 80),
        Offset(1700, 140),
        Offset(1650, 990),
        Offset(90, 1010),
      ];
      final h = Homography.between(from, wallCorners)!;
      final inv = h.inverse()!;
      for (var i = 0; i < 4; i++) {
        expect((h.map(from[i]) - wallCorners[i]).distance, lessThan(1e-6));
        expect((inv.map(wallCorners[i]) - from[i]).distance, lessThan(1e-6));
      }
    });

    test('three points in a line give no mapping', () {
      expect(
          Homography.between(
              const [Offset(0, 0), Offset(1, 1), Offset(2, 2), Offset(0, 5)],
              wallCorners),
          isNull);
    });

    for (final MapEntry(key: name, value: cam) in views.entries) {
      test('$name: the window comes back to the millimetre', () {
        final corners = [for (final p in wallCorners) cam.project(p)];
        expect(windowError(corners, cam), lessThan(0.5));
      });
    }

    test('the old four-line method is far off once the photo is angled', () {
      // What the axis-aligned lines did: one scale across the whole wall.
      final cam = views['turned 30°']!;
      final corners = [for (final p in wallCorners) cam.project(p)];
      final left = (corners[0].dx + corners[3].dx) / 2;
      final right = (corners[1].dx + corners[2].dx) / 2;
      final mmPerPx = wallW / (right - left);
      final windowLeft = (cam.project(window[0]).dx - left) * mmPerPx;
      expect((windowLeft - 1500).abs(), greaterThan(100));
    });
  });

  group('estimateWallShape', () {
    for (final MapEntry(key: name, value: cam) in views.entries) {
      test('$name: true proportions with the photo\'s focal length', () {
        final corners = [for (final p in wallCorners) cam.project(p)];
        final shape = estimateWallShape(corners, photo, focalPx: cam.f)!;
        expect(shape.aspect, closeTo(wallW / wallH, 0.005 * wallW / wallH));
        expect(shape.focalSource, FocalSource.photo);
      });
    }

    test('head-on, the focal length makes no difference', () {
      final cam = views['head-on']!;
      final corners = [for (final p in wallCorners) cam.project(p)];
      final shape = estimateWallShape(corners, photo)!;
      expect(shape.aspect, closeTo(wallW / wallH, 1e-6));
    });

    test('angled both ways, the corners give the focal length themselves', () {
      final cam = views['turned 25°, tilted 12°']!;
      final corners = [for (final p in wallCorners) cam.project(p)];
      final shape = estimateWallShape(corners, photo)!;
      expect(shape.focalSource, FocalSource.corners);
      expect(shape.focalPx, closeTo(cam.f, 0.01 * cam.f));
      expect(shape.aspect, closeTo(wallW / wallH, 0.01 * wallW / wallH));
    });

    test('how far off a wrong focal length or shaky corners can be', () {
      // Not a pass/fail: the numbers the size check's tolerance is set from.
      final rows = <String>[];
      for (final yaw in [0.0, 15.0, 30.0]) {
        final cam = Camera(yawDeg: yaw, pitchDeg: 0, distance: 3500);
        final corners = [for (final p in wallCorners) cam.project(p)];
        for (final k in [0.75, 1.25]) {
          final s = estimateWallShape(corners, photo, focalPx: cam.f * k)!;
          final err = (s.aspect / (wallW / wallH) - 1) * 100;
          rows.add('yaw ${yaw.round()}°, focal ×$k: ${err.toStringAsFixed(1)}%');
        }
        // Corners tapped up to 4 px off, in a fixed pattern.
        const jitter = [Offset(4, -3), Offset(-3, 4), Offset(4, 3), Offset(-4, -4)];
        final shaky = [for (var i = 0; i < 4; i++) corners[i] + jitter[i]];
        final s = estimateWallShape(shaky, photo, focalPx: cam.f)!;
        final err = (s.aspect / (wallW / wallH) - 1) * 100;
        rows.add('yaw ${yaw.round()}°, corners ±4 px: '
            '${err.toStringAsFixed(1)}%, window ${windowError(shaky, cam).toStringAsFixed(0)} mm');
      }
      // ignore: avoid_print
      print(rows.join('\n'));
    });
  });
}
