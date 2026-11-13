import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'corner_finder.dart' show DepthMap;
import 'opening_finder.dart' show WallLabels;

/// Our own corner model (tool/wall_corner_training/ trains it). It was
/// trained on made-up kitchens and rooms whose corners are known exactly,
/// so it finds the wall's corners behind cabinets, where the depth patches
/// (corner_finder.dart) can't. It reads the depth map and the segmentation
/// labels the app already has, not the photo itself.
const kCornerModelAsset = 'assets/models/wall_corners.onnx';

/// Its input: [kCornerModelChannels] maps of [kCornerModelSize] squared.
const int kCornerModelSize = 128;
const int kCornerModelChannels = 11;

/// Its corners are used only when it expects every one to be within this
/// fraction of the photo. On real photos, the corners it was this sure of
/// were right, and those it got wrong it was less sure of
/// (tool/wall_corner_training/README.md).
const double kLearnedMaxError = 0.03;

/// Corners further outside the photo than this can't be marked on it.
const double _outside = 0.02;

// The model's classes (wall, floor, ceiling, window, cabinet, door, other)
// from the segmentation model's ADE20K ids, as in synth.py's ADE_TO_CLASS.
const int _numClasses = 7, _other = 6;
const Map<int, int> _adeToClass = {
  WallLabels.wall: 0,
  WallLabels.floor: 1,
  WallLabels.ceiling: 2,
  WallLabels.window: 3,
  WallLabels.curtain: 3,
  WallLabels.cabinet: 4,
  WallLabels.door: 5,
};

/// The corner model's input for a photo, laid out channel by channel:
/// depth scaled to 0..1, one map per class, the cell's x and y as
/// fractions, and the photo's log aspect (width / height). Exactly as
/// tool/wall_corner_training/evaluate.py builds it.
Float32List cornerModelInput(
    DepthMap depth, WallLabels labels, double aspect) {
  const n = kCornerModelSize, cells = n * n;
  final x = Float32List(kCornerModelChannels * cells);
  x.setRange(0, cells, _shrinkBox(_normalise(depth), depth.width, depth.height, n));

  final ids = labels.width == n && labels.height == n
      ? labels.ids
      : _shrinkNearest(labels, n);
  for (var i = 0; i < cells; i++) {
    final c = _adeToClass[ids[i]] ?? _other;
    x[(1 + c) * cells + i] = 1;
  }

  final logAspect = math.log(aspect);
  for (var row = 0; row < n; row++) {
    for (var col = 0; col < n; col++) {
      final i = row * n + col;
      x[(1 + _numClasses) * cells + i] = (col + 0.5) / n;
      x[(2 + _numClasses) * cells + i] = (row + 0.5) / n;
      x[(3 + _numClasses) * cells + i] = logAspect;
    }
  }
  return x;
}

/// The hidden bottom corners are used for measuring only when the model
/// expects them within this fraction of the photo; otherwise the wall is
/// measured from the corners as marked.
const double kHiddenMaxError = 0.05;

/// What the corner model found, when it's sure enough to use.
class LearnedCorners {
  const LearnedCorners(this.corners, this.wallBottom);

  /// The wall's corners as a salesperson marks them (top-left, top-right,
  /// bottom-right, bottom-left), as fractions of the photo. In a kitchen the
  /// bottom ones are where the floor meets the cabinets.
  final List<Offset> corners;

  /// Where the wall really meets the floor behind the cabinets
  /// (bottom-right, bottom-left), which the wall is measured from. Null if
  /// the model doesn't say or isn't sure.
  final List<Offset>? wallBottom;
}

/// The model's answer, if it's sure enough to use. [output] is its points as
/// fractions of the photo (x then y: the four corners as marked, then, from
/// a newer model, the two hidden bottom corners), then how far off it
/// expects each of those numbers to be: 16 or 24 numbers in all.
LearnedCorners? trustedCorners(List<double> output,
    {double maxError = kLearnedMaxError}) {
  if (output.length != 16 && output.length != 24) return null;
  final n = output.length ~/ 2; // the coordinates; their errors follow
  for (var i = n; i < n + 8; i++) {
    if (!(output[i] <= maxError)) return null; // NaN too
  }
  final points = [
    for (var k = 0; k < n ~/ 2; k++) Offset(output[2 * k], output[2 * k + 1])
  ];
  bool inside(Offset p) =>
      p.dx >= -_outside &&
      p.dx <= 1 + _outside &&
      p.dy >= -_outside &&
      p.dy <= 1 + _outside;
  final corners = points.sublist(0, 4);
  if (!corners.every(inside)) return null;

  List<Offset>? wallBottom;
  if (points.length == 6) {
    final hidden = points.sublist(4);
    final sure = [for (var i = n + 8; i < 2 * n; i++) output[i]]
        .every((e) => e <= kHiddenMaxError);
    if (sure && hidden.every(inside)) wallBottom = hidden;
  }
  return LearnedCorners(corners, wallBottom);
}

/// Depth to 0..1 between its 1st and 99th percentiles (numpy's
/// percentile, interpolating between neighbours).
Float32List _normalise(DepthMap depth) {
  final sorted = Float32List.fromList(depth.values)..sort();
  double percentile(double q) {
    final pos = q / 100 * (sorted.length - 1);
    final i = pos.floor();
    if (i + 1 >= sorted.length) return sorted.last;
    return sorted[i] + (sorted[i + 1] - sorted[i]) * (pos - i);
  }

  final lo = percentile(1), hi = percentile(99);
  final span = math.max(hi - lo, 1e-9);
  final out = Float32List(depth.values.length);
  for (var i = 0; i < out.length; i++) {
    out[i] = ((depth.values[i] - lo) / span).clamp(0.0, 1.0);
  }
  return out;
}

/// Down to n × n by averaging, like Pillow's BOX resize: each output cell
/// is the mean of the input pixels whose centres fall inside it.
Float32List _shrinkBox(Float32List values, int w, int h, int n) {
  List<int> edges(int size) => [
        for (var i = 0; i <= n; i++)
          math.min(size, (i * size / n + 0.5).floor()),
      ];
  final xs = edges(w), ys = edges(h);
  final out = Float32List(n * n);
  for (var row = 0; row < n; row++) {
    for (var col = 0; col < n; col++) {
      var sum = 0.0;
      var count = 0;
      for (var y = ys[row]; y < math.max(ys[row + 1], ys[row] + 1); y++) {
        for (var x = xs[col]; x < math.max(xs[col + 1], xs[col] + 1); x++) {
          sum += values[math.min(y, h - 1) * w + math.min(x, w - 1)];
          count++;
        }
      }
      out[row * n + col] = sum / count;
    }
  }
  return out;
}

/// Labels down (or up) to n × n, taking the nearest cell.
Uint8List _shrinkNearest(WallLabels labels, int n) {
  final out = Uint8List(n * n);
  for (var row = 0; row < n; row++) {
    final y = math.min(labels.height - 1, ((row + 0.5) * labels.height / n).floor());
    for (var col = 0; col < n; col++) {
      final x = math.min(labels.width - 1, ((col + 0.5) * labels.width / n).floor());
      out[row * n + col] = labels.ids[y * labels.width + x];
    }
  }
  return out;
}
