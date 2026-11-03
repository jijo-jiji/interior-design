import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/obstacle.dart';

// ─── Wall Setup ─────────────────────────────────────────────────────────────

class WallSetup {
  const WallSetup({
    this.widthMm = 4000,
    this.heightMm = 2700,
    this.depthMm = 150,
    this.screenWidthPx = 1,
    this.screenHeightPx = 1,
    this.leftLineRatio = 0.0,
    this.rightLineRatio = 1.0,
    this.topLineRatio = 0.0,
    this.bottomLineRatio = 1.0,
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

  void updateScreenSize(double widthPx, double heightPx) =>
      state = state.copyWith(
        screenWidthPx: widthPx,
        screenHeightPx: heightPx,
      );

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
