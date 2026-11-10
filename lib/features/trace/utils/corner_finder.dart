import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// A depth model's output: relative inverse depth (bigger = nearer), row by
/// row, [width] × [height].
class DepthMap {
  DepthMap(this.width, this.height, this.values)
      : assert(values.length == width * height);

  final int width, height;
  final Float32List values;
}

/// The wall in front of the camera, found from a depth map: its four corners
/// as fractions of the photo (top-left, top-right, bottom-right, bottom-left),
/// or null when it can't be found with confidence.
///
/// In inverse depth every flat surface of a room is a flat patch over the
/// image (d = a·u + b·v + c), whatever the depth's unknown scale and shift.
/// So: fit the room's flat patches (front wall, side walls, ceiling, floor),
/// take the one in the middle of the photo as the front wall, follow its
/// outline from the middle outwards, and fit a straight line to each side;
/// the corners are where those lines cross. A window or a light switch on
/// the wall is stepped over; a wall cut off by the photo's edge gives no
/// answer.
///
/// The answer must also sit in the room the way a wall does: ceiling above
/// it, floor below (reaching the photo's bottom, so not a counter), a side
/// wall left and right ([_inRoom]). In a kitchen the middle of the photo is
/// a cabinet front, a fridge or the backsplash strip, with more cabinets or
/// a counter around it, so it gives no answer and the corners are placed by
/// hand: on 9 kitchen photos, all were turned down, while both empty rooms
/// tested passed with their corners 3–11 px from hand-marked ones
/// (tool/wall_benchmark/web_photos/).
///
/// [tau] is how far (in depth normalised to 0..1) a pixel may be from a
/// patch and still belong to it. 0.012 is tuned on the depth model's real
/// output: tighter suits exact geometry but breaks on the model's noise.
/// The weak spot is a wall far away and small in the photo, where its
/// corners blur into the side walls: the answer is then rougher, or none.
///
/// Prototype and measurements: tool/wall_benchmark/depth_corners.py.
List<Offset>? cornersFromDepth(DepthMap depth, {double tau = 0.012}) {
  final rng = math.Random(7); // the same answer every time
  final w = depth.width, h = depth.height;
  if (w < 32 || h < 32) return null;

  // Fit the patches on a small copy; it's the slow part.
  final small = _shrink(depth, 160);
  final sorted = Float32List.fromList(small.values)..sort();
  final lo = sorted[(sorted.length * 0.01).floor()];
  final hi = sorted[math.min(sorted.length - 1, (sorted.length * 0.99).floor())];
  if (hi - lo < 1e-6) return null;
  double norm(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);


  final planes = _planes(small, norm, tau, rng);
  if (planes.length < 2) return null;
  final label = _label(depth, planes, norm, tau);

  // The front wall: the patch covering most of the middle of the photo.
  final counts = List<int>.filled(planes.length, 0);
  final sumX = List<int>.filled(planes.length, 0);
  final sumY = List<int>.filled(planes.length, 0);
  for (var y = (0.35 * h).ceil(); y < 0.65 * h; y++) {
    for (var x = (0.35 * w).ceil(); x < 0.65 * w; x++) {
      final l = label[y * w + x];
      if (l < 0) continue;
      counts[l]++;
      sumX[l] += x;
      sumY[l] += y;
    }
  }
  var front = 0;
  for (var p = 1; p < planes.length; p++) {
    if (counts[p] > counts[front]) front = p;
  }
  if (counts[front] == 0) return null;
  final cx = sumX[front] ~/ counts[front];
  final cy = sumY[front] ~/ counts[front];
  bool isFront(int x, int y) => label[y * w + x] == front;

  final edges = _wallEdges(w, h, isFront, cx, cy);
  final left = _fitLine(edges.left, alongY: true, rng: rng);
  final right = _fitLine(edges.right, alongY: true, rng: rng);
  final top = _fitLine(edges.top, alongY: false, rng: rng);
  final bottom = _fitLine(edges.bottom, alongY: false, rng: rng);
  if (left == null || right == null || top == null || bottom == null) {
    return null;
  }

  final corners = <Offset>[];
  for (final (a, b) in [(top, left), (top, right), (bottom, right), (bottom, left)]) {
    final p = _cross(a, b);
    if (p == null) return null;
    corners.add(Offset(p.dx / w, p.dy / h));
  }
  if (!_plausible(corners)) return null;
  return _inRoom(depth, small, norm, tau, corners) ? corners : null;
}

