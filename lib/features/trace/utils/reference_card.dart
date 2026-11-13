import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'homography.dart';

/// An A4 sheet taped flat on the wall: something of exactly known size in
/// the photo, so the wall's size is measured, not guessed from a worktop or
/// a door. The traced corners give the wall's proportions; the sheet, its
/// scale. It works whichever way the sheet is turned.
const double kSheetShortMm = 210, kSheetLongMm = 297;

/// How far the sheet's proportions on the straightened wall may be from
/// A4's before the screen says a corner looks off (the sheet's or the
/// wall's).
const double kSheetShapeTolerance = 0.08;

/// The sheet's shortest side, as a share of the photo's diagonal, below
/// which it's too small on the photo to measure from well: a dot a few
/// pixels off is then a few per cent of the sheet.
const double kSheetMinShare = 0.03;

/// The wall's size measured from the sheet.
class SheetMeasure {
  const SheetMeasure({
    required this.widthMm,
    required this.heightMm,
    required this.shapeOff,
    required this.share,
    required this.onWall,
  });

  /// The wall's width and height.
  final double widthMm, heightMm;

  /// The sheet's long side over its short side on the straightened wall,
  /// against A4's: 0 for a perfect match, 0.1 for 10% longer.
  final double shapeOff;

  /// The sheet's shortest side on the photo, over the photo's diagonal.
  final double share;

  /// Whether all of the sheet is on the traced wall.
  final bool onWall;

  bool get shapeLooksOff => shapeOff.abs() > kSheetShapeTolerance;
  bool get small => share < kSheetMinShare;
}

/// The wall's size from an A4 sheet on it.
///
/// [sheet]: the sheet's corners and [wallCorners] the wall's, both as
/// fractions of a [photo] of that size, in order round the shape
/// (top-left, top-right, bottom-right, bottom-left). [aspect]: the wall's
/// width over its height, from its corners. Null if either shape makes no
/// sense.
///
/// The sheet is mapped onto the straightened wall, where its sides, in
/// units of the wall's height, are known to be 210 and 297 mm: the wall's
/// height is what fits all four sides best.
SheetMeasure? measureSheet({
  required List<Offset> sheet,
  required List<Offset> wallCorners,
  required double aspect,
  required Size photo,
}) {
  if (sheet.length != 4 || wallCorners.length != 4 || aspect <= 0) return null;
  const unit = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
  final toWall = Homography.between(wallCorners, unit);
  if (toWall == null) return null;
  final q = [for (final p in sheet) toWall.map(p)];
  // On the wall, in units of its height.
  final p = [for (final w in q) Offset(w.dx * aspect, w.dy)];
  final sides = [
    for (var i = 0; i < 4; i++) (p[(i + 1) % 4] - p[i]).distance,
  ];
  if (sides.any((s) => !s.isFinite || s <= 0)) return null;

  // Top and bottom, against right and left: the longer pair is the 297.
  final across = (sides[0] + sides[2]) / 2, down = (sides[1] + sides[3]) / 2;
  final acrossMm = across >= down ? kSheetLongMm : kSheetShortMm;
  final downMm = across >= down ? kSheetShortMm : kSheetLongMm;
  final mm = [acrossMm, downMm, acrossMm, downMm];
  var num = 0.0, den = 0.0;
  for (var i = 0; i < 4; i++) {
    num += sides[i] * mm[i];
    den += sides[i] * sides[i];
  }
  final height = num / den;
  if (!height.isFinite || height <= 0) return null;

  final long = math.max(across, down), short = math.min(across, down);
  final shapeOff = (long / short) / (kSheetLongMm / kSheetShortMm) - 1;

  final px = [
    for (final s in sheet) Offset(s.dx * photo.width, s.dy * photo.height)
  ];
  var shortest = double.infinity;
  for (var i = 0; i < 4; i++) {
    shortest = math.min(shortest, (px[(i + 1) % 4] - px[i]).distance);
  }
  final diagonal =
      math.sqrt(photo.width * photo.width + photo.height * photo.height);

  const slack = 0.02;
  final onWall = q.every((w) =>
      w.dx >= -slack && w.dx <= 1 + slack && w.dy >= -slack && w.dy <= 1 + slack);

  return SheetMeasure(
    widthMm: height * aspect,
    heightMm: height,
    shapeOff: shapeOff,
    share: shortest / diagonal,
    onWall: onWall,
  );
}

/// Where the sheet's dots start: an upright A4 sheet in the middle of the
/// wall, a little above halfway, drawn in the photo's perspective at the
/// size the wall is thought to be ([heightMm]). Fractions of the photo.
List<Offset> startSheet({
  required List<Offset> wallCorners,
  required double aspect,
  required double heightMm,
}) {
  const unit = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
  final toPhoto = Homography.between(unit, wallCorners);
  final du = kSheetShortMm / (heightMm * aspect), dv = kSheetLongMm / heightMm;
  const cu = 0.5, cv = 0.45;
  final onWall = [
    Offset(cu - du / 2, cv - dv / 2),
    Offset(cu + du / 2, cv - dv / 2),
    Offset(cu + du / 2, cv + dv / 2),
    Offset(cu - du / 2, cv + dv / 2),
  ];
  if (toPhoto == null) return onWall;
  Offset onPhoto(Offset w) {
    final p = toPhoto.map(w);
    return Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));
  }

  return [for (final w in onWall) onPhoto(w)];
}
