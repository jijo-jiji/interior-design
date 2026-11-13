import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/obstacle.dart';
import '../providers/wall_provider.dart';
import '../utils/corner_suggestion.dart';
import '../utils/homography.dart';
import '../utils/opening_finder.dart';
import '../utils/payload_builder.dart';
import '../utils/photo_exif.dart';
import '../utils/wall_lean.dart';
import '../utils/scale_math.dart';
import '../widgets/obstacle_editor.dart';
import '../widgets/trace_box.dart';
import '../../../shared/platform/photo_error.dart';
import '../../../shared/platform/photo_image.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets/nudge_buttons.dart';

/// Each arrow tap moves a corner this much of the photo (about 4 px on a
/// 1080p photo).
const double kCornerNudge = 0.002;

/// The bottom panel keeps one height in both steps, so the photo (and every
/// line and box measured against it) doesn't shift when the step changes.
/// It grows with the text size, up to [_maxPanelShare] of the screen.
const double _panelHeight = 232;
const double _maxPanelShare = 0.45;

/// Where a photo of [photo]'s size is drawn on [canvas]: contained and
/// centred. The whole canvas while the photo's size isn't known yet.
Rect photoRectIn(Size canvas, Size? photo) {
  if (photo == null || photo.isEmpty) return Offset.zero & canvas;
  final fitted = applyBoxFit(BoxFit.contain, photo, canvas).destination;
  return Alignment.center.inscribe(fitted, Offset.zero & canvas);
}

/// A 2D perspective mapping as a [Matrix4], for [Transform].
Matrix4 matrixOf(Homography h) {
  final m = h.m;
  // Column-major: x, y, z, w columns.
  return Matrix4(
    m[0], m[3], 0, m[6], //
    m[1], m[4], 0, m[7], //
    0, 0, 1, 0, //
    m[2], m[5], 0, m[8],
  );
}

/// The wall photo, traced first and measured after:
///  1. the four corners of the wall in front of the camera, found by the
///     corner model where it can, checked or placed by hand (drag a dot,
///     tap the photo, or use the arrows);
///  2. the wall's size, on its own screen ([WallSetupScreen]), filled in
///     from the traced corners and checked with a tape;
///  3. on that wall, straightened to its true shape, the windows and doors
///     (drag a box, or type its exact size).
///
/// The corners fix the perspective exactly, so a photo taken at an angle,
/// with the side walls and ceiling in it, still measures true.
class TraceScreen extends ConsumerStatefulWidget {
  final String imagePath;

  /// Checks the straightened wall for leaning upright edges (a corner off).
  final LeanCheck leanCheck;

  const TraceScreen({
    super.key,
    required this.imagePath,
    this.leanCheck = deviceLeanCheck,
  });

