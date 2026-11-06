import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/obstacle.dart';
import '../providers/wall_provider.dart';
import '../utils/payload_builder.dart';
import '../utils/scale_math.dart';
import '../widgets/obstacle_editor.dart';
import '../widgets/trace_box.dart';
import '../../../shared/platform/photo_image.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets/nudge_buttons.dart';

/// Each arrow tap moves a wall edge this much of the photo.
const double kEdgeNudge = 0.005;

/// The bottom panel keeps one height in both steps, so the photo (and every
/// line and box measured against it) doesn't shift when the step changes.
/// It grows with the text size, up to [_maxPanelShare] of the screen.
const double _panelHeight = 232;
const double _maxPanelShare = 0.45;

/// Two steps over the wall photo:
///  1. line up the four wall edges (drag a line, tap the photo, or use the
///     arrows), then
///  2. mark the windows and doors (drag a box, or edit its exact size).
class TraceScreen extends ConsumerStatefulWidget {
  final String imagePath;
  const TraceScreen({super.key, required this.imagePath});

  @override
  ConsumerState<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends ConsumerState<TraceScreen> {
  bool _markingObstacles = false;
  WallEdge _edge = WallEdge.left;

  void _selectEdge(WallEdge edge) {
    if (_edge == edge) return;
    HapticFeedback.selectionClick();
    setState(() => _edge = edge);
  }

  void _nudgeEdge(int dx, int dy) {
    final wall = ref.read(wallSetupProvider);
    final step = _edge.isVertical ? dx : dy;
    ref
        .read(wallSetupProvider.notifier)
        .moveEdge(_edge, wall.ratioOf(_edge) + step * kEdgeNudge);
  }

  /// Tapping the photo in step 1 moves the selected edge there.
  void _placeEdge(Offset at, Size canvas) {
    HapticFeedback.selectionClick();
    ref.read(wallSetupProvider.notifier).moveEdge(
          _edge,
          _edge.isVertical ? at.dx / canvas.width : at.dy / canvas.height,
        );
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
            _markingObstacles ? 'Mark windows & doors' : 'Line up the wall'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: () => _generate3D(context, ref, wallSetup, obstacles),
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
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (MediaQuery.of(context).viewInsets.bottom == 0) {
                    ref.read(wallSetupProvider.notifier).updateScreenSize(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                  }
                });

                final canvasW = constraints.maxWidth;
                final canvasH = constraints.maxHeight;
                final canvas = Size(canvasW, canvasH);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── Layer 2: Frozen photo ─────────────────────────────
                    Center(
                      child: photoImage(
                        widget.imagePath,
                        width: canvasW,
                        height: canvasH,
                      ),
                    ),

                    // ── Dark edge vignette ────────────────────────────────
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 1.0,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.18),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Step 1: dim outside the wall; tap to place an edge ─
                    if (!_markingObstacles) ...[
                      IgnorePointer(
                        child: CustomPaint(
                          painter:
                              _WallCropOverlayPainter(wallSetup: wallSetup),
                          size: Size.infinite,
                        ),
                      ),
                      // Pointer shortcut only: screen-reader and switch users
                      // move edges with the arrow buttons instead.
                      Positioned.fill(
                        child: ExcludeSemantics(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _placeEdge(d.localPosition, canvas),
                          ),
                        ),
                      ),
                    ],

                    // ── Layer 3: Obstacle boxes (editable in step 2) ──────
                    for (final obs in obstacles)
                      TraceBox(
                        key: ValueKey(obs.id),
                        obstacle: obs,
                        name: obstacleName(obstacles, obs),
                        canvasWidth: canvasW,
                        canvasHeight: canvasH,
                        // Shown for reference while lining up the edges.
                        interactive: _markingObstacles,
                        onDelete: () =>
                            ref.read(obstaclesProvider.notifier).remove(obs.id),
                      ),

                    // ── Step 1: the four wall-edge lines ──────────────────
                    if (!_markingObstacles)
                      for (final edge in WallEdge.values)
                        _BoundaryHandleLine(
                          edge: edge,
                          positionPx: edge.isVertical
                              ? canvasW * wallSetup.ratioOf(edge)
                              : canvasH * wallSetup.ratioOf(edge),
                          selected: edge == _edge,
                          onSelect: () => _selectEdge(edge),
                          onDrag: (delta) {
                            final size = edge.isVertical ? canvasW : canvasH;
                            ref.read(wallSetupProvider.notifier).moveEdge(
                                  edge,
                                  ref.read(wallSetupProvider).ratioOf(edge) +
                                      delta / size,
                                );
                          },
                        ),
                  ],
                );
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
                        onBack: () => setState(() => _markingObstacles = false),
                      )
                    : _EdgesStep(
                        selected: _edge,
                        onSelect: _selectEdge,
                        onNudge: _nudgeEdge,
                        onNext: () => setState(() => _markingObstacles = true),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _generate3D(
    BuildContext context,
    WidgetRef ref,
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
    );
    context.push('/viewer', extra: payload);
  }
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
              'Step $step of 2',
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

// ── Step 1: line up the wall edges ──────────────────────────────────────────
class _EdgesStep extends StatelessWidget {
  const _EdgesStep({
    required this.selected,
    required this.onSelect,
    required this.onNudge,
    required this.onNext,
  });

