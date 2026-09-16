import 'dart:convert';
import '../models/obstacle.dart';
import 'scale_math.dart';

/// Converts the current wall + obstacle state into the lean JSON payload
/// that both the Three.js renderer and the Python backend consume.
class PayloadBuilder {
  const PayloadBuilder._();

  static Map<String, dynamic> build({
    required double wallWidthMm,
    required double wallHeightMm,
    required double wallDepthMm,
    required double scaleRatio, // px per mm fallback
    double? scaleRatioX,
    double? scaleRatioY,
    double leftLinePx = 0.0,
    double? bottomLinePx,
    required List<Obstacle> obstacles,
    required double canvasHeightPx, // used to anchor distance_from_floor
  }) {
    final sRatioX = (scaleRatioX != null && scaleRatioX > 0) ? scaleRatioX : scaleRatio;
    final sRatioY = (scaleRatioY != null && scaleRatioY > 0) ? scaleRatioY : scaleRatio;
    final floorPx = bottomLinePx ?? canvasHeightPx;

    final List<Map<String, dynamic>> obstacleList = obstacles.map((obs) {
      final distFromLeftPx = obs.leftPx - leftLinePx;
      double distFromLeftMm = ScaleMath.pxToMm(distFromLeftPx, sRatioX).roundToDouble();

      final distFromFloorPx = floorPx - (obs.topPx + obs.heightPx);
      double distFromFloorMm = ScaleMath.pxToMm(distFromFloorPx, sRatioY).roundToDouble();

      double widthMm = ScaleMath.pxToMm(obs.widthPx, sRatioX).roundToDouble();
      double heightMm = ScaleMath.pxToMm(obs.heightPx, sRatioY).roundToDouble();

      // ── Dimension calculations ─────────────────────────────────────────────
      if (distFromLeftMm < 0) distFromLeftMm = 0;
      if (distFromFloorMm < 0) distFromFloorMm = 0;

      // Doors ALWAYS connect to the floor (distance_from_floor_mm = 0)
      if (obs.type == ObstacleType.door) {
        distFromFloorMm = 0;
      }

      return {
        'type': obs.type.name, // 'window' | 'door'
        'distance_from_left_mm': distFromLeftMm,
        'distance_from_floor_mm': distFromFloorMm,
        'width_mm': widthMm,
        'height_mm': heightMm,
      };
    }).toList();

    return {
      'wall': {
        'width_mm': wallWidthMm,
        'height_mm': wallHeightMm,
        'depth_mm': wallDepthMm,
      },
      'obstacles': obstacleList,
      'salesperson_id': 'demo_agent_01', // hardcoded per spec
    };
  }

  /// Returns the payload serialised as a JSON string (for WebView bridge).
  static String toJson({
    required double wallWidthMm,
    required double wallHeightMm,
    required double wallDepthMm,
    required double scaleRatio,
    double? scaleRatioX,
    double? scaleRatioY,
    double leftLinePx = 0.0,
    double? bottomLinePx,
    required List<Obstacle> obstacles,
    required double canvasHeightPx,
  }) =>
      jsonEncode(build(
        wallWidthMm: wallWidthMm,
        wallHeightMm: wallHeightMm,
        wallDepthMm: wallDepthMm,
        scaleRatio: scaleRatio,
        scaleRatioX: scaleRatioX,
        scaleRatioY: scaleRatioY,
        leftLinePx: leftLinePx,
        bottomLinePx: bottomLinePx,
        obstacles: obstacles,
        canvasHeightPx: canvasHeightPx,
      ));
}