  @override
  ConsumerState<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends ConsumerState<TraceScreen> {
  bool _markingObstacles = false;
  WallCorner _corner = WallCorner.topLeft;

  /// How far upright edges lean on the straightened wall: checked each time
  /// step 2 opens; null until known, or if the photo can't tell.
  double? _leanDeg;
  int _leanRun = 0;

  /// Windows and doors found on the photo: placed once per photo, when
  /// step 3 first opens. Null until known (or with no model here).
  bool _openingsPlaced = false;
  bool _lookingForOpenings = false;
  List<FoundOpening>? _openingsFound;

  /// What the wall-corner model did for this photo, for the panel.
  _Suggest _suggest = _Suggest.none;

  /// While a corner is dragged: where it is on the canvas, for the loupe.
  Offset? _dragAt;

  late final ImageProvider _photo = photoProvider(widget.imagePath);
  ImageStream? _stream;
  late final ImageStreamListener _listener =
      ImageStreamListener(_onDecoded, onError: (_, __) {});
  Size? _decoded;
  double? _focal35mm;

  @override
  void initState() {
    super.initState();
    _stream = _photo.resolve(ImageConfiguration.empty)..addListener(_listener);
    readFocal35mm(widget.imagePath).then((f) {
      _focal35mm = f;
      _publishPhoto();
    });
    // Start labelling the photo now, so windows and doors are ready by step 3.
    ref.read(wallLabelsProvider(widget.imagePath));
    ref.listenManual<WallSetup>(wallSetupProvider, (prev, next) {
      if (prev == null) return;
      final from = prev.wallRect, to = next.wallRect;
      if (from != to) ref.read(obstaclesProvider.notifier).remap(from, to);
    });
    // The model's corners, looked for as soon as the photo opens; placed if
    // the salesperson hasn't started marking.
    ref.listenManual<AsyncValue<CornerSuggestion>>(
      cornerSuggestionProvider(widget.imagePath),
      (_, next) => next.when(
        data: (s) => scheduleMicrotask(() => _onSuggestion(s)),
        loading: () => _suggest = _Suggest.looking,
        error: (_, __) => scheduleMicrotask(
            () => _onSuggestion(const CornerSuggestion(null))),
      ),
      fireImmediately: true,
    );
  }

  void _onSuggestion(CornerSuggestion s) {
    if (!mounted) return;
    final corners = s.corners;
    final _Suggest status;
    if (!s.available) {
      status = _Suggest.none;
    } else if (corners == null) {
      status = _Suggest.notFound;
    } else {
      final untouched = !_markingObstacles &&
          listEquals(ref.read(wallSetupProvider).corners, kStartCorners);
      final placed = ref
          .read(wallSetupProvider.notifier)
          .suggest(corners,
              place: untouched, source: s.source, wallBottom: s.wallBottom);
      status = placed ? _Suggest.placed : _Suggest.offered;
    }
    setState(() => _suggest = status);
  }

  void _useSuggestion() {
    if (ref.read(wallSetupProvider.notifier).useSuggestion()) {
      setState(() => _suggest = _Suggest.placed);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _onDecoded(ImageInfo info, bool _) {
    _decoded = Size(info.image.width.toDouble(), info.image.height.toDouble());
    info.dispose();
    _publishPhoto();
  }

  /// The photo's upright size (the decoder applies the EXIF rotation) and
  /// lens. Deferred: a cached photo reports during initState, while the
  /// tree is building.
  void _publishPhoto() {
    final size = _decoded;
    if (size == null) return;
    final focal = _focal35mm;
    scheduleMicrotask(() {
      if (!mounted) return;
      ref.read(wallSetupProvider.notifier).setPhoto(
            size,
            focalPx: focal == null ? null : focalPxFrom35mm(focal, size),
          );
    });
  }

  /// Checks the corners against the photo itself, in the background. Only
  /// the latest check counts, if the corners changed in the meantime.
  void _checkLean() {
    final wall = ref.read(wallSetupProvider);
    final run = ++_leanRun;
    setState(() => _leanDeg = null);
    widget
        .leanCheck(widget.imagePath, wall.wallCorners, wall.widthMm / wall.heightMm)
        .then((lean) {
      if (mounted && run == _leanRun) setState(() => _leanDeg = lean);
    });
  }

  /// Step 2: the wall's size, filled in from the traced corners for the
  /// salesperson to check with a tape. Then windows and doors.
  Future<void> _toWallSize() async {
    final ok = await context.push<bool>('/wall-setup', extra: widget.imagePath);
    if (ok != true || !mounted) return;
    setState(() => _markingObstacles = true);
    _checkLean();
    _placeOpenings();
  }

  /// Puts the windows and doors the model sees on the wall, as boxes to
  /// check: once per photo, and only if none have been added by hand.
  Future<void> _placeOpenings() async {
    if (_openingsPlaced) return;
    _openingsPlaced = true;
    setState(() => _lookingForOpenings = true);
    WallLabels? labels;
    try {
      labels = await ref.read(wallLabelsProvider(widget.imagePath).future);
    } catch (_) {
      labels = null;
    }
    if (!mounted) return;
    final wall = ref.read(wallSetupProvider);
    final boxes = ref.read(obstaclesProvider.notifier);
    if (labels == null || ref.read(obstaclesProvider).isNotEmpty) {
      setState(() => _lookingForOpenings = false);
      return;
    }
    final found =
        findOpenings(labels, wall.wallCorners, wall.widthMm, wall.heightMm);
    for (final o in found) {
      final r = o.rectMm;
      boxes.add(Obstacle(
        type: o.type,
        leftPx: wall.leftLinePx + r.left * wall.scaleRatioX,
        topPx: wall.topLinePx + r.top * wall.scaleRatioY,
        widthPx: math.max(kMinObstaclePx, r.width * wall.scaleRatioX),
        heightPx: math.max(kMinObstaclePx, r.height * wall.scaleRatioY),
      ));
    }
    setState(() {
      _lookingForOpenings = false;
      _openingsFound = found;
    });
  }

  void _selectCorner(WallCorner corner) {
    if (_corner == corner) return;
    HapticFeedback.selectionClick();
    setState(() => _corner = corner);
  }

  void _nudgeCorner(int dx, int dy) {
    final at = ref.read(wallSetupProvider).corner(_corner);
    ref.read(wallSetupProvider.notifier).moveCorner(
        _corner, at + Offset(dx * kCornerNudge, dy * kCornerNudge));
  }

  @override
  Widget build(BuildContext context) {
    final obstacles = ref.watch(obstaclesProvider);
    final wallSetup = ref.watch(wallSetupProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: context.colors.onPrimary,
        // Dark app bar over the photo: light title.
        titleTextStyle: context.textTheme.titleMedium
            ?.copyWith(color: context.colors.onPrimary),
        title: Text(
            _markingObstacles ? 'Mark windows & doors' : 'Mark the wall'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: () => _generate3D(context, wallSetup, obstacles),
              icon: const Icon(Icons.view_in_ar_rounded, size: 18),
              label: const Text('View in 3D'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: context.textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Main canvas ───────────────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canvas = constraints.biggest;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (MediaQuery.of(context).viewInsets.bottom == 0) {
                    ref.read(wallSetupProvider.notifier).syncLayout(canvas);
                  }
                });
                return _markingObstacles
                    ? _openingsView(canvas, wallSetup, obstacles)
                    : _cornersView(canvas, wallSetup, obstacles);
              },
            ),
          ),

          // ── Bottom panel: the current step ────────────────────────────
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(_panelHeight).clamp(
                _panelHeight,
                MediaQuery.sizeOf(context).height * _maxPanelShare),
            child: Material(
              color: AppTheme.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _markingObstacles
                    ? _ObstaclesStep(
                        obstacles: obstacles,
                        wallSetup: wallSetup,
                        leanDeg: _leanDeg,
                        lookingForOpenings: _lookingForOpenings,
                        openingsFound: _openingsFound,
                        onBack: () => setState(() => _markingObstacles = false),
                        onEditSize: _toWallSize,
                      )
                    : _CornersStep(
                        wallSetup: wallSetup,
                        suggest: _suggest,
                        onUseSuggestion: _useSuggestion,
                        selected: _corner,
                        onSelect: _selectCorner,
                        onNudge: _nudgeCorner,
                        onNext: _toWallSize,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1: the photo with the wall's corners ─────────────────────────────

  Widget _cornersView(
      Size canvas, WallSetup wall, List<Obstacle> obstacles) {
    final photoRect = photoRectIn(canvas, wall.photoSize);
    Offset toCanvas(Offset f) =>
        photoRect.topLeft +
        Offset(f.dx * photoRect.width, f.dy * photoRect.height);
    Offset toPhoto(Offset p) => Offset((p.dx - photoRect.left) / photoRect.width,
        (p.dy - photoRect.top) / photoRect.height);
    final points = [for (final c in wall.corners) toCanvas(c)];

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: photoRect,
          child: Image(
            image: _photo,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const PhotoError(),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _CornersPainter(
              points: points,
              openings: _openingsOnPhoto(wall, obstacles, toCanvas),
            ),
            size: Size.infinite,
          ),
        ),
        // Pointer shortcut only: screen-reader and switch users move the
        // corners with the arrow buttons instead.
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                HapticFeedback.selectionClick();
                ref
                    .read(wallSetupProvider.notifier)
                    .moveCorner(_corner, toPhoto(d.localPosition));
              },
            ),
          ),
        ),
        for (final corner in WallCorner.values)
          _CornerHandle(
            corner: corner,
            at: points[corner.index],
            selected: corner == _corner,
            onSelect: () => _selectCorner(corner),
            onDrag: (delta) {
              final notifier = ref.read(wallSetupProvider.notifier);
              final from = ref.read(wallSetupProvider).corner(corner);
              notifier.moveCorner(
                corner,
                from +
                    Offset(delta.dx / photoRect.width,
                        delta.dy / photoRect.height),
              );
              setState(() => _dragAt =
                  toCanvas(ref.read(wallSetupProvider).corner(corner)));
            },
            onDragEnd: () => setState(() => _dragAt = null),
          ),
        if (_dragAt case final at?) _Loupe(at: at, canvas: canvas),
      ],
    );
  }

  /// The windows and doors already marked, drawn back onto the photo
  /// through the perspective, for reference while the corners are moved.
  List<(ObstacleType, List<Offset>)> _openingsOnPhoto(WallSetup wall,
      List<Obstacle> obstacles, Offset Function(Offset) toCanvas) {
    if (obstacles.isEmpty || wall.scaleRatioX <= 0) return const [];
    final toPhoto = Homography.between([
      Offset.zero,
      Offset(wall.widthMm, 0),
      Offset(wall.widthMm, wall.heightMm),
      Offset(0, wall.heightMm),
    ], wall.wallCorners);
    if (toPhoto == null) return const [];
    Offset wallMm(double x, double y) => Offset(
        (x - wall.leftLinePx) / wall.scaleRatioX,
        (y - wall.topLinePx) / wall.scaleRatioY);
    return [
      for (final o in obstacles)
        (
          o.type,
          [
            wallMm(o.leftPx, o.topPx),
            wallMm(o.leftPx + o.widthPx, o.topPx),
            wallMm(o.leftPx + o.widthPx, o.topPx + o.heightPx),
            wallMm(o.leftPx, o.topPx + o.heightPx),
          ].map((p) => toCanvas(toPhoto.map(p))).toList(),
        ),
    ];
  }

  // ── Step 2: the wall straightened, with its windows and doors ────────────

  Widget _openingsView(
      Size canvas, WallSetup wall, List<Obstacle> obstacles) {
    final rect = Rect.fromLTRB(
        wall.leftLinePx, wall.topLinePx, wall.rightLinePx, wall.bottomLinePx);
    final photoSize = wall.photoSize;
    final cornersPx = wall.cornersPx;
    final straighten = cornersPx == null || rect.width < 1
        ? null
        : Homography.between(cornersPx, [
            Offset.zero,
            Offset(rect.width, 0),
            Offset(rect.width, rect.height),
            Offset(0, rect.height),
          ]);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (straighten != null && photoSize != null)
          Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      width: photoSize.width,
                      height: photoSize.height,
                      child: Transform(
                        transform: matrixOf(straighten),
                        child: Image(
                          image: _photo,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => const PhotoError(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          // The photo isn't decoded yet: show it as it is.
          Center(
            child: Image(
              image: _photo,
              width: canvas.width,
              height: canvas.height,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const PhotoError(),
            ),
          ),
        IgnorePointer(
          child: CustomPaint(
            painter: _WallFramePainter(rect),
            size: Size.infinite,
          ),
        ),
        for (final obs in obstacles)
          TraceBox(
            key: ValueKey(obs.id),
            obstacle: obs,
            name: obstacleName(obstacles, obs),
            canvasWidth: canvas.width,
            canvasHeight: canvas.height,
            interactive: true,
            onDelete: () =>
                ref.read(obstaclesProvider.notifier).remove(obs.id),
          ),
      ],
    );
  }

  void _generate3D(
    BuildContext context,
    WallSetup wallSetup,
    List<Obstacle> obstacles,
  ) {
    final payload = PayloadBuilder.toJson(
      wallWidthMm: wallSetup.widthMm,
      wallHeightMm: wallSetup.heightMm,
      wallDepthMm: wallSetup.depthMm,
      scaleRatio: wallSetup.scaleRatioX,
      scaleRatioX: wallSetup.scaleRatioX,
      scaleRatioY: wallSetup.scaleRatioY,
      leftLinePx: wallSetup.leftLinePx,
      bottomLinePx: wallSetup.bottomLinePx,
      obstacles: obstacles,
      canvasHeightPx: wallSetup.canvasHeightPx,
      capture: captureRecord(wallSetup),
      photoPath: widget.imagePath,
    );
    context.push('/viewer', extra: payload);
  }
}