/// Every pixel of [depth] labelled with its nearest patch (-1 for none).
Int8List _label(DepthMap depth, List<List<double>> planes,
    double Function(double) norm, double tau) {
  final w = depth.width, h = depth.height;
  final label = Int8List(w * h);
  for (var y = 0; y < h; y++) {
    final v = (y + 0.5) / h;
    for (var x = 0; x < w; x++) {
      final u = (x + 0.5) / w;
      final d = norm(depth.values[y * w + x]);
      var best = -1;
      var bestRes = 2.5 * tau;
      for (var p = 0; p < planes.length; p++) {
        final pl = planes[p];
        final res = (pl[0] * u + pl[1] * v + pl[2] - d).abs();
        if (res < bestRes) {
          bestRes = res;
          best = p;
        }
      }
      label[y * w + x] = best;
    }
  }
  return label;
}

enum _Role { ceiling, floor, counter, left, right, front }

/// Whether the wall found sits in the room as a wall does: just outside
/// each side, the right kind of surface. A patch's kind comes from which way
/// it gets nearer: the ceiling towards the top, the floor towards the
/// bottom (and reaching it; a counter doesn't), a side wall towards its
/// edge. Fitted finer than the finder's own patches, so a narrow wall
/// return beside a door still counts.
bool _inRoom(DepthMap depth, DepthMap small, double Function(double) norm,
    double tau, List<Offset> corners) {
  final w = depth.width, h = depth.height;
  final planes = _planes(small, norm, tau, math.Random(7),
      maxPlanes: 10, minFraction: 0.01);
  if (planes.isEmpty) return false;
  final label = _label(depth, planes, norm, tau);

  final atBottom = List<int>.filled(planes.length, 0);
  for (var y = (0.88 * h).ceil(); y < h; y++) {
    for (var x = 0; x < w; x++) {
      final l = label[y * w + x];
      if (l >= 0) atBottom[l]++;
    }
  }
  final roles = [
    for (var p = 0; p < planes.length; p++)
      () {
        final a = planes[p][0], b = planes[p][1];
        if (b < 0 && b.abs() > a.abs()) return _Role.ceiling;
        if (b > 0 && b.abs() > a.abs()) {
          return atBottom[p] > 0.002 * w * h ? _Role.floor : _Role.counter;
        }
        if (a < 0 && a.abs() > b.abs()) return _Role.left;
        if (a > 0 && a.abs() > b.abs()) return _Role.right;
        return _Role.front;
      }()
  ];

  final cx = corners.fold(0.0, (s, c) => s + c.dx) / 4;
  final cy = corners.fold(0.0, (s, c) => s + c.dy) / 4;
  for (final (i, j, want) in [
    (0, 1, _Role.ceiling),
    (1, 2, _Role.right),
    (2, 3, _Role.floor),
    (3, 0, _Role.left),
  ]) {
    final a = corners[i], b = corners[j];
    var out = (a + b) / 2 - Offset(cx, cy);
    out = out / out.distance;
    // The nearest surface may be narrow: the side passes if it's right at
    // any of a few distances out.
    var best = 0.0;
    for (final step in const [0.015, 0.03, 0.045]) {
      var hits = 0, good = 0;
      for (var k = 0; k < 15; k++) {
        final t = 0.15 + 0.7 * k / 14;
        final p = a + (b - a) * t + out * step;
        final x = (p.dx * w).floor(), y = (p.dy * h).floor();
        if (x < 0 || x >= w || y < 0 || y >= h) continue;
        final l = label[y * w + x];
        if (l < 0) continue;
        hits++;
        if (roles[l] == want) good++;
      }
      if (hits >= 5) best = math.max(best, good / hits);
    }
    if (best < 0.6) return false;
  }
  return true;
}

/// Box-averaged copy [width] wide.
DepthMap _shrink(DepthMap d, int width) {
  final w = math.min(width, d.width);
  final h = math.max(1, (w * d.height / d.width).round());
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = y * d.height ~/ h, y1 = math.max(y0 + 1, (y + 1) * d.height ~/ h);
    for (var x = 0; x < w; x++) {
      final x0 = x * d.width ~/ w, x1 = math.max(x0 + 1, (x + 1) * d.width ~/ w);
      var sum = 0.0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          sum += d.values[yy * d.width + xx];
        }
      }
      out[y * w + x] = sum / ((y1 - y0) * (x1 - x0));
    }
  }
  return DepthMap(w, h, out);
}

