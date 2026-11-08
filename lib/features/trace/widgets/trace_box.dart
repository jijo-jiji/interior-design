import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme.dart';
import '../models/obstacle.dart';
import '../providers/wall_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/scale_math.dart';
import 'obstacle_editor.dart';

/// Layer 3 — The draggable obstacle box (window or door).
/// Positioned inside the Stack on the TraceScreen. Responds to pan gestures.
/// Separate handles for move (body), resize-width (right edge) and
/// resize-height (bottom edge) make touch interaction far easier on mobile.
/// Tapping the body opens the size-and-position editor, which is also the
/// way to move and resize it without dragging (WCAG 2.5.7).
class TraceBox extends ConsumerStatefulWidget {
  final Obstacle obstacle;

  /// "Window 1": shown on the box and read out by TalkBack.
  final String name;
  final double canvasWidth;
  final double canvasHeight;
  final VoidCallback onDelete;

  /// False when shown for reference only: visible, but not touchable.
  final bool interactive;

  const TraceBox({
    super.key,
    required this.obstacle,
    required this.name,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.onDelete,
    this.interactive = true,
  });

  @override
  ConsumerState<TraceBox> createState() => _TraceBoxState();
}

class _TraceBoxState extends ConsumerState<TraceBox> {
  late double _left;
  late double _top;
  late double _width;
  late double _height;

  static const double _minSize = kMinObstaclePx;

  // ── Touch handle sizes — large enough for reliable mobile touch ───────────
  static const double _edgeHandleThick = 28; // right / bottom edge handles
  static const double _cornerHandle = 44; // corner resize grip

  @override
  void initState() {
    super.initState();
    _left = widget.obstacle.leftPx;
    _top = widget.obstacle.topPx;
    _width = widget.obstacle.widthPx;
    _height = widget.obstacle.heightPx;
  }

  @override
  void didUpdateWidget(TraceBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obstacle != widget.obstacle) {
      _left = widget.obstacle.leftPx;
      _top = widget.obstacle.topPx;
      _width = widget.obstacle.widthPx;
      _height = widget.obstacle.heightPx;
    }
  }

  void _pushToProvider() {
    ref.read(obstaclesProvider.notifier).update(
          widget.obstacle.copyWith(
            leftPx: _left,
            topPx: _top,
            widthPx: _width,
            heightPx: _height,
          ),
        );
  }

  Color get _fillColor => widget.obstacle.type == ObstacleType.window
      ? AppTheme.windowColor
      : AppTheme.doorColor;

  Color get _borderColor => widget.obstacle.type == ObstacleType.window
      ? AppTheme.windowBorder
      : AppTheme.doorBorder;

  void _edit() {
    HapticFeedback.lightImpact();
    showObstacleEditor(context, ref, widget.obstacle);
  }

  @override
  Widget build(BuildContext context) {
    final sizeLabel = obstacleSizeLabel(
      ref.watch(wallSetupProvider),
      widget.obstacle.copyWith(widthPx: _width, heightPx: _height),
    );
    return Positioned(
      left: _left,
      top: _top,
      width: _width,
      height: _height,
      child: IgnorePointer(
        ignoring: !widget.interactive,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Main body — drag to move, tap to edit size and position ────────
            Positioned.fill(
              child: Semantics(
                button: true,
                label: '${widget.name}, $sizeLabel',
                onTapHint: 'Edit size and position',
                excludeSemantics: true,
                onTap: _edit,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _edit,
                  onPanUpdate: (d) {
                    setState(() {
                      _left = ScaleMath.clampLeft(
                          _left + d.delta.dx, _width, widget.canvasWidth);
                      _top = ScaleMath.clampTop(
                          _top + d.delta.dy, _height, widget.canvasHeight);
                    });
                  },
                  onPanEnd: (_) => _pushToProvider(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _fillColor,
                      border: Border.all(color: _borderColor, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    // A solid label, so it stays readable on any photo; scales
                    // down rather than overflowing a small box.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.name,
                                style: context.textTheme.labelMedium),
                            if (sizeLabel.isNotEmpty)
                              Text(sizeLabel,
                                  style: context.textTheme.labelSmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Right edge — drag to change WIDTH ─────────────────────────────
            Positioned(
              top: 0,
              bottom: 0,
              right: -_edgeHandleThick / 2,
              width: _edgeHandleThick,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _width = (_width + d.delta.dx).clamp(
                      _minSize,
                      widget.canvasWidth - _left,
                    );
                  });
                },
                onPanEnd: (_) => _pushToProvider(),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),

            // ── Bottom edge — drag to change HEIGHT ───────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: -_edgeHandleThick / 2,
              height: _edgeHandleThick,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _height = (_height + d.delta.dy).clamp(
                      _minSize,
                      widget.canvasHeight - _top,
                    );
                  });
                },
                onPanEnd: (_) => _pushToProvider(),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),

            // ── Corner resize (bottom-right) — width AND height together ──────
            Positioned(
              bottom: -_edgeHandleThick / 2,
              right: -_edgeHandleThick / 2,
              width: _cornerHandle,
              height: _cornerHandle,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _width = (_width + d.delta.dx)
                        .clamp(_minSize, widget.canvasWidth - _left);
                    _height = (_height + d.delta.dy)
                        .clamp(_minSize, widget.canvasHeight - _top);
                  });
                },
                onPanEnd: (_) => _pushToProvider(),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _borderColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),

            // ── Remove (top-right): a labelled 48dp button ────────────────────
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'Remove ${widget.name.toLowerCase()}',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  widget.onDelete();
                },
                icon: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
