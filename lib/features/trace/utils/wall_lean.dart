import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image_picker/image_picker.dart' show XFile;

import '../../floorplan/plan_geometry.dart' show GrayImage;
import 'homography.dart';

/// Above this, the upright edges on the straightened wall lean enough that a
/// corner is probably off. Right corners give under 1° on test photos; a
/// corner 100 px off gave 2.3–7.5°.
const double kLeanWarnDeg = 1.5;

/// The photo is checked at most this many pixels on the long side.
const int _checkLongSidePx = 800;

class WallLeanInput {
  const WallLeanInput(this.image, this.corners, this.aspect);

  final GrayImage image;

  /// The wall's corners in [image] pixels: top-left, top-right,
  /// bottom-right, bottom-left.
  final List<ui.Offset> corners;

  /// The wall's real width ÷ height.
  final double aspect;
}

/// How far the room's upright edges lean on the straightened wall, in
/// degrees, or null when the photo has too few of them to tell.
///
/// Straightening through the right corners turns every upright line in the
/// room vertical: window and door frames, cabinet sides, even a fridge
/// standing in front of the wall, since they all share one vanishing point.
/// A corner in the wrong place moves that point, and they lean. (Level lines
/// are no use: the ones running into the room are meant to slant.)
double? uprightLean(WallLeanInput input) {
  final src = input.image;
  const outW = 360;
  final outH = (outW / input.aspect).round().clamp(60, 720);
  final toPhoto = Homography.between([
    ui.Offset.zero,
    const ui.Offset(outW * 1.0, 0),
    ui.Offset(outW * 1.0, outH * 1.0),
    ui.Offset(0, outH * 1.0),
  ], input.corners);
  if (toPhoto == null) return null;

  // The straightened wall, sampled from the photo.
  final wall = Float32List(outW * outH);
  final px = src.pixels;
  for (var v = 0; v < outH; v++) {
    for (var u = 0; u < outW; u++) {
      final p = toPhoto.map(ui.Offset(u + 0.5, v + 0.5));
      final x = p.dx.clamp(0.0, src.width - 1.001);
      final y = p.dy.clamp(0.0, src.height - 1.001);
      final x0 = x.floor(), y0 = y.floor();
      final fx = x - x0, fy = y - y0;
      final i = y0 * src.width + x0;
      wall[v * outW + u] = px[i] * (1 - fx) * (1 - fy) +
          px[i + 1] * fx * (1 - fy) +
          px[i + src.width] * (1 - fx) * fy +
          px[i + src.width + 1] * fx * fy;
    }
  }

  // Sobel, away from the frame (the wall's own edges sit there).
  final margin = math.max(2, (0.04 * math.min(outW, outH)).round());
  final gxs = <double>[], gys = <double>[], mags = <double>[];
  for (var v = margin; v < outH - margin; v++) {
    for (var u = margin; u < outW - margin; u++) {
      double at(int du, int dv) => wall[(v + dv) * outW + u + du];
      final gx = (at(1, -1) + 2 * at(1, 0) + at(1, 1)) -
          (at(-1, -1) + 2 * at(-1, 0) + at(-1, 1));
      final gy = (at(-1, 1) + 2 * at(0, 1) + at(1, 1)) -
          (at(-1, -1) + 2 * at(0, -1) + at(1, -1));
      gxs.add(gx);
      gys.add(gy);
      mags.add(math.sqrt(gx * gx + gy * gy));
    }
  }
  if (mags.isEmpty) return null;
  final sorted = [...mags]..sort();
  final threshold =
      math.max(sorted[(sorted.length * 0.97).floor().clamp(0, sorted.length - 1)], 40.0);

  // Upright edges have mostly sideways gradients. How far each leans from
  // vertical, weighted by its strength.
  final devs = <(double, double)>[];
  for (var i = 0; i < mags.length; i++) {
    final m = mags[i];
    if (m < threshold || gxs[i].abs() <= gys[i].abs()) continue;
    final angle = math.atan2(gys[i], gxs[i]) * 180 / math.pi;
    devs.add(((angle + 45) % 90 - 45, m));
  }
  if (devs.length < 30) return null;

  // Weighted median: robust to stray texture.
  devs.sort((a, b) => a.$1.compareTo(b.$1));
  final total = devs.fold(0.0, (s, d) => s + d.$2);
  var acc = 0.0;
  for (final (dev, weight) in devs) {
    acc += weight;
    if (acc >= total / 2) return dev;
  }
  return devs.last.$1;
}

/// Checks a photo's straightened wall for leaning upright edges, in a
/// background isolate. [corners] are fractions of the photo.
typedef LeanCheck = Future<double?> Function(
    String imagePath, List<ui.Offset> corners, double aspect);

/// Reads the photo (a file, or a browser `blob:` URL), scales it down, and
/// runs [uprightLean]. Null if anything about the photo can't be read.
Future<double?> deviceLeanCheck(
    String imagePath, List<ui.Offset> corners, double aspect) async {
  try {
    final bytes = await XFile(imagePath).readAsBytes();
    final probe = await ui.instantiateImageCodec(bytes);
    final first = (await probe.getNextFrame()).image;
    final longSide = math.max(first.width, first.height);
    final shrink =
        longSide > _checkLongSidePx ? _checkLongSidePx / longSide : 1.0;
    final width = (first.width * shrink).round();
    final height = (first.height * shrink).round();
    first.dispose();

    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: width, targetHeight: height);
    final image = (await codec.getNextFrame()).image;
    try {
      final rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (rgba == null) return null;
      final gray =
          GrayImage.fromRgba(rgba.buffer.asUint8List(), image.width, image.height);
      final px = [
        for (final c in corners)
          ui.Offset(c.dx * image.width, c.dy * image.height)
      ];
      return await compute(uprightLean, WallLeanInput(gray, px, aspect));
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}
