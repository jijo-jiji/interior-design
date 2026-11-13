import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// A perspective mapping between two planes: a 3×3 homography.
///
/// A photo of a flat wall is the wall seen in perspective, so the four
/// corners of the wall on the photo and its real width and height fix the
/// mapping exactly, with no camera calibration: every other point on the
/// wall (a window's corner, a door's edge) maps through it to true wall
/// millimetres, however the photo was angled.
class Homography {
  const Homography._(this.m);

  /// Row-major 3×3, `m[8]` normalised to 1.
  final List<double> m;

  /// The mapping that sends `from[i]` to `to[i]` (four points each), or null
  /// if three of the points are in a line.
  static Homography? between(List<Offset> from, List<Offset> to) {
    assert(from.length == 4 && to.length == 4);
    final a = <List<double>>[];
    for (var i = 0; i < 4; i++) {
      final x = from[i].dx, y = from[i].dy;
      final u = to[i].dx, v = to[i].dy;
      a.add([x, y, 1, 0, 0, 0, -u * x, -u * y, u]);
      a.add([0, 0, 0, x, y, 1, -v * x, -v * y, v]);
    }
    final h = _solve(a);
    if (h == null) return null;
    return Homography._([...h, 1]);
  }

  Offset map(Offset p) {
    final w = m[6] * p.dx + m[7] * p.dy + m[8];
    return Offset(
      (m[0] * p.dx + m[1] * p.dy + m[2]) / w,
      (m[3] * p.dx + m[4] * p.dy + m[5]) / w,
    );
  }

  Homography? inverse() {
    final [a, b, c, d, e, f, g, h, i] = m;
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < 1e-12) return null;
    final inv = [
      (e * i - f * h), -(b * i - c * h), (b * f - c * e),
      -(d * i - f * g), (a * i - c * g), -(a * f - c * d),
      (d * h - e * g), -(a * h - b * g), (a * e - b * d),
    ].map((v) => v / det).toList();
    final s = inv[8];
    if (s.abs() < 1e-15) return null;
    return Homography._(inv.map((v) => v / s).toList());
  }

  /// Gaussian elimination with partial pivoting on an 8×9 augmented matrix.
  static List<double>? _solve(List<List<double>> a) {
    const n = 8;
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      if (a[pivot][col].abs() < 1e-12) return null;
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final k = a[r][col] / a[col][col];
        if (k == 0) continue;
        for (var c = col; c <= n; c++) {
          a[r][c] -= k * a[col][c];
        }
      }
    }
    return [for (var r = 0; r < n; r++) a[r][n] / a[r][r]];
  }
}

/// Where the camera's focal length came from.
enum FocalSource {
  /// The photo's EXIF data (35 mm equivalent): the most reliable.
  photo,

  /// Worked out from the corners: needs the wall seen at an angle both ways.
  corners,

  /// A typical phone camera (26 mm equivalent).
  assumed,
}

/// The wall's real shape, worked out from where its corners are on a photo.
class WallShapeEstimate {
  const WallShapeEstimate({
    required this.aspect,
    required this.focalPx,
    required this.focalSource,
  });

  /// Real width ÷ real height.
  final double aspect;
  final double focalPx;
  final FocalSource focalSource;
}

/// 35 mm film's diagonal, for EXIF "focal length in 35 mm film".
const double _filmDiagonalMm = 43.2666;

/// A phone's main camera is about 26 mm equivalent.
const double kAssumedFocal35mm = 26;

/// The focal length in photo pixels for a 35 mm-equivalent focal length.
double focalPxFrom35mm(double focal35mm, Size photo) =>
    focal35mm * math.sqrt(photo.width * photo.width + photo.height * photo.height) /
    _filmDiagonalMm;

/// The wall's width ÷ height from its four corners on the photo, in pixels,
/// in the order top-left, top-right, bottom-right, bottom-left.
///
/// A rectangle seen in perspective keeps its true proportions in the
/// mapping from the photo back to the plane, once the camera's focal length
/// is known: the two directions along the wall must come out at right
/// angles. With the wall seen at an angle both ways, that alone gives the
/// focal length; otherwise it comes from the photo's EXIF data or a typical
/// phone camera. Head-on, the focal length doesn't matter at all.
WallShapeEstimate? estimateWallShape(
  List<Offset> cornersPx,
  Size photo, {
  double? focalPx,
}) {
  const unit = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
  final g = Homography.between(unit, cornersPx);
  if (g == null) return null;
  final m = g.m;
  final cx = photo.width / 2, cy = photo.height / 2;
  // The two directions along the wall, with the photo's centre as origin.
  final a1 = m[0] - cx * m[6], b1 = m[3] - cy * m[6], c1 = m[6];
  final a2 = m[1] - cx * m[7], b2 = m[4] - cy * m[7], c2 = m[7];

  final diagonal =
      math.sqrt(photo.width * photo.width + photo.height * photo.height);
  double? fromCorners;
  // Both directions must converge noticeably for the right-angle rule to
  // pin the focal length down.
  if (c1.abs() > 0.02 && c2.abs() > 0.02) {
    final f2 = -(a1 * a2 + b1 * b2) / (c1 * c2);
    if (f2 > 0) {
      final f = math.sqrt(f2);
      if (f > 0.3 * diagonal && f < 3 * diagonal) fromCorners = f;
    }
  }

  final double f;
  final FocalSource source;
  if (focalPx != null && focalPx > 0) {
    (f, source) = (focalPx, FocalSource.photo);
  } else if (fromCorners != null) {
    (f, source) = (fromCorners, FocalSource.corners);
  } else {
    (f, source) =
        (focalPxFrom35mm(kAssumedFocal35mm, photo), FocalSource.assumed);
  }

  final along = math.sqrt((a1 * a1 + b1 * b1) / (f * f) + c1 * c1);
  final down = math.sqrt((a2 * a2 + b2 * b2) / (f * f) + c2 * c2);
  if (down == 0) return null;
  return WallShapeEstimate(aspect: along / down, focalPx: f, focalSource: source);
}
