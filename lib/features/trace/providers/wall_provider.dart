import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/obstacle.dart';
import '../utils/corner_suggester.dart';
import '../utils/corner_suggestion.dart';
import '../utils/homography.dart';

// ─── Wall Setup ─────────────────────────────────────────────────────────────

/// The four corners of the wall in front of the camera, marked on the photo.
enum WallCorner {
  topLeft('Top left'),
  topRight('Top right'),
  bottomRight('Bottom right'),
  bottomLeft('Bottom left');

  const WallCorner(this.label);
  final String label;

  bool get isLeft => this == topLeft || this == bottomLeft;
  bool get isTop => this == topLeft || this == topRight;
}

/// Corners stay at least this far apart (as a fraction of the photo).
const double kMinEdgeGap = 0.05;

/// Where the corners start: a little inside the photo, since walls rarely
/// fill the frame and a dot on the very edge is hard to grab.
const List<Offset> kStartCorners = [
  Offset(0.08, 0.08),
  Offset(0.92, 0.08),
  Offset(0.92, 0.92),
  Offset(0.08, 0.92),
];

/// How the phone was held when the photo was taken, in degrees.
class CaptureTilt {
  const CaptureTilt({required this.rollDeg, required this.pitchDeg});

  /// Turned clockwise (+) or anticlockwise (−) from level.
  final double rollDeg;

  /// The camera looking down (+) or up (−), from upright.
  final double pitchDeg;

  Map<String, double> toJson() => {
        'roll': double.parse(rollDeg.toStringAsFixed(1)),
        'pitch': double.parse(pitchDeg.toStringAsFixed(1)),
      };
}

class WallSetup {
  const WallSetup({
    this.widthMm = 4000,
    this.heightMm = 2700,
    this.depthMm = 150,
    this.screenWidthPx = 1,
    this.screenHeightPx = 1,
    this.leftLineRatio = 0.08,
    this.rightLineRatio = 0.92,
    this.topLineRatio = 0.08,
    this.bottomLineRatio = 0.92,
    this.corners = kStartCorners,
    this.photoSize,
    this.focalPx,
    this.tilt,
    this.suggestedCorners,
  });

  final double widthMm;
  final double heightMm;
  final double depthMm;

  /// The trace canvas, set when its LayoutBuilder resolves.
  final double screenWidthPx;
  final double screenHeightPx;

  /// Where the straightened wall sits on the canvas while windows and doors
  /// are marked (fractions of the canvas). Boxes are measured against it.
  final double leftLineRatio;
  final double rightLineRatio;
  final double topLineRatio;
  final double bottomLineRatio;

  /// The wall's corners on the photo, as fractions of its width and height,
  /// in [WallCorner] order.
  final List<Offset> corners;

  /// The photo's size in pixels (upright), once it has been decoded.
  final Size? photoSize;

  /// The camera's focal length in photo pixels, from the photo's EXIF data.
  final double? focalPx;

  /// How the phone was held, if the photo came from the camera screen.
  final CaptureTilt? tilt;

  /// Where the wall-corner model put the corners (fractions of the photo),
  /// if it found them: kept with the quote beside the corners confirmed, so
  /// the model can be measured and improved.
  final List<Offset>? suggestedCorners;

  double get leftLinePx => screenWidthPx * leftLineRatio;
  double get rightLinePx => screenWidthPx * rightLineRatio;
  double get topLinePx => screenHeightPx * topLineRatio;
  double get bottomLinePx => screenHeightPx * bottomLineRatio;

  double get activeWallWidthPx => (rightLinePx - leftLinePx)
      // Before the first layout the screen size is a 1px placeholder;
      // clamp(50, 1) would throw.
      .clamp(math.min(50, screenWidthPx), screenWidthPx);
  double get activeWallHeightPx => (bottomLinePx - topLinePx)
      .clamp(math.min(50, screenHeightPx), screenHeightPx);

  /// Pixels per mm on the straightened wall. The same both ways once the
  /// layout has settled, since the wall is drawn at its true proportions.
  double get scaleRatioX => activeWallWidthPx / widthMm;
  double get scaleRatioY => activeWallHeightPx / heightMm;
  double get scaleRatio => scaleRatioX;

  double get canvasHeightPx => activeWallHeightPx;

  Offset corner(WallCorner c) => corners[c.index];

  /// The corners in photo pixels, once the photo's size is known.
  List<Offset>? get cornersPx {
    final size = photoSize;
    if (size == null) return null;
    return [for (final c in corners) Offset(c.dx * size.width, c.dy * size.height)];
  }

  /// The wall's proportions as the photo shows them, or null if the photo
  /// isn't decoded yet or the corners make no sense.
  WallShapeEstimate? get photoShape {
    final px = cornersPx;
    if (px == null) return null;
    return estimateWallShape(px, photoSize!, focalPx: focalPx);
  }

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
    List<Offset>? corners,
    Size? photoSize,
    double? focalPx,
    CaptureTilt? tilt,
    List<Offset>? suggestedCorners,
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
        corners: corners ?? this.corners,
        photoSize: photoSize ?? this.photoSize,
        focalPx: focalPx ?? this.focalPx,
        tilt: tilt ?? this.tilt,
        suggestedCorners: suggestedCorners ?? this.suggestedCorners,
      );
}

