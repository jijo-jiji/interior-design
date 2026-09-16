import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/obstacle.dart';
import '../providers/wall_provider.dart';
import '../utils/payload_builder.dart';
import '../utils/scale_math.dart';
import '../widgets/trace_box.dart';
import '../../../shared/theme.dart';

/// Layer 1 + 2 + 4-Boundary Calibration — The main trace screen.
/// Stack contains: photo + 4-boundary wall calibration guides + TraceBoxes.
class TraceScreen extends ConsumerStatefulWidget {
  final String imagePath;
  const TraceScreen({super.key, required this.imagePath});

  @override
  ConsumerState<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends ConsumerState<TraceScreen> {
  bool _showCalibration = true;

  @override
  Widget build(BuildContext context) {
    final obstacles = ref.watch(obstaclesProvider);
    final wallSetup = ref.watch(wallSetupProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Trace Obstacles'),
        actions: [
          // ── Toggle Calibration Handles ────────────────────────────────
          IconButton(
            onPressed: () => setState(() => _showCalibration = !_showCalibration),
            icon: Icon(
              _showCalibration ? Icons.crop_free_rounded : Icons.crop_rounded,
              color: _showCalibration ? AppTheme.accent : Colors.white70,
            ),
            tooltip: _showCalibration ? 'Hide Wall Bounds' : 'Calibrate Wall Bounds',
          ),
          const SizedBox(width: 8),

          // ── Generate 3D button ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: () => _generate3D(context, ref, wallSetup, obstacles),
              icon: const Icon(Icons.view_in_ar_rounded, size: 18),
              label: Text(obstacles.isEmpty ? 'Generate 3D (Clean Wall)' : 'Generate 3D'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: const TextStyle(fontSize: 13),
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

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── Layer 2: Frozen photo ─────────────────────────────
                    Center(
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.contain,
                        width: canvasW,
                        height: canvasH,
                      ),
                    ),

                    // ── Dark edge vignette ────────────────────────────────
                    Container(
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

                    // ── Layer 3: Obstacle boxes ───────────────────────────
                    ...obstacles.map(
                      (obs) => TraceBox(
                        key: ValueKey(obs.id),
                        obstacle: obs,
                        canvasWidth: canvasW,
                        canvasHeight: canvasH,
                        onDelete: () => ref
                            .read(obstaclesProvider.notifier)
                            .remove(obs.id),
                      ),
                    ),

                    // ── Layer 4: Draggable 4-Boundary Wall Calibration Box ──
                    if (_showCalibration) ...[
                      // Dim outside non-wall areas
                      CustomPaint(
                        painter: _WallCropOverlayPainter(wallSetup: wallSetup),
                        size: Size.infinite,
                      ),

                      // Top Ceiling Line Handle
                      _BoundaryHandleLine(
                        isVertical: false,
                        positionPx: wallSetup.topLinePx,
                        color: Colors.orangeAccent,
                        label: 'CEILING LINE',
                        onDrag: (dy) {
                          final newRatio = (wallSetup.topLinePx + dy) / canvasH;
                          ref.read(wallSetupProvider.notifier).updateBoundaries(
                                topRatio: newRatio.clamp(0.0, wallSetup.bottomLineRatio - 0.05),
                              );
                        },
                      ),

                      // Bottom Floor Line Handle
                      _BoundaryHandleLine(
                        isVertical: false,
                        positionPx: wallSetup.bottomLinePx,
                        color: AppTheme.accent,
                        label: 'FLOOR LINE',
                        onDrag: (dy) {
                          final newRatio = (wallSetup.bottomLinePx + dy) / canvasH;
                          ref.read(wallSetupProvider.notifier).updateBoundaries(
                                bottomRatio: newRatio.clamp(wallSetup.topLineRatio + 0.05, 1.0),
                              );
                        },
                      ),

                      // Left Wall Line Handle
                      _BoundaryHandleLine(
                        isVertical: true,
                        positionPx: wallSetup.leftLinePx,
                        color: Colors.purpleAccent,
                        label: 'LEFT WALL',
                        onDrag: (dx) {
                          final newRatio = (wallSetup.leftLinePx + dx) / canvasW;
                          ref.read(wallSetupProvider.notifier).updateBoundaries(
                                leftRatio: newRatio.clamp(0.0, wallSetup.rightLineRatio - 0.05),
                              );
                        },
                      ),

                      // Right Wall Line Handle
                      _BoundaryHandleLine(
                        isVertical: true,
                        positionPx: wallSetup.rightLinePx,
                        color: Colors.purpleAccent,
                        label: 'RIGHT WALL',
                        onDrag: (dx) {
                          final newRatio = (wallSetup.rightLinePx + dx) / canvasW;
                          ref.read(wallSetupProvider.notifier).updateBoundaries(
                                rightRatio: newRatio.clamp(wallSetup.leftLineRatio + 0.05, 1.0),
                              );
                        },
                      ),
                    ],

                    // ── Scale ratio readout overlay ───────────────────────
                    if (wallSetup.scaleRatio > 0)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            'Scale: 1mm = ${wallSetup.scaleRatioX.toStringAsFixed(2)}px '
                            '| Calibrated Wall: ${wallSetup.widthMm.toStringAsFixed(0)}×${wallSetup.heightMm.toStringAsFixed(0)}mm',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),

          // ── Bottom toolbar ────────────────────────────────────────────
          _BottomToolbar(obstacles: obstacles),
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

// ── Draggable Boundary Handle Line Widget ────────────────────────────────────
class _BoundaryHandleLine extends StatelessWidget {
  final bool isVertical;
  final double positionPx;
  final Color color;
  final String label;
  final ValueChanged<double> onDrag;

  const _BoundaryHandleLine({
    required this.isVertical,
    required this.positionPx,
    required this.color,
    required this.label,
    required this.onDrag,
  });

  @override
  Widget build(BuildContext context) {
    const handleThick = 44.0;

    return Positioned(
      left: isVertical ? positionPx - handleThick / 2 : 0,
      right: isVertical ? null : 0,
      top: isVertical ? 0 : positionPx - handleThick / 2,
      bottom: isVertical ? 0 : null,
      width: isVertical ? handleThick : null,
      height: isVertical ? null : handleThick,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          HapticFeedback.selectionClick();
          onDrag(isVertical ? d.delta.dx : d.delta.dy);
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow line
            Container(
              width: isVertical ? 6 : double.infinity,
              height: isVertical ? double.infinity : 6,
              color: color.withOpacity(0.2),
            ),
            // High-contrast neon guide line
            Container(
              width: isVertical ? 2 : double.infinity,
              height: isVertical ? double.infinity : 2,
              color: color,
            ),
            // Tactile 36px circular frosted-glass grip knob
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xEE121620),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                isVertical ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            // Positioned label pill
            Positioned(
              top: isVertical ? 6 : null,
              left: isVertical ? null : 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
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

// ── Bottom toolbar ──────────────────────────────────────────────────────────
class _BottomToolbar extends ConsumerWidget {
  final List<Obstacle> obstacles;
  const _BottomToolbar({required this.obstacles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallSetup = ref.watch(wallSetupProvider);

    void addObstacle(ObstacleType type) {
      final ratioX = wallSetup.scaleRatioX;
      final ratioY = wallSetup.scaleRatioY;

      final w = ratioX > 0 ? ScaleMath.mmToPx(900, ratioX) : 120.0;
      final h = ratioY > 0 ? ScaleMath.mmToPx(2100, ratioY) : 180.0;

      // Position new obstacle relative to calibrated floor / left boundaries
      final left = wallSetup.leftLinePx + 20;
      final top = type == ObstacleType.door
          ? wallSetup.bottomLinePx - h
          : wallSetup.topLinePx + 40;

      ref.read(obstaclesProvider.notifier).add(
            Obstacle(
              type: type,
              leftPx: left.clamp(0, wallSetup.screenWidthPx - w),
              topPx: top.clamp(0, wallSetup.screenHeightPx - h),
              widthPx: w.clamp(40, 300),
              heightPx: h.clamp(40, 400),
            ),
          );
    }

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _ToolButton(
            icon: Icons.window_rounded,
            label: 'Window',
            color: AppTheme.windowBorder,
            onTap: () => addObstacle(ObstacleType.window),
          ),
          const SizedBox(width: 12),
          _ToolButton(
            icon: Icons.door_front_door_rounded,
            label: 'Door',
            color: AppTheme.doorBorder,
            onTap: () => addObstacle(ObstacleType.door),
          ),
          const Spacer(),
          if (obstacles.isNotEmpty)
            Text(
              '${obstacles.length} obstacle${obstacles.length > 1 ? 's' : ''}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
