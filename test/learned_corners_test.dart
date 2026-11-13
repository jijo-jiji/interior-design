import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/utils/corner_finder.dart';
import 'package:static_trace/features/trace/utils/learned_corners.dart';
import 'package:static_trace/features/trace/utils/opening_finder.dart';

const n = kCornerModelSize, cells = n * n;

/// A depth map from a formula, the same one as the Python check that gave
/// the expected numbers below (synth.normalise, then Pillow's BOX resize).
DepthMap formulaDepth() {
  const w = 686, h = 518;
  final v = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      v[y * w + x] = 2 * math.sin(x * 0.013) +
          math.cos(y * 0.021) +
          x * y * 1e-5 +
          (x % 7) * 0.01;
    }
  }
  return DepthMap(w, h, v);
}

WallLabels allWall() =>
    WallLabels(n, n, Uint8List(cells)..fillRange(0, cells, WallLabels.wall));

void main() {
  group('the corner model’s input', () {
    test('depth is scaled and shrunk exactly as in training', () {
      final x = cornerModelInput(formulaDepth(), allWall(), 4 / 3);
      expect(x.length, kCornerModelChannels * cells);
      var sum = 0.0;
      for (var i = 0; i < cells; i++) {
        sum += x[i];
      }
      expect(sum, closeTo(8186.432279, 0.01));
      // Cells (row, column) and their values from the Python check.
      const expected = {
        (0, 0): 0.4747258,
        (5, 77): 0.2430069,
        (64, 64): 0.2718231,
        (100, 3): 0.3132204,
        (127, 127): 0.9568652,
        (31, 120): 0.5618840,
      };
      expected.forEach((cell, value) {
        expect(x[cell.$1 * n + cell.$2], closeTo(value, 2e-5),
            reason: 'cell $cell');
      });
    });

    test('labels become one map per class; unknown ones count as other', () {
      final ids = Uint8List(cells);
      ids[0] = WallLabels.wall;
      ids[1] = WallLabels.floor;
      ids[2] = WallLabels.ceiling;
      ids[3] = WallLabels.window;
      ids[4] = WallLabels.curtain;
      ids[5] = WallLabels.cabinet;
      ids[6] = WallLabels.door;
      ids[7] = 23; // a painting, say
      final x = cornerModelInput(formulaDepth(), WallLabels(n, n, ids), 1);
      int classOf(int cell) {
        final on = [
          for (var c = 0; c < 7; c++)
            if (x[(1 + c) * cells + cell] == 1) c
        ];
        expect(on.length, 1, reason: 'cell $cell is in exactly one class');
        return on.single;
      }

      expect([for (var i = 0; i < 8; i++) classOf(i)], [0, 1, 2, 3, 3, 4, 5, 6]);
    });

    test('where each cell is, and the photo’s shape', () {
      final x = cornerModelInput(formulaDepth(), allWall(), 16 / 9);
      const u = 8 * cells, v = 9 * cells, aspect = 10 * cells;
      expect(x[u + 0], closeTo(0.5 / n, 1e-7));
      expect(x[u + n - 1], closeTo((n - 0.5) / n, 1e-7));
      expect(x[v + 0], closeTo(0.5 / n, 1e-7));
      expect(x[v + (n - 1) * n], closeTo((n - 0.5) / n, 1e-7));
      expect(x[aspect + 1234], closeTo(math.log(16 / 9), 1e-6));
    });

    test('labels of another size are resampled', () {
      final ids = Uint8List(64 * 64)..fillRange(0, 64 * 64, WallLabels.floor);
      final x = cornerModelInput(formulaDepth(), WallLabels(64, 64, ids), 1);
      expect(x[2 * cells + 500], 1); // floor
    });
  });

  group('trusting its answer', () {
    const corners = <double>[0.2, 0.1, 0.8, 0.12, 0.79, 0.9, 0.21, 0.88];

    test('sure enough: its corners', () {
      final got = trustedCorners([...corners, ...List.filled(8, 0.02)]);
      expect(got!.corners, const [
        Offset(0.2, 0.1),
        Offset(0.8, 0.12),
        Offset(0.79, 0.9),
        Offset(0.21, 0.88),
      ]);
      expect(got.wallBottom, isNull); // an older model doesn't say
    });

    group('with the hidden bottom corners', () {
      const hidden = <double>[0.83, 0.8, 0.25, 0.79];

      test('sure of them: given for measuring', () {
        final got = trustedCorners(
            [...corners, ...hidden, ...List.filled(12, 0.02)]);
        expect(got!.corners[2], const Offset(0.79, 0.9));
        expect(got.wallBottom, const [Offset(0.83, 0.8), Offset(0.25, 0.79)]);
      });

      test('unsure of them: the corners alone', () {
        final errors = List.filled(12, 0.02)..[9] = kHiddenMaxError + 0.01;
        final got = trustedCorners([...corners, ...hidden, ...errors]);
        expect(got!.corners, hasLength(4));
        expect(got.wallBottom, isNull);
      });

      test('unsure of a corner: nothing', () {
        final errors = List.filled(12, 0.02)..[3] = 0.04;
        expect(trustedCorners([...corners, ...hidden, ...errors]), isNull);
      });
    });

    test('unsure of any one coordinate: nothing', () {
      final errors = List.filled(8, 0.01)..[5] = 0.04;
      expect(trustedCorners([...corners, ...errors]), isNull);
      expect(trustedCorners([...corners, ...List.filled(8, double.nan)]),
          isNull);
    });

    test('a corner off the photo: nothing', () {
      final off = [...corners]..[1] = -0.1;
      expect(trustedCorners([...off, ...List.filled(8, 0.01)]), isNull);
      final nan = [...corners]..[4] = double.nan;
      expect(trustedCorners([...nan, ...List.filled(8, 0.01)]), isNull);
      final justOff = [...corners]..[1] = -0.01;
      expect(trustedCorners([...justOff, ...List.filled(8, 0.01)]),
          isNotNull);
    });

    test('a short answer: nothing', () {
      expect(trustedCorners(corners), isNull);
    });
  });
}