/// Where the straightened wall is drawn on a canvas: as large as fits, at
/// its true proportions, centred, with a margin for the boxes' handles.
Rect straightWallRect(Size canvas, double widthMm, double heightMm) {
  const margin = 16.0;
  final room = Size(math.max(1, canvas.width - 2 * margin),
      math.max(1, canvas.height - 2 * margin));
  final aspect = widthMm / heightMm;
  final w = math.min(room.width, room.height * aspect);
  final h = w / aspect;
  return Rect.fromCenter(
      center: Offset(canvas.width / 2, canvas.height / 2), width: w, height: h);
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

  /// A new photo: corners back to their start, and how the phone was held
  /// (null for a photo from the gallery).
  void startPhoto({CaptureTilt? tilt}) => state = WallSetup(
        widthMm: state.widthMm,
        heightMm: state.heightMm,
        depthMm: state.depthMm,
        screenWidthPx: state.screenWidthPx,
        screenHeightPx: state.screenHeightPx,
        tilt: tilt,
      );

  /// The photo has been decoded: its upright size in pixels, and the
  /// camera's focal length if its EXIF data has one.
  void setPhoto(Size size, {double? focalPx}) {
    if (state.photoSize == size && state.focalPx == focalPx) return;
    state = state.copyWith(photoSize: size, focalPx: focalPx);
  }

  /// Called after every layout of the trace canvas: the canvas size and the
  /// straightened wall's place on it. Only a real change may notify, or the
  /// screen would rebuild itself every frame.
  void syncLayout(Size canvas) {
    final r = straightWallRect(canvas, state.widthMm, state.heightMm);
    final next = state.copyWith(
      screenWidthPx: canvas.width,
      screenHeightPx: canvas.height,
      leftLineRatio: r.left / canvas.width,
      rightLineRatio: r.right / canvas.width,
      topLineRatio: r.top / canvas.height,
      bottomLineRatio: r.bottom / canvas.height,
    );
    bool same(double a, double b) => (a - b).abs() < 1e-9;
    if (same(next.screenWidthPx, state.screenWidthPx) &&
        same(next.screenHeightPx, state.screenHeightPx) &&
        same(next.leftLineRatio, state.leftLineRatio) &&
        same(next.rightLineRatio, state.rightLineRatio) &&
        same(next.topLineRatio, state.topLineRatio) &&
        same(next.bottomLineRatio, state.bottomLineRatio)) {
      return;
    }
    state = next;
  }

  /// The model's corners for this photo. Placed on the photo only if
  /// [place] and they make a proper four-sided wall; kept for the record
  /// either way. Returns whether they were placed.
  bool suggest(List<Offset> corners, {required bool place}) {
    final c = [
      for (final p in corners) Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0))
    ];
    final ok = c.length == 4 && isConvexQuad(c);
    state = state.copyWith(
      suggestedCorners: c,
      corners: place && ok ? c : null,
    );
    return place && ok;
  }

  /// Moves [corner] to [at] (fractions of the photo): kept on the photo, on
  /// its own side of the wall, and the wall kept a proper four-sided shape.
  /// Used by dragging, tapping the photo and the arrows.
  void moveCorner(WallCorner corner, Offset at) {
    final c = [...state.corners];
    const g = kMinEdgeGap;
    final tl = c[0], tr = c[1], br = c[2], bl = c[3];
    var x = at.dx.clamp(0.0, 1.0);
    var y = at.dy.clamp(0.0, 1.0);
    switch (corner) {
      case WallCorner.topLeft:
        x = math.min(x, tr.dx - g);
        y = math.min(y, bl.dy - g);
      case WallCorner.topRight:
        x = math.max(x, tl.dx + g);
        y = math.min(y, br.dy - g);
      case WallCorner.bottomRight:
        x = math.max(x, bl.dx + g);
        y = math.max(y, tr.dy + g);
      case WallCorner.bottomLeft:
        x = math.min(x, br.dx - g);
        y = math.max(y, tl.dy + g);
    }
    c[corner.index] = Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
    if (!isConvexQuad(c)) return;
    state = state.copyWith(corners: c);
  }
}

/// Whether four points, in order, make a convex four-sided shape.
bool isConvexQuad(List<Offset> p) {
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = p[i], b = p[(i + 1) % 4], c = p[(i + 2) % 4];
    final cross = (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
    if (cross.abs() < 1e-9) return false;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
}

/// The wall-corner model on this device.
final cornerSuggesterProvider =
    Provider<CornerSuggester>((ref) => const DeviceCornerSuggester());

/// The model's corners for a photo, looked for once per photo: started as
/// soon as the photo is chosen (on the wall-size screen), so they're usually
/// ready by the time the corners are marked.
final cornerSuggestionProvider =
    FutureProvider.family<CornerSuggestion, String>(
        (ref, imagePath) => ref.watch(cornerSuggesterProvider).suggest(imagePath));

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
