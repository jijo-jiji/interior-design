import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'homography.dart';
import 'opening_finder.dart' show WallLabels;
import 'reference_card.dart';

/// A photo shows the wall's proportions but not its size: a wall twice as
/// big, twice as far away, looks the same. The size comes from something of
/// known size on the wall:
///   - an A4 sheet taped on it, if one was marked: measured, not guessed
///     (reference_card.dart);
///   - the worktop: the backsplash meets it about 900 mm up;
///   - a door: its top is about 2,100 mm up;
///   - failing both, the usual ceiling height.
/// The salesperson checks the result and types a measurement if it's off.
const double kWorktopMm = 900;
const double kDoorTopMm = 2100;
const double kAssumedCeilingMm = 2700;

/// Walls outside this range are a misreading, not a room.
const double kMinEstimateMm = 2200, kMaxEstimateMm = 3600;

/// What the wall's size was worked out from.
enum SizeCue { sheet, worktop, door, assumed }

class WallSizeEstimate {
  const WallSizeEstimate(this.widthMm, this.heightMm, this.cue);
  final double widthMm, heightMm;
  final SizeCue cue;
}

// The straightened wall is sampled on this grid: columns across, rows down,
// finely down so that only the labels' own coarseness limits the height.
// A run of _run rows (2.5% of the wall) counts as a stretch of one thing.
const int _cols = 60, _rows = 360, _run = 9;

/// The wall's size from the photo. [aspect]: its width over its height, from
/// the traced corners. [labels]: the segmentation of the photo, if there is
/// one. [wallCorners]: the wall's own corners as fractions of the photo
/// (top-left, top-right, bottom-right, bottom-left; in a kitchen the bottom
/// ones where the wall meets the floor behind the cabinets). [sheet]: the
/// wall measured from an A4 sheet on it, used before anything else when the
/// sheet is all on the wall.
WallSizeEstimate estimateWallSize(double aspect,
    {WallLabels? labels, List<Offset>? wallCorners, SheetMeasure? sheet}) {
  if (sheet != null && sheet.onWall) {
    return WallSizeEstimate((sheet.widthMm / 10).roundToDouble() * 10,
        (sheet.heightMm / 10).roundToDouble() * 10, SizeCue.sheet);
  }
  var height = kAssumedCeilingMm;
  var cue = SizeCue.assumed;
  final grid = labels == null || wallCorners == null
      ? null
      : _straightened(labels, wallCorners);
  if (grid != null) {
    final fromWorktop = _worktopHeight(grid);
    final fromDoor = _doorHeight(grid);
    if (fromWorktop != null) {
      (height, cue) = (fromWorktop, SizeCue.worktop);
    } else if (fromDoor != null) {
      (height, cue) = (fromDoor, SizeCue.door);
    }
  }
  height = (height / 10).roundToDouble() * 10;
  return WallSizeEstimate(
      (height * aspect / 10).roundToDouble() * 10, height, cue);
}

/// The labels resampled onto the wall: [_rows] × [_cols], row by row, -1
/// where the wall is off the photo. Null if the corners make no wall.
List<int>? _straightened(WallLabels labels, List<Offset> corners) {
  final toPhoto = Homography.between(const [
    Offset(0, 0),
    Offset(1, 0),
    Offset(1, 1),
    Offset(0, 1),
  ], corners);
  if (toPhoto == null) return null;
  final grid = List<int>.filled(_rows * _cols, -1);
  for (var r = 0; r < _rows; r++) {
    for (var c = 0; c < _cols; c++) {
      final p = toPhoto.map(Offset((c + 0.5) / _cols, (r + 0.5) / _rows));
      final x = (p.dx * labels.width).floor(), y = (p.dy * labels.height).floor();
      if (x < 0 || y < 0 || x >= labels.width || y >= labels.height) continue;
      grid[r * _cols + c] = labels.ids[y * labels.width + x];
    }
  }
  return grid;
}

/// Cabinets, a worktop, things on it: whatever isn't the room itself.
bool _fitted(int id) =>
    id >= 0 &&
    id != WallLabels.wall &&
    id != WallLabels.floor &&
    id != WallLabels.ceiling &&
    id != WallLabels.window &&
    id != WallLabels.curtain &&
    id != WallLabels.door;

/// In each column, the lowest place where wall (the backsplash) sits right
/// on top of cabinets: the worktop. Their median, 20–50% up the wall, in
/// enough columns, gives the wall's height.
double? _worktopHeight(List<int> grid) {
  int at(int r, int c) => grid[r * _cols + c];
  final tops = <double>[];
  bool all(int c, int from, int to, bool Function(int) test) {
    for (var r = from; r < to; r++) {
      if (!test(at(r, c))) return false;
    }
    return true;
  }

  for (var c = 0; c < _cols; c++) {
    for (var r = _rows - 1 - _run; r >= _run; r--) {
      // Wall at r and the rows above it, fitted things in the rows below.
      if (at(r, c) == WallLabels.wall &&
          _fitted(at(r + 1, c)) &&
          all(c, r - _run + 1, r + 1, (id) => id == WallLabels.wall) &&
          all(c, r + 1, r + 1 + _run, _fitted)) {
        final top = (r + 1) / _rows;
        if (top >= 0.5 && top <= 0.8) tops.add(top);
        break;
      }
    }
  }
  if (tops.length < math.max(6, _cols ~/ 4)) return null;
  return _plausible(kWorktopMm / (1 - _median(tops)));
}

/// A door standing on the floor: its top, in enough columns, 55–95% up the
/// wall, gives the wall's height.
double? _doorHeight(List<int> grid) {
  final tops = <double>[];
  for (var c = 0; c < _cols; c++) {
    int? first, last;
    var count = 0;
    for (var r = 0; r < _rows; r++) {
      if (grid[r * _cols + c] != WallLabels.door) continue;
      first ??= r;
      last = r;
      count++;
    }
    if (first != null && count >= _run && last! >= 0.85 * _rows) {
      tops.add(first / _rows);
    }
  }
  if (tops.length < 3) return null;
  final up = 1 - _median(tops);
  if (up < 0.55 || up > 0.95) return null;
  return _plausible(kDoorTopMm / up);
}

double? _plausible(double mm) =>
    mm >= kMinEstimateMm && mm <= kMaxEstimateMm ? mm : null;

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}