/// Flat patches, largest first, by sequential RANSAC: each as [a, b, c].
List<List<double>> _planes(DepthMap s, double Function(double) norm,
    double tau, math.Random rng,
    {int maxPlanes = 6, double minFraction = 0.03}) {
  final n = s.width * s.height;
  final u = Float64List(n), v = Float64List(n), d = Float64List(n);
  for (var i = 0; i < n; i++) {
    u[i] = (i % s.width + 0.5) / s.width;
    v[i] = (i ~/ s.width + 0.5) / s.height;
    d[i] = norm(s.values[i]);
  }
  final free = List<bool>.filled(n, true);
  final planes = <List<double>>[];
  for (var round = 0; round < maxPlanes; round++) {
    final idx = [for (var i = 0; i < n; i++) if (free[i]) i];
    if (idx.length < minFraction * n) break;
    List<double>? best;
    var bestCount = 0;
    for (var it = 0; it < 600; it++) {
      final a = idx[rng.nextInt(idx.length)];
      final b = idx[rng.nextInt(idx.length)];
      final c = idx[rng.nextInt(idx.length)];
      if (a == b || b == c || a == c) continue;
      final plane = _solve3([
        [u[a], v[a], 1, d[a]],
        [u[b], v[b], 1, d[b]],
        [u[c], v[c], 1, d[c]],
      ]);
      if (plane == null) continue;
      var count = 0;
      for (final i in idx) {
        if ((plane[0] * u[i] + plane[1] * v[i] + plane[2] - d[i]).abs() < tau) {
          count++;
        }
      }
      if (count > bestCount) {
        bestCount = count;
        best = plane;
      }
    }
    if (best == null || bestCount < minFraction * n) break;
    // Refit on the inliers, then take the inliers of the refit.
    var plane = best;
    for (var pass = 0; pass < 2; pass++) {
      final inl = [
        for (final i in idx)
          if ((plane[0] * u[i] + plane[1] * v[i] + plane[2] - d[i]).abs() < tau) i
      ];
      if (pass == 1) {
        for (final i in inl) {
          free[i] = false;
        }
        break;
      }
      plane = _leastSquaresPlane(inl, u, v, d) ?? plane;
    }
    planes.add(plane);
  }
  return planes;
}

