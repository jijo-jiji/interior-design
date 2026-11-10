import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import '../models/obstacle.dart';
import 'homography.dart';

/// The segmentation model's labels for a photo: one ADE20K class id per
/// cell, [width] × [height], covering the whole photo (cell (x, y) is the
/// photo at fractions ((x + 0.5) / width, (y + 0.5) / height)).
class WallLabels {
  WallLabels(this.width, this.height, this.ids)
      : assert(ids.length == width * height);

  final int width, height;
  final Uint8List ids;

  // The ADE20K classes the app uses (of the model's 32).
  static const int wall = 1, floor = 4, ceiling = 6, window = 9;
  static const int cabinet = 11, door = 15, curtain = 19;
}

/// A window or door found on the wall, in millimetres from the wall's
/// top-left corner.
class FoundOpening {
  const FoundOpening(this.type, this.rectMm);
  final ObstacleType type;
  final Rect rectMm;
}

/// Openings smaller than this either way are noise, not a window or door.
const double kMinOpeningMm = 250;

/// Windows and doors on the wall the corners mark, from the segmentation
/// labels: each window (or curtain, which hangs over one) and door region is
/// mapped onto the straightened wall, and its extent taken as a box. Regions
/// mostly off the wall (a door in a side wall) are left out.
///
/// [corners] are fractions of the photo (top-left, top-right, bottom-right,
/// bottom-left); the wall is [wallWidthMm] × [wallHeightMm].
List<FoundOpening> findOpenings(WallLabels labels, List<Offset> corners,
    double wallWidthMm, double wallHeightMm) {
  final toWall = Homography.between(corners, [
    Offset.zero,
    Offset(wallWidthMm, 0),
    Offset(wallWidthMm, wallHeightMm),
    Offset(0, wallHeightMm),
  ]);
  if (toWall == null) return const [];
  final w = labels.width, h = labels.height;
  final minCells = math.max(4, (0.002 * w * h).round());
  final found = <FoundOpening>[];

  for (final (type, ids) in [
    (ObstacleType.window, const {WallLabels.window, WallLabels.curtain}),
    (ObstacleType.door, const {WallLabels.door}),
  ]) {
    final seen = Uint8List(w * h);
    for (var start = 0; start < w * h; start++) {
      if (seen[start] == 1 || !ids.contains(labels.ids[start])) continue;
      // One connected region (4 neighbours).
      final region = <int>[];
      final queue = <int>[start];
      seen[start] = 1;
      while (queue.isNotEmpty) {
        final i = queue.removeLast();
        region.add(i);
        final x = i % w, y = i ~/ w;
        for (final j in [
          if (x > 0) i - 1,
          if (x < w - 1) i + 1,
          if (y > 0) i - w,
          if (y < h - 1) i + w,
        ]) {
          if (seen[j] == 0 && ids.contains(labels.ids[j])) {
            seen[j] = 1;
            queue.add(j);
          }
        }
      }
      if (region.length < minCells) continue;

      // On the straightened wall.
      final xs = <double>[], ys = <double>[];
      var inside = 0;
      const slack = 50.0; // mm: the region's edge may spill past a corner
      for (final i in region) {
        final p = toWall.map(Offset((i % w + 0.5) / w, (i ~/ w + 0.5) / h));
        if (p.dx < -slack ||
            p.dx > wallWidthMm + slack ||
            p.dy < -slack ||
            p.dy > wallHeightMm + slack) {
          continue;
        }
        inside++;
        xs.add(p.dx);
        ys.add(p.dy);
      }
      if (inside < 0.8 * region.length) continue; // on another wall
      xs.sort();
      ys.sort();
      double at(List<double> v, double q) =>
          v[(q * (v.length - 1)).round().clamp(0, v.length - 1)];
      // The region's cells are centres: widen by half a cell's size there.
      final cellW = wallWidthMm / w * _scaleAcross(corners);
      final cellH = wallHeightMm / h * _scaleDown(corners);
      final left = (at(xs, 0.02) - cellW / 2).clamp(0.0, wallWidthMm);
      final right = (at(xs, 0.98) + cellW / 2).clamp(0.0, wallWidthMm);
      final top = (at(ys, 0.02) - cellH / 2).clamp(0.0, wallHeightMm);
      var bottom = (at(ys, 0.98) + cellH / 2).clamp(0.0, wallHeightMm);
      if (type == ObstacleType.door && wallHeightMm - bottom < 150) {
        bottom = wallHeightMm; // doors stand on the floor
      }
      if (right - left < kMinOpeningMm || bottom - top < kMinOpeningMm) {
        continue;
      }
      found.add(FoundOpening(type, Rect.fromLTRB(left, top, right, bottom)));
    }
  }
  found.sort((a, b) => a.rectMm.left.compareTo(b.rectMm.left));
  return found;
}

/// How many photo-widths the wall spans across, roughly: 1 / the wall's
/// share of the photo's width (to size one label cell on the wall).
double _scaleAcross(List<Offset> c) {
  final span = ((c[1].dx - c[0].dx) + (c[2].dx - c[3].dx)) / 2;
  return span > 0.05 ? 1 / span : 1;
}

double _scaleDown(List<Offset> c) {
  final span = ((c[3].dy - c[0].dy) + (c[2].dy - c[1].dy)) / 2;
  return span > 0.05 ? 1 / span : 1;
}