/// How the wall was measured, kept with the design: the corners on the
/// photo, its size and lens, and how the phone was held. Lets a design be
/// checked against a tape later, and is the labelled data a learned
/// corner finder will be trained on.
Map<String, dynamic> captureRecord(WallSetup wall) {
  double r4(double v) => double.parse(v.toStringAsFixed(4));
  final size = wall.photoSize;
  final shape = wall.photoShape;
  return {
    'method': 'corners',
    'corners': [
      for (final c in wall.corners) [r4(c.dx), r4(c.dy)]
    ],
    if (size != null) 'photo_px': [size.width.round(), size.height.round()],
    if (wall.focalPx != null) 'focal_px': wall.focalPx!.roundToDouble(),
    if (shape != null) 'photo_aspect': r4(shape.aspect),
    if (shape != null) 'focal_source': shape.focalSource.name,
    if (wall.tilt != null) 'tilt_deg': wall.tilt!.toJson(),
    if (wall.suggestedCorners case final s?)
      'suggested_corners': [
        for (final c in s) [r4(c.dx), r4(c.dy)]
      ],
    if (wall.suggestedCorners != null && wall.suggestedBy != null)
      'suggested_by': wall.suggestedBy!.name,
    // Where the size came from: the photo (worktop, door, assumed ceiling)
    // or a typed measurement.
    if (wall.sizeFrom != null) 'size_from': wall.sizeFrom,
    // Where the wall meets the floor behind the cabinets (bottom-right,
    // bottom-left), when the bottom corners are on the cabinets' front.
    if (wall.bottomShift != null)
      'wall_bottom': [
        for (final c in wall.wallCorners.sublist(2)) [r4(c.dx), r4(c.dy)]
      ],
  };
}

