import 'dart:math' as math;

/// All pixel↔mm conversion helpers.
/// [ratio] = screenWidthPx / wallWidthMm
/// i.e. how many pixels represent 1 mm.
class ScaleMath {
  const ScaleMath._();

  /// Convert a pixel measurement to millimetres.
  static double pxToMm(double px, double ratio) {
    assert(ratio > 0, 'Scale ratio must be positive');
    return px / ratio;
  }

  /// Convert a millimetre measurement to pixels.
  static double mmToPx(double mm, double ratio) {
    assert(ratio > 0, 'Scale ratio must be positive');
    return mm * ratio;
  }

  /// Compute the scale ratio from screen width and real wall width.
  /// Returns pixels-per-mm.
  static double computeRatio({
    required double screenWidthPx,
    required double wallWidthMm,
  }) {
    assert(wallWidthMm > 0, 'Wall width must be positive');
    return screenWidthPx / wallWidthMm;
  }

  /// Snap a pixel value to the nearest [gridMm] grid in mm-space.
  static double snapToGrid(double px, double ratio, {double gridMm = 50}) {
    final mm = pxToMm(px, ratio);
    final snapped = (mm / gridMm).round() * gridMm;
    return mmToPx(snapped.toDouble(), ratio);
  }

  /// Clamp an obstacle box so it never leaves the canvas.
  static double clampLeft(double left, double boxWidth, double canvasWidth) =>
      math.max(0, math.min(left, canvasWidth - boxWidth));

  static double clampTop(double top, double boxHeight, double canvasHeight) =>
      math.max(0, math.min(top, canvasHeight - boxHeight));
}
