import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/theme.dart';
import '../models/obstacle.dart';
import '../providers/wall_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/scale_math.dart';

/// Layer 3 — The draggable obstacle box (window or door).
/// Positioned inside the Stack on the TraceScreen. Responds to pan gestures.
/// Separate handles for move (body), resize-width (right edge) and
/// resize-height (bottom edge) make touch interaction far easier on mobile.
/// Tapping the body opens an exact numeric dimensions edit dialog.
class TraceBox extends ConsumerStatefulWidget {
  final Obstacle obstacle;
  final double canvasWidth;
  final double canvasHeight;
  final VoidCallback onDelete;

  const TraceBox({
    super.key,
    required this.obstacle,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.onDelete,
  });

  @override
  ConsumerState<TraceBox> createState() => _TraceBoxState();
}

class _TraceBoxState extends ConsumerState<TraceBox> {
  late double _left;
  late double _top;
  late double _width;
  late double _height;

  static const double _minSize = 32;

  // ── Touch handle sizes — large enough for reliable mobile touch ───────────
  static const double _edgeHandleThick = 28; // right / bottom edge handles
  static const double _cornerHandle = 44; // corner delete badge hit area

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

  String get _mmLabel {
    final ratio = ref.read(wallSetupProvider).scaleRatio;
    if (ratio <= 0) return '';
    final wMm = ScaleMath.pxToMm(_width, ratio).round();
    final hMm = ScaleMath.pxToMm(_height, ratio).round();
    return '${wMm}mm × ${hMm}mm';
  }

