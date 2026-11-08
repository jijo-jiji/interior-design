// The corner finder: from a depth map to the front wall's four corners.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:static_trace/features/trace/utils/corner_finder.dart';

const roomW = 4000.0, roomH = 2700.0, roomD = 7000.0;

/// A pinhole camera inside a box room: the front wall at z = 0, x across
/// (0..roomW), y down (0..roomH), the room behind at negative z.
class RoomCamera {
  RoomCamera({
    required this.at,
    required double yawDeg,
    required double pitchDeg,
    this.width = 480,
    this.height = 270,
  }) {
    final y = yawDeg * math.pi / 180, p = pitchDeg * math.pi / 180;
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
        [for (var j = 0; j < 3; j++) rx[i][0] * ry[0][j] + rx[i][1] * ry[1][j] + rx[i][2] * ry[2][j]]
    ];
    // A phone's main camera: 26 mm equivalent.
    f = 26 * math.sqrt(width * width + height * height) / 43.2666;
  }

  final List<double> at;
  final int width, height;
  late final List<List<double>> r;
  late final double f;

  Offset project(List<double> p) {
    final d = [p[0] - at[0], p[1] - at[1], p[2] - at[2]];
    double dot(List<double> a) => a[0] * d[0] + a[1] * d[1] + a[2] * d[2];
    final z = dot(r[2]);
    return Offset(f * dot(r[0]) / z + width / 2, f * dot(r[1]) / z + height / 2);
  }

  /// Inverse depth (1 / camera z) of the room's nearest surface per pixel.
  DepthMap render() {
    final out = Float32List(width * height);
    for (var v = 0; v < height; v++) {
      for (var u = 0; u < width; u++) {
        final dc = [(u + 0.5 - width / 2) / f, (v + 0.5 - height / 2) / f, 1.0];
        final dw = [for (var j = 0; j < 3; j++) dc[0] * r[0][j] + dc[1] * r[1][j] + dc[2] * r[2][j]];
        var best = double.infinity;
        // Each wall plane: axis, value.
        for (final (axis, value) in [(2, 0.0), (2, -roomD), (0, 0.0), (0, roomW), (1, 0.0), (1, roomH)]) {
          if (dw[axis].abs() < 1e-12) continue;
          final t = (value - at[axis]) / dw[axis];
          if (t <= 0 || t >= best) continue;
          final p = [for (var j = 0; j < 3; j++) at[j] + t * dw[j]];
          const e = 1e-6;
          if (p[0] < -e || p[0] > roomW + e || p[1] < -e || p[1] > roomH + e || p[2] > e || p[2] < -roomD - e) {
            continue;
          }
          best = t;
        }
        out[v * width + u] = (1 / best).toDouble();
      }
    }
    return DepthMap(width, height, out);
  }

  List<Offset> wallCorners() => [
        project([0, 0, 0]),
        project([roomW, 0, 0]),
        project([roomW, roomH, 0]),
        project([0, roomH, 0]),
      ];
}

double worstPx(List<Offset> found, List<Offset> truth, Size size) {
  var worst = 0.0;
  for (var i = 0; i < 4; i++) {
    final p = Offset(found[i].dx * size.width, found[i].dy * size.height);
    worst = math.max(worst, (p - truth[i]).distance);
  }
  return worst;
}

void main() {
  group('a room rendered exactly', () {
    final views = {
      'head-on': RoomCamera(at: [2000, 1300, -4600], yawDeg: 0, pitchDeg: 3),
      // From near a side wall at the back of a 7 m room, as a phone's
      // lens needs to fit a 4 m wall seen at an angle.
      'from the left, turned 20°': RoomCamera(at: [200, 1350, -5400], yawDeg: 20, pitchDeg: 4),
      'from the right, turned 18°, looking up': RoomCamera(at: [2200, 1500, -6850], yawDeg: -18, pitchDeg: -5),
    };
    for (final MapEntry(key: name, value: cam) in views.entries) {
      test('$name: right, or roughly right, or nothing; never far off', () {
        final truth = cam.wallCorners();
        // The test only means something with the whole wall in the photo.
        for (final p in truth) {
          expect(p.dx, inInclusiveRange(10, cam.width - 10));
          expect(p.dy, inInclusiveRange(10, cam.height - 10));
        }
        final found = cornersFromDepth(cam.render());
        if (found == null) return; // the salesperson places them by hand
        expect(worstPx(found, truth, Size(cam.width * 1.0, cam.height * 1.0)),
            lessThan(0.05 * cam.width));
      });
    }

    test('head-on, the corners are found to a few pixels', () {
      final cam = views['head-on']!;
      final found = cornersFromDepth(cam.render())!;
      expect(worstPx(found, cam.wallCorners(), Size(cam.width * 1.0, cam.height * 1.0)),
          lessThan(4));
    });

    test('the same answer every time', () {
      final depth = views['from the left, turned 20°']!.render();
      expect(cornersFromDepth(depth), cornersFromDepth(depth));
    });

    test('a wall cut off by the photo gives no answer', () {
      // So close that the wall overflows the photo on both sides.
      final cam = RoomCamera(at: [2000, 1350, -900], yawDeg: 0, pitchDeg: 0);
      expect(cornersFromDepth(cam.render()), isNull);
    });
  });

  test('nothing flat to find gives no answer', () {
    final rnd = math.Random(3);
    final noise = Float32List.fromList([for (var i = 0; i < 200 * 120; i++) rnd.nextDouble()]);
    expect(cornersFromDepth(DepthMap(200, 120, noise)), isNull);
    expect(cornersFromDepth(DepthMap(200, 120, Float32List(200 * 120))), isNull);
  });

  test("the depth model's view of a rendered room, 25° from the left", () {
    // From the 8-bit Depth Anything V2 Small the app ships (half size), on
    // tool/wall_benchmark/make_synthetic.py's photo. On real photos the
    // corners land 3–11 px off; flat, untextured renders are harder.
    final png = img.decodePng(
        File('test/fixtures/walls/from-left-25-depth.png').readAsBytesSync())!;
    final values = Float32List(png.width * png.height);
    for (final p in png) {
      values[p.y * png.width + p.x] = p.r.toDouble();
    }
    final truth = jsonDecode(
        File('test/fixtures/walls/from-left-25.json').readAsStringSync());
    final corners = [
      for (final c in truth['wall_corners_px'] as List)
        Offset((c[0] as num).toDouble(), (c[1] as num).toDouble())
    ];
    final found = cornersFromDepth(DepthMap(png.width, png.height, values));
    expect(found, isNotNull);
    expect(worstPx(found!, corners, const Size(1920, 1080)), lessThan(60));
  });
}