/// Solves a·u + b·v + c = d for three points, rows [u, v, 1, d].
List<double>? _solve3(List<List<double>> m) {
  for (var col = 0; col < 3; col++) {
    var pivot = col;
    for (var r = col + 1; r < 3; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    if (m[pivot][col].abs() < 1e-12) return null;
    final t = m[col];
    m[col] = m[pivot];
    m[pivot] = t;
    for (var r = 0; r < 3; r++) {
      if (r == col) continue;
      final k = m[r][col] / m[col][col];
      for (var c = col; c < 4; c++) {
        m[r][c] -= k * m[col][c];
      }
    }
  }
  return [for (var r = 0; r < 3; r++) m[r][3] / m[r][r]];
}

List<double>? _leastSquaresPlane(
    List<int> idx, Float64List u, Float64List v, Float64List d) {
  // Normal equations for [u v 1]·[a b c] = d.
  var suu = 0.0, suv = 0.0, su = 0.0, svv = 0.0, sv = 0.0;
  var sud = 0.0, svd = 0.0, sd = 0.0;
  for (final i in idx) {
    suu += u[i] * u[i];
    suv += u[i] * v[i];
    su += u[i];
    svv += v[i] * v[i];
    sv += v[i];
    sud += u[i] * d[i];
    svd += v[i] * d[i];
    sd += d[i];
  }
  return _solve3([
    [suu, suv, su, sud],
    [suv, svv, sv, svd],
    [su, sv, idx.length.toDouble(), sd],
  ]);
}

class _Edges {
  final left = <Offset>[], right = <Offset>[], top = <Offset>[], bottom = <Offset>[];
}

/// The front wall's edge points, walking out from its middle along every
/// row and column, across small gaps (a window frame, a light switch).
_Edges _wallEdges(int w, int h, bool Function(int x, int y) isFront, int cx,
    int cy, {int gap = 6, int margin = 2}) {
  final e = _Edges();
  int walk(bool Function(int i) on, int length, int start, int step) {
    var last = start, misses = 0, i = start;
    while (i + step >= 0 && i + step < length) {
      i += step;
      if (on(i)) {
        last = i;
        misses = 0;
      } else if (++misses > gap) {
        break;
      }
    }
    return last;
  }

  for (var y = 0; y < h; y++) {
    var near = false;
    for (var x = math.max(0, cx - 3); x < math.min(w, cx + 4); x++) {
      if (isFront(x, y)) near = true;
    }
    if (!near) continue;
    final l = walk((x) => isFront(x, y), w, cx, -1);
    final r = walk((x) => isFront(x, y), w, cx, 1);
    if (l > margin) e.left.add(Offset(l.toDouble(), y.toDouble()));
    if (r < w - 1 - margin) e.right.add(Offset(r.toDouble(), y.toDouble()));
  }
  for (var x = 0; x < w; x++) {
    var near = false;
    for (var y = math.max(0, cy - 3); y < math.min(h, cy + 4); y++) {
      if (isFront(x, y)) near = true;
    }
    if (!near) continue;
    final t = walk((y) => isFront(x, y), h, cy, -1);
    final b = walk((y) => isFront(x, y), h, cy, 1);
    if (t > margin) e.top.add(Offset(x.toDouble(), t.toDouble()));
    if (b < h - 1 - margin) e.bottom.add(Offset(x.toDouble(), b.toDouble()));
  }
  return e;
}

/// A robust straight line through edge points, as [A, B, C] with
/// A·x + B·y + C = 0: x as a function of y for a side, y of x for top and
/// bottom.
List<double>? _fitLine(List<Offset> pts,
    {required bool alongY, required math.Random rng, double tol = 2}) {
  if (pts.length < 8) return null;
  final s = [for (final p in pts) alongY ? p.dy : p.dx];
  final t = [for (final p in pts) alongY ? p.dx : p.dy];
  (double, double)? best;
  var bestCount = 0;
  for (var it = 0; it < 300; it++) {
    final i = rng.nextInt(pts.length), j = rng.nextInt(pts.length);
    if (i == j || s[i] == s[j]) continue;
    final m = (t[j] - t[i]) / (s[j] - s[i]);
    final b = t[i] - m * s[i];
    var count = 0;
    for (var k = 0; k < pts.length; k++) {
      if ((m * s[k] + b - t[k]).abs() < tol) count++;
    }
    if (count > bestCount) {
      bestCount = count;
      best = (m, b);
    }
  }
  if (best == null) return null;
  final (m0, b0) = best;
  // Least squares on the inliers.
  var n = 0, ss = 0.0, st = 0.0, sss = 0.0, sst = 0.0;
  for (var k = 0; k < pts.length; k++) {
    if ((m0 * s[k] + b0 - t[k]).abs() >= tol) continue;
    n++;
    ss += s[k];
    st += t[k];
    sss += s[k] * s[k];
    sst += s[k] * t[k];
  }
  final den = n * sss - ss * ss;
  if (n < 2 || den.abs() < 1e-9) return null;
  final m = (n * sst - ss * st) / den;
  final b = (st - m * ss) / n;
  return alongY ? [-1, m, b] : [m, -1, b];
}

Offset? _cross(List<double> l1, List<double> l2) {
  final det = l1[0] * l2[1] - l2[0] * l1[1];
  if (det.abs() < 1e-9) return null;
  return Offset(
    (-l1[2] * l2[1] + l2[2] * l1[1]) / det,
    (-l1[0] * l2[2] + l2[0] * l1[2]) / det,
  );
}

/// A wall the salesperson could plausibly mean: four-sided, convex, covering
/// a fair part of the photo, its corners on or near the photo.
bool _plausible(List<Offset> c) {
  for (final p in c) {
    if (p.dx < -0.1 || p.dx > 1.1 || p.dy < -0.1 || p.dy > 1.1) return false;
  }
  double? sign;
  var area = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (d.dy - b.dy) - (b.dy - a.dy) * (d.dx - b.dx);
    if (cross.abs() < 1e-9) return false;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area.abs() / 2 >= 0.05;
}