  Future<void> _showEditDialog() async {
    final wallSetup = ref.read(wallSetupProvider);
    final ratioX = wallSetup.scaleRatioX;
    final ratioY = wallSetup.scaleRatioY;
    if (ratioX <= 0 || ratioY <= 0) return;

    final wallWMm = wallSetup.widthMm;
    final wallHMm = wallSetup.heightMm;

    final currentWMm = ScaleMath.pxToMm(_width, ratioX).roundToDouble();
    final currentHMm = ScaleMath.pxToMm(_height, ratioY).roundToDouble();

    // Offsets relative to calibrated wall boundary box
    final currentLeftPx = _left - wallSetup.leftLinePx;
    final currentLeftMm =
        ScaleMath.pxToMm(currentLeftPx, ratioX).roundToDouble();
    final currentRightMm =
        (wallWMm - currentLeftMm - currentWMm).roundToDouble();

    final currentFloorPx = wallSetup.bottomLinePx - (_top + _height);
    final currentFloorMm =
        ScaleMath.pxToMm(currentFloorPx, ratioY).roundToDouble();
    final currentCeilingMm =
        (wallHMm - currentFloorMm - currentHMm).roundToDouble();

    final wCtrl = TextEditingController(text: currentWMm.toStringAsFixed(0));
    final hCtrl = TextEditingController(text: currentHMm.toStringAsFixed(0));
    final leftCtrl =
        TextEditingController(text: currentLeftMm.toStringAsFixed(0));
    final rightCtrl =
        TextEditingController(text: currentRightMm.toStringAsFixed(0));
    final floorCtrl =
        TextEditingController(text: currentFloorMm.toStringAsFixed(0));
    final ceilingCtrl =
        TextEditingController(text: currentCeilingMm.toStringAsFixed(0));

    bool isUpdating = false;

    void onWidthChanged(String val) {
      if (isUpdating) return;
      isUpdating = true;
      final w = double.tryParse(val) ?? currentWMm;
      final l = double.tryParse(leftCtrl.text) ?? currentLeftMm;
      final r = (wallWMm - l - w).roundToDouble();
      rightCtrl.text = r.toStringAsFixed(0);
      isUpdating = false;
    }

    void onLeftChanged(String val) {
      if (isUpdating) return;
      isUpdating = true;
      final l = double.tryParse(val) ?? currentLeftMm;
      final w = double.tryParse(wCtrl.text) ?? currentWMm;
      final r = (wallWMm - l - w).roundToDouble();
      rightCtrl.text = r.toStringAsFixed(0);
      isUpdating = false;
    }

    void onRightChanged(String val) {
      if (isUpdating) return;
      isUpdating = true;
      final r = double.tryParse(val) ?? currentRightMm;
      final w = double.tryParse(wCtrl.text) ?? currentWMm;
      final l = (wallWMm - r - w).roundToDouble();
      leftCtrl.text = l.toStringAsFixed(0);
      isUpdating = false;
    }

    void onHeightChanged(String val) {
      if (isUpdating) return;
      isUpdating = true;
      final h = double.tryParse(val) ?? currentHMm;
      final f = double.tryParse(floorCtrl.text) ?? currentFloorMm;
      final c = (wallHMm - f - h).roundToDouble();
      ceilingCtrl.text = c.toStringAsFixed(0);
      isUpdating = false;
    }

    void onFloorChanged(String val) {
      if (isUpdating) return;
      isUpdating = true;
      final f = double.tryParse(val) ?? currentFloorMm;
      final h = double.tryParse(hCtrl.text) ?? currentHMm;
      final c = (wallHMm - f - h).roundToDouble();
      ceilingCtrl.text = c.toStringAsFixed(0);
      isUpdating = false;
    }

    void onCeilingChanged(String val) {
      if (isUpdating) return;
      isUpdating = true;
      final c = double.tryParse(val) ?? currentCeilingMm;
      final h = double.tryParse(hCtrl.text) ?? currentHMm;
      final f = (wallHMm - c - h).roundToDouble();
      floorCtrl.text = f.toStringAsFixed(0);
      isUpdating = false;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceRaised,
        title: Row(
          children: [
            Icon(
              widget.obstacle.type == ObstacleType.window
                  ? Icons.window_rounded
                  : Icons.door_front_door_rounded,
              color: _borderColor,
            ),
            const SizedBox(width: 8),
            const Text('Exact Dimensions & Offsets (mm)',
                style: TextStyle(fontSize: 15)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: onWidthChanged,
                      decoration:
                          const InputDecoration(labelText: 'Width (mm)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: hCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: onHeightChanged,
                      decoration:
                          const InputDecoration(labelText: 'Height (mm)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: leftCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: onLeftChanged,
                      decoration:
                          const InputDecoration(labelText: 'Dist Left (mm)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: rightCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: onRightChanged,
                      decoration:
                          const InputDecoration(labelText: 'Dist Right (mm)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: floorCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: onFloorChanged,
                      decoration:
                          const InputDecoration(labelText: 'Dist Floor (mm)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: ceilingCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: onCeilingChanged,
                      decoration:
                          const InputDecoration(labelText: 'Dist Ceiling (mm)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (result == true) {
      final newWMm = double.tryParse(wCtrl.text) ?? currentWMm;
      final newHMm = double.tryParse(hCtrl.text) ?? currentHMm;
      final newLeftMm = double.tryParse(leftCtrl.text) ?? currentLeftMm;
      final newFloorMm = double.tryParse(floorCtrl.text) ?? currentFloorMm;

      setState(() {
        _width = ScaleMath.mmToPx(newWMm, ratioX)
            .clamp(_minSize, widget.canvasWidth);
        _height = ScaleMath.mmToPx(newHMm, ratioY)
            .clamp(_minSize, widget.canvasHeight);

        final leftPx =
            wallSetup.leftLinePx + ScaleMath.mmToPx(newLeftMm, ratioX);
        _left = leftPx.clamp(0, widget.canvasWidth - _width);

        final floorTopPx = wallSetup.bottomLinePx -
            ScaleMath.mmToPx(newFloorMm, ratioY) -
            _height;
        _top = floorTopPx.clamp(0, widget.canvasHeight - _height);
      });
      _pushToProvider();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _left,
      top: _top,
      width: _width,
      height: _height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Main body — drag to move, tap to edit numeric dimensions ───────
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                _showEditDialog();
              },
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.obstacle.type == ObstacleType.window
                          ? Icons.window_rounded
                          : Icons.door_front_door_rounded,
                      color: _borderColor,
                      size: 20,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.obstacle.label,
                      style: TextStyle(
                        color: _borderColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _mmLabel,
                      style: TextStyle(
                        color: _borderColor.withValues(alpha: 0.85),
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to edit',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 8,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
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

          // ── Delete badge (top-right) ───────────────────────────────────────
          Positioned(
            top: -_cornerHandle / 2,
            right: -_cornerHandle / 2,
            width: _cornerHandle,
            height: _cornerHandle,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                widget.onDelete();
              },
              child: Center(
                child: Container(
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
          ),
        ],
      ),
    );
  }
}