/// A heading with the step number above it.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.title, this.trailing});

  final int step;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // A Wrap, so the button drops under the title at large text sizes.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Step $step of 3',
              style: context.textTheme.labelSmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            Text(title, style: context.textTheme.titleSmall),
          ],
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── Step 1: mark the wall's corners ─────────────────────────────────────────
/// What the wall-corner model did for this photo.
enum _Suggest {
  /// No model here, or nothing heard yet: say nothing.
  none,
  looking,

  /// Placed on the photo, to be checked.
  placed,

  /// Found after the salesperson had started: offered, not placed.
  offered,
  notFound,
}

/// A line in the panel about the corners the model found.
class _SuggestLine extends StatelessWidget {
  const _SuggestLine({required this.suggest, required this.onUse});

  final _Suggest suggest;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final (IconData? icon, String text) = switch (suggest) {
      _Suggest.none => (null, ''),
      _Suggest.looking => (null, 'Looking for the wall’s corners…'),
      _Suggest.placed => (
          Icons.auto_fix_high_rounded,
          'Corners placed for you. Check each one with the magnifier and '
              'drag any that are off.',
        ),
      _Suggest.offered => (Icons.auto_fix_high_rounded, 'Found the wall’s corners.'),
      _Suggest.notFound => (
          Icons.touch_app_rounded,
          'Couldn’t find the corners on this photo, as often happens with '
              'cabinets in front of the wall. Place them by hand.',
        ),
    };
    if (suggest == _Suggest.none) return const SizedBox.shrink();
    final style = context.textTheme.bodySmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            if (suggest == _Suggest.looking)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: style)),
            if (suggest == _Suggest.offered)
              TextButton(onPressed: onUse, child: const Text('Use them')),
          ],
        ),
      ),
    );
  }
}