  final WallEdge selected;
  final ValueChanged<WallEdge> onSelect;
  final void Function(int dx, int dy) onNudge;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHeader(
          step: 1,
          title: 'Line up the wall edges',
          trailing: ElevatedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Next'),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Pick an edge, then tap where it is on the photo, or use the arrows.',
          style: context.textTheme.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final edge in WallEdge.values)
              Tooltip(
                message: edge.label,
                child: ChoiceChip(
                  label: Text(edge.shortLabel),
                  showCheckmark: false,
                  selected: edge == selected,
                  onSelected: (_) => onSelect(edge),
                ),
              ),
            NudgeButtons(
              horizontal: selected.isVertical,
              vertical: !selected.isVertical,
              labels: NudgeLabels(
                left: 'Move ${selected.label.toLowerCase()} edge left',
                right: 'Move ${selected.label.toLowerCase()} edge right',
                up: 'Move ${selected.label.toLowerCase()} edge up',
                down: 'Move ${selected.label.toLowerCase()} edge down',
              ),
              onNudge: onNudge,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Step 2: mark windows and doors ──────────────────────────────────────────
class _ObstaclesStep extends ConsumerWidget {
  const _ObstaclesStep({
    required this.obstacles,
    required this.wallSetup,
    required this.onBack,
  });

  final List<Obstacle> obstacles;
  final WallSetup wallSetup;
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
          step: 2,
          title: 'Mark windows & doors',
          trailing: TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.crop_free_rounded, size: 18),
            label: const Text('Edit wall edges'),
          ),
        ),
        Text(
          'Wall ${wallSetup.widthMm.round()} × ${wallSetup.heightMm.round()} mm'
          ' · tap a box to type its size',
          style: context.textTheme.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
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

// ── Draggable boundary line ─────────────────────────────────────────────────
class _BoundaryHandleLine extends StatelessWidget {
  final WallEdge edge;
  final double positionPx;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<double> onDrag;

  const _BoundaryHandleLine({
    required this.edge,
    required this.positionPx,
    required this.selected,
    required this.onSelect,
    required this.onDrag,
  });

  static Color colorOf(WallEdge edge) => switch (edge) {
        WallEdge.ceiling => Colors.orangeAccent,
        WallEdge.floor => const Color(0xFF68D391),
        WallEdge.left || WallEdge.right => Colors.purpleAccent,
      };

  @override
  Widget build(BuildContext context) {
    const handleThick = 48.0;
    final isVertical = edge.isVertical;
    final color = colorOf(edge);
    final lineWidth = selected ? 4.0 : 2.0;

    return Positioned(
      left: isVertical ? positionPx - handleThick / 2 : 0,
      right: isVertical ? null : 0,
      top: isVertical ? 0 : positionPx - handleThick / 2,
      bottom: isVertical ? 0 : null,
      width: isVertical ? handleThick : null,
      height: isVertical ? null : handleThick,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${edge.label} edge',
        hint: selected
            ? 'Use the arrows below the photo to move it'
            : 'Select, then use the arrows below the photo to move it',
        excludeSemantics: true,
        onTap: onSelect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          onPanStart: (_) => onSelect(),
          onPanUpdate: (d) {
            HapticFeedback.selectionClick();
            onDrag(isVertical ? d.delta.dx : d.delta.dy);
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow line
              Container(
                width: isVertical ? 8 : double.infinity,
                height: isVertical ? double.infinity : 8,
                color: color.withValues(alpha: selected ? 0.35 : 0.2),
              ),
              // High-contrast guide line
              Container(
                width: isVertical ? lineWidth : double.infinity,
                height: isVertical ? double.infinity : lineWidth,
                color: color,
              ),
              // Grip knob
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xEE121620),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: selected ? Colors.white : color, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  isVertical
                      ? Icons.swap_horiz_rounded
                      : Icons.swap_vert_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              // Label pill
              Positioned(
                top: isVertical ? 6 : null,
                left: isVertical ? null : 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                    border: selected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  // Short names on the side lines: they sit in a 48px strip.
                  child: Text(
                    isVertical ? edge.shortLabel : edge.label,
                    style: context.textTheme.labelSmall
                        ?.copyWith(color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dim non-wall outer area ───────────────────────────────────────────────────
class _WallCropOverlayPainter extends CustomPainter {
  final WallSetup wallSetup;
  _WallCropOverlayPainter({required this.wallSetup});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.35);

    final left = wallSetup.leftLinePx;
    final right = wallSetup.rightLinePx;
    final top = wallSetup.topLinePx;
    final bottom = wallSetup.bottomLinePx;

    // Top rect
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, top), paint);
    // Bottom rect
    canvas.drawRect(Rect.fromLTRB(0, bottom, size.width, size.height), paint);
    // Left rect
    canvas.drawRect(Rect.fromLTRB(0, top, left, bottom), paint);
    // Right rect
    canvas.drawRect(Rect.fromLTRB(right, top, size.width, bottom), paint);
  }

  @override
  bool shouldRepaint(_WallCropOverlayPainter oldDelegate) => true;
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
