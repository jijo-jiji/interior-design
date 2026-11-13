import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/utils/opening_finder.dart';
import 'package:static_trace/features/trace/utils/wall_size.dart';

/// A wall seen head-on, filling 10–90% of the photo both ways.
const corners = [
  Offset(0.1, 0.1),
  Offset(0.9, 0.1),
  Offset(0.9, 0.9),
  Offset(0.1, 0.9),
];

/// Labels for that photo: [at] gives the label at a point of the wall
/// (u across, v down, both 0..1); ceiling above it, floor below.
WallLabels labelled(int Function(double u, double v) at) {
  const n = 128;
  final ids = Uint8List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final u = ((x + 0.5) / n - 0.1) / 0.8, v = ((y + 0.5) / n - 0.1) / 0.8;
      ids[y * n + x] = v < 0
          ? WallLabels.ceiling
          : v > 1
              ? WallLabels.floor
              : (u < 0 || u > 1)
                  ? WallLabels.wall
                  : at(u, v);
    }
  }
  return WallLabels(n, n, ids);
}

/// Base cabinets along the whole wall, their worktop [up] of the way up it.
WallLabels kitchen(double up) => labelled(
    (u, v) => v > 1 - up ? WallLabels.cabinet : WallLabels.wall);

void main() {
  group('from the worktop', () {
    test('a third of the way up: 900 mm makes a 2,700 mm wall', () {
      final e = estimateWallSize(1.5, labels: kitchen(1 / 3), wallCorners: corners);
      expect(e.cue, SizeCue.worktop);
      expect(e.heightMm, closeTo(2700, 40));
      expect(e.widthMm, closeTo(e.heightMm * 1.5, 10));
    });

    test('lower on the wall: a taller wall', () {
      final e = estimateWallSize(1.2, labels: kitchen(0.3), wallCorners: corners);
      expect(e.cue, SizeCue.worktop);
      expect(e.heightMm, closeTo(3000, 50));
    });

    test('things on the worktop in a few places don\'t move it', () {
      final labels = labelled((u, v) {
        if (v > 2 / 3) return WallLabels.cabinet;
        // A kettle and a tall bottle, standing on the worktop.
        final onTop = (u > 0.2 && u < 0.27 && v > 0.55) || (u > 0.6 && u < 0.64 && v > 0.45);
        return onTop ? 0 : WallLabels.wall;
      });
      final e = estimateWallSize(1.5, labels: labels, wallCorners: corners);
      expect(e.cue, SizeCue.worktop);
      expect(e.heightMm, closeTo(2700, 40));
    });

    test('in a corner of the wall only: not trusted', () {
      final labels = labelled((u, v) =>
          u < 0.12 && v > 2 / 3 ? WallLabels.cabinet : WallLabels.wall);
      expect(estimateWallSize(1.5, labels: labels, wallCorners: corners).cue,
          SizeCue.assumed);
    });

    test('too high to be a worktop (a 1,900 mm ceiling): not trusted', () {
      final e = estimateWallSize(1.5, labels: kitchen(0.47), wallCorners: corners);
      expect(e.cue, isNot(SizeCue.worktop));
    });
  });

  group('from a door', () {
    WallLabels withDoor(double up) => labelled((u, v) =>
        u > 0.4 && u < 0.7 && v > 1 - up ? WallLabels.door : WallLabels.wall);

    test('its top three quarters of the way up: 2,100 mm makes 2,800', () {
      final e = estimateWallSize(1.4, labels: withDoor(0.75), wallCorners: corners);
      expect(e.cue, SizeCue.door);
      expect(e.heightMm, closeTo(2800, 40));
    });

    test('too short to be a door: not trusted', () {
      final e = estimateWallSize(1.4, labels: withDoor(0.4), wallCorners: corners);
      expect(e.cue, SizeCue.assumed);
    });

    test('the worktop wins when there are both', () {
      final labels = labelled((u, v) {
        if (u > 0.05 && u < 0.3 && v > 0.25) return WallLabels.door;
        return v > 2 / 3 ? WallLabels.cabinet : WallLabels.wall;
      });
      final e = estimateWallSize(1.5, labels: labels, wallCorners: corners);
      expect(e.cue, SizeCue.worktop);
    });
  });

  test('nothing to go by: the usual ceiling, the width from the proportions', () {
    final e = estimateWallSize(1.48);
    expect(e.cue, SizeCue.assumed);
    expect(e.heightMm, kAssumedCeilingMm);
    expect(e.widthMm, 4000); // 2,700 × 1.48 = 3,996, to the nearest 10
    final plain = labelled((u, v) => WallLabels.wall);
    expect(estimateWallSize(1.48, labels: plain, wallCorners: corners).cue,
        SizeCue.assumed);
  });
}