class _CornersStep extends StatelessWidget {
  const _CornersStep({
    required this.wallSetup,
    required this.selected,
    required this.onSelect,
    required this.onNudge,
    required this.onNext,
    required this.suggest,
    required this.onUseSuggestion,
  });

  final WallSetup wallSetup;
  final _Suggest suggest;
  final VoidCallback onUseSuggestion;
  final WallCorner selected;
  final ValueChanged<WallCorner> onSelect;
  final void Function(int dx, int dy) onNudge;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final name = selected.label.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHeader(
          step: 1,
          title: 'Mark the wall’s corners',
          trailing: ElevatedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Next'),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Put a dot on each corner of the wall in front of you, where it '
          'meets the ceiling, floor and side walls. Drag a dot, or pick one '
          'and tap the photo.',
          style: context.textTheme.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        // Up here, where it's seen without scrolling the panel.
        _SuggestLine(suggest: suggest, onUse: onUseSuggestion),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final corner in WallCorner.values)
              ChoiceChip(
                label: Text(corner.label),
                showCheckmark: false,
                selected: corner == selected,
                onSelected: (_) => onSelect(corner),
              ),
            NudgeButtons(
              labels: NudgeLabels(
                left: 'Move $name corner left',
                right: 'Move $name corner right',
                up: 'Move $name corner up',
                down: 'Move $name corner down',
              ),
              onNudge: onNudge,
            ),
          ],
        ),
      ],
    );
  }
}

