import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/obstacle.dart';

// ─── Wall Setup ─────────────────────────────────────────────────────────────

/// The four lines the salesperson lines up with the wall in the photo.
enum WallEdge {
  ceiling('Ceiling', 'Ceiling'),
  floor('Floor', 'Floor'),
  left('Left wall', 'Left'),
  right('Right wall', 'Right');

  const WallEdge(this.label, this.shortLabel);
  final String label;

  /// For the edge picker, where four have to fit on one line.
  final String shortLabel;

  /// Left and right are vertical lines that move sideways.
  bool get isVertical => this == left || this == right;
}

/// Edges stay at least this far apart (as a fraction of the photo).
const double kMinEdgeGap = 0.05;

class WallSetup {
  const WallSetup({
    this.widthMm = 4000,
    this.heightMm = 2700,
    this.depthMm = 150,
    this.screenWidthPx = 1,
    this.screenHeightPx = 1,
    // Start a little inside the photo: walls rarely fill the frame, and a
    // line on the very edge would be half off-screen and hard to grab.
    this.leftLineRatio = 0.08,
    this.rightLineRatio = 0.92,
    this.topLineRatio = 0.08,
    this.bottomLineRatio = 0.92,
  });

  final double widthMm;
  final double heightMm;
  final double depthMm;

  /// Set by the TraceCanvas when LayoutBuilder resolves.
  final double screenWidthPx;
  final double screenHeightPx;

  /// 4-Boundary wall calibration ratios (0.0 to 1.0)
  final double leftLineRatio;
  final double rightLineRatio;
  final double topLineRatio;
  final double bottomLineRatio;

  /// Pixel positions of wall boundaries on screen
  double get leftLinePx => screenWidthPx * leftLineRatio;
  double get rightLinePx => screenWidthPx * rightLineRatio;
  double get topLinePx => screenHeightPx * topLineRatio;
  double get bottomLinePx => screenHeightPx * bottomLineRatio;

  /// Active calibrated wall pixel dimensions inside the cropped boundary box
  double get activeWallWidthPx => (rightLinePx - leftLinePx)
      // Before the first layout the screen size is a 1px placeholder;
      // clamp(50, 1) would throw.
      .clamp(math.min(50, screenWidthPx), screenWidthPx);
  double get activeWallHeightPx => (bottomLinePx - topLinePx)
      .clamp(math.min(50, screenHeightPx), screenHeightPx);

  /// Calibrated scale ratios (pixels-per-mm)
  double get scaleRatioX => activeWallWidthPx / widthMm;
  double get scaleRatioY => activeWallHeightPx / heightMm;

  /// Primary scale ratio for backwards compatibility
  double get scaleRatio => scaleRatioX;

  /// Where [edge] sits, as a fraction of the photo's width or height.
  double ratioOf(WallEdge edge) => switch (edge) {
        WallEdge.ceiling => topLineRatio,
        WallEdge.floor => bottomLineRatio,
        WallEdge.left => leftLineRatio,
        WallEdge.right => rightLineRatio,
      };

  /// Canvas height in px derived from the wall aspect ratio.
  double get canvasHeightPx => activeWallHeightPx;

  WallSetup copyWith({
    double? widthMm,
    double? heightMm,
    double? depthMm,
    double? screenWidthPx,
    double? screenHeightPx,
    double? leftLineRatio,
    double? rightLineRatio,
    double? topLineRatio,
    double? bottomLineRatio,
  }) =>
      WallSetup(
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
        depthMm: depthMm ?? this.depthMm,
        screenWidthPx: screenWidthPx ?? this.screenWidthPx,
        screenHeightPx: screenHeightPx ?? this.screenHeightPx,
        leftLineRatio: leftLineRatio ?? this.leftLineRatio,
        rightLineRatio: rightLineRatio ?? this.rightLineRatio,
        topLineRatio: topLineRatio ?? this.topLineRatio,
        bottomLineRatio: bottomLineRatio ?? this.bottomLineRatio,
      );
}

class WallSetupNotifier extends StateNotifier<WallSetup> {
  WallSetupNotifier() : super(const WallSetup());

  void updateDimensions({
    required double widthMm,
    required double heightMm,
    required double depthMm,
  }) =>
      state = state.copyWith(
        widthMm: widthMm,
        heightMm: heightMm,
        depthMm: depthMm,
      );

  void updateScreenSize(double widthPx, double heightPx) {
    // Called after every layout of the trace canvas; only a real change may
    // notify, or the screen would rebuild itself every frame.
    if (state.screenWidthPx == widthPx && state.screenHeightPx == heightPx) {
      return;
    }
    state = state.copyWith(screenWidthPx: widthPx, screenHeightPx: heightPx);
  }

  void updateBoundaries({
    double? leftRatio,
    double? rightRatio,
    double? topRatio,
    double? bottomRatio,
  }) =>
      state = state.copyWith(
        leftLineRatio: leftRatio,
        rightLineRatio: rightRatio,
        topLineRatio: topRatio,
        bottomLineRatio: bottomRatio,
      );

  /// Moves [edge] to [ratio], kept on the photo and [kMinEdgeGap] away from
  /// the opposite edge. Used by dragging, tapping the photo and the arrows.
  void moveEdge(WallEdge edge, double ratio) {
    final s = state;
    switch (edge) {
      case WallEdge.ceiling:
        updateBoundaries(
            topRatio: ratio.clamp(0.0, s.bottomLineRatio - kMinEdgeGap));
      case WallEdge.floor:
        updateBoundaries(
            bottomRatio: ratio.clamp(s.topLineRatio + kMinEdgeGap, 1.0));
      case WallEdge.left:
        updateBoundaries(
            leftRatio: ratio.clamp(0.0, s.rightLineRatio - kMinEdgeGap));
      case WallEdge.right:
        updateBoundaries(
            rightRatio: ratio.clamp(s.leftLineRatio + kMinEdgeGap, 1.0));
    }
  }
}

final wallSetupProvider =
    StateNotifierProvider<WallSetupNotifier, WallSetup>((ref) {
  return WallSetupNotifier();
});

// ─── Obstacles ───────────────────────────────────────────────────────────────

class ObstaclesNotifier extends StateNotifier<List<Obstacle>> {
  ObstaclesNotifier() : super([]);

  void add(Obstacle obs) => state = [...state, obs];

  void update(Obstacle updated) {
    state = [
      for (final obs in state)
        if (obs.id == updated.id) updated else obs,
    ];
  }

  void remove(String id) => state = state.where((obs) => obs.id != id).toList();

  void clear() => state = [];
}

final obstaclesProvider =
    StateNotifierProvider<ObstaclesNotifier, List<Obstacle>>((ref) {
  return ObstaclesNotifier();
});