/// What the model found on the wall, for the windows-and-doors step.
class _OpeningsLine extends StatelessWidget {
  const _OpeningsLine({required this.looking, required this.found});

  final bool looking;
  final List<FoundOpening>? found;

  static String _count(int n, String one) =>
      n == 1 ? 'a $one' : '$n ${one}s';

  @override
  Widget build(BuildContext context) {
    final list = found;
    if (!looking && list == null) return const SizedBox.shrink();
    final String text;
    if (looking) {
      text = 'Looking for windows and doors…';
    } else if (list!.isEmpty) {
      text = 'No windows or doors found on the wall. Add any below.';
    } else {
      final windows = list.where((o) => o.type == ObstacleType.window).length;
      final doors = list.length - windows;
      final parts = [
        if (windows > 0) _count(windows, 'window'),
        if (doors > 0) _count(doors, 'door'),
      ];
      text = 'Found ${parts.join(' and ')}. Check each box sits on its '
          'frame, and drag or type to fix it.';
    }
    final style = context.textTheme.bodySmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            if (looking)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.auto_fix_high_rounded,
                  size: 18, color: context.colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: style)),
          ],
        ),
      ),
    );
  }
}

// ── Step 3: mark windows and doors ──────────────────────────────────────────
class _ObstaclesStep extends ConsumerWidget {
  const _ObstaclesStep({
    required this.obstacles,
    required this.wallSetup,
    required this.leanDeg,
    required this.onBack,
    required this.onEditSize,
    this.lookingForOpenings = false,
    this.openingsFound,
  });

  final List<Obstacle> obstacles;
  final WallSetup wallSetup;
  final VoidCallback onEditSize;

  /// Windows and doors the model found and placed (null: none looked for).
  final bool lookingForOpenings;
  final List<FoundOpening>? openingsFound;

  /// How far upright edges lean on the straightened wall, once checked.
  final double? leanDeg;
  final VoidCallback onBack;

  void _add(WidgetRef ref, ObstacleType type) {
    HapticFeedback.lightImpact();
    final wall = wallSetup;
    final rx = wall.scaleRatioX, ry = wall.scaleRatioY;
    double px(double mm, double ratio, double fallback) =>
        ratio > 0 ? ScaleMath.mmToPx(mm, ratio) : fallback;

    // Typical sizes: a 1200 × 1000 window with a 1000 mm sill, or a
    // 900 × 2100 door on the floor. Each new one sits a little further
    // right so they don't stack.
    final isWindow = type == ObstacleType.window;
    final count = obstacles.where((o) => o.type == type).length;
    final w = px(isWindow ? 1200 : 900, rx, 120);
    final h = px(isWindow ? 1000 : 2100, ry, 180);
    final fromLeft = px(isWindow ? 600 : 200, rx, 20) + count * px(300, rx, 30);
    final fromFloor = px(isWindow ? 1000 : 0, ry, 0);

    final canvasW = wall.screenWidthPx, canvasH = wall.screenHeightPx;
    final width = w.clamp(kMinObstaclePx, canvasW).toDouble();
    final height = h.clamp(kMinObstaclePx, canvasH).toDouble();
    ref.read(obstaclesProvider.notifier).add(
          Obstacle(
            type: type,
            leftPx: (wall.leftLinePx + fromLeft)
                .clamp(0.0, canvasW - width)
                .toDouble(),
            topPx: (wall.bottomLinePx - fromFloor - height)
                .clamp(0.0, canvasH - height)
                .toDouble(),
            widthPx: width,
            heightPx: height,
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHeader(
          step: 3,
          title: 'Mark windows & doors',
          trailing: Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.crop_free_rounded, size: 18),
                label: const Text('Edit corners'),
              ),
              TextButton.icon(
                onPressed: onEditSize,
                icon: const Icon(Icons.straighten_rounded, size: 18),
                label: const Text('Edit size'),
              ),
            ],
          ),
        ),
        Text(
          'Wall ${wallSetup.widthMm.round()} × ${wallSetup.heightMm.round()} mm,'
          ' straightened: windows and doors should stand upright. If they '
          'lean, a corner is off. Tap a box to type its size.',
          style: context.textTheme.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        _OpeningsLine(
          looking: lookingForOpenings,
          found: openingsFound,
        ),
        if (leanDeg case final lean? when lean.abs() > kLeanWarnDeg)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppTheme.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Upright edges lean about '
                      '${lean.abs().toStringAsFixed(lean.abs() < 10 ? 1 : 0)}° '
                      'here, so a corner is probably off. Edit corners and '
                      'check each one with the magnifier.',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.danger),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        // Every box is also listed here, however small it is on the photo:
        // tap one to type its exact size, or remove it.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ToolButton(
              icon: Icons.window_rounded,
              label: 'Window',
              color: AppTheme.windowBorder,
              onTap: () => _add(ref, ObstacleType.window),
            ),
            _ToolButton(
              icon: Icons.door_front_door_rounded,
              label: 'Door',
              color: AppTheme.doorBorder,
              onTap: () => _add(ref, ObstacleType.door),
            ),
            for (final obs in obstacles)
              ActionChip(
                avatar: Icon(obstacleIcon(obs.type), size: 18),
                label: Text(
                  '${obstacleName(obstacles, obs)} · '
                  '${obstacleSizeLabel(wallSetup, obs)}',
                ),
                tooltip: 'Edit ${obstacleName(obstacles, obs).toLowerCase()}',
                onPressed: () => showObstacleEditor(context, ref, obs),
              ),
          ],
        ),
      ],
    );
  }
}

// ── A corner of the wall: a ring with a crosshair, so the exact point shows ─
class _CornerHandle extends StatelessWidget {
  const _CornerHandle({
    required this.corner,
    required this.at,
    required this.selected,
    required this.onSelect,
    required this.onDrag,
    required this.onDragEnd,
  });

  final WallCorner corner;
  final Offset at;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  static const double _hit = 48;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: at.dx - _hit / 2,
      top: at.dy - _hit / 2,
      width: _hit,
      height: _hit,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${corner.label} corner',
        hint: selected
            ? 'Use the arrows below the photo to move it'
            : 'Select, then use the arrows below the photo to move it',
        excludeSemantics: true,
        onTap: onSelect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          onPanStart: (_) => onSelect(),
          onPanUpdate: (d) => onDrag(d.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: CustomPaint(
            painter: _RingPainter(selected: selected),
          ),
        ),
      ),
    );
  }
}

const Color _cornerColor = Color(0xFF68D391);
const Color _cornerSelected = Colors.white;

class _RingPainter extends CustomPainter {
  _RingPainter({required this.selected});

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final color = selected ? _cornerSelected : _cornerColor;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 5 : 4;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 2;
    canvas.drawCircle(c, 13, shadow);
    canvas.drawCircle(c, 13, ring);
    // A crosshair with a gap at the centre, so the point itself stays clear.
    final hair = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (final d in const [Offset(1, 0), Offset(0, 1)]) {
      canvas.drawLine(c + d * 4, c + d * 11, hair);
      canvas.drawLine(c - d * 4, c - d * 11, hair);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.selected != selected;
}

/// While a corner is dragged, the photo under it, magnified, above the
/// finger (below it near the top of the photo), so it lands exactly on the
/// corner.
class _Loupe extends StatelessWidget {
  const _Loupe({required this.at, required this.canvas});

  final Offset at;
  final Size canvas;

  static const double _size = 116;
  static const double _lift = 100;

  @override
  Widget build(BuildContext context) {
    final above = at.dy - _lift - _size / 2 >= 0;
    final centre = Offset(
      at.dx.clamp(_size / 2, canvas.width - _size / 2).toDouble(),
      at.dy + (above ? -_lift : _lift),
    );
    return Positioned(
      left: centre.dx - _size / 2,
      top: centre.dy - _size / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size(_size, _size),
          magnificationScale: 2.5,
          focalPointOffset: at - centre,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(color: Colors.white, width: 2),
            ),
            shadows: [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
      ),
    );
  }
}

/// Dims everything but the wall, outlines it, and shows the windows and
/// doors already marked, in perspective.
class _CornersPainter extends CustomPainter {
  _CornersPainter({required this.points, required this.openings});

  final List<Offset> points;
  final List<(ObstacleType, List<Offset>)> openings;

  @override
  void paint(Canvas canvas, Size size) {
    final wall = Path()..addPolygon(points, true);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(wall, Offset.zero);
    canvas.drawPath(
        outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    canvas.drawPath(
      wall,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawPath(
      wall,
      Paint()
        ..color = _cornerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final (type, quad) in openings) {
      canvas.drawPath(
        Path()..addPolygon(quad, true),
        Paint()
          ..color = type == ObstacleType.window
              ? AppTheme.windowBorder
              : AppTheme.doorBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CornersPainter old) =>
      !listEquals(old.points, points) || old.openings != openings;
}

/// A frame round the straightened wall.
class _WallFramePainter extends CustomPainter {
  _WallFramePainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = _cornerColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_WallFramePainter old) => old.rect != rect;
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // A real button (reachable by TalkBack / switch access, 48dp). The type
    // colour stays on the icon and border; the label uses readable text.
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 18),
      label: Text('Add ${label.toLowerCase()}'),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.colors.onSurface,
        backgroundColor: color.withValues(alpha: 0.12),
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
