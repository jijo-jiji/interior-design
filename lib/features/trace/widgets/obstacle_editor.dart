import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme.dart';
import '../models/obstacle.dart';
import '../providers/wall_provider.dart';
import '../utils/scale_math.dart';

/// Smallest a window or door box can be on screen, in px.
const double kMinObstaclePx = 32;

/// "Window 1", "Door 2": numbered by type, in the order they were added.
String obstacleName(List<Obstacle> all, Obstacle obstacle) {
  final sameType = all.where((o) => o.type == obstacle.type).toList();
  return '${obstacle.label} ${sameType.indexWhere((o) => o.id == obstacle.id) + 1}';
}

/// "1200 × 1000 mm", or empty before the wall has a scale.
String obstacleSizeLabel(WallSetup wall, Obstacle obstacle) {
  if (wall.scaleRatioX <= 0 || wall.scaleRatioY <= 0) return '';
  final w = ScaleMath.pxToMm(obstacle.widthPx, wall.scaleRatioX).round();
  final h = ScaleMath.pxToMm(obstacle.heightPx, wall.scaleRatioY).round();
  return '$w × $h mm';
}

IconData obstacleIcon(ObstacleType type) => type == ObstacleType.window
    ? Icons.window_rounded
    : Icons.door_front_door_rounded;

/// Exact size and position in mm: the way to move and resize a window or
/// door without dragging. Applies the change, or removes the item.
Future<void> showObstacleEditor(
  BuildContext context,
  WidgetRef ref,
  Obstacle obstacle,
) async {
  final wall = ref.read(wallSetupProvider);
  if (wall.scaleRatioX <= 0 || wall.scaleRatioY <= 0) return;
  final name = obstacleName(ref.read(obstaclesProvider), obstacle);

  final result = await showDialog<_EditorResult>(
    context: context,
    builder: (_) => _ObstacleEditorDialog(
      name: name,
      type: obstacle.type,
      wallWidthMm: wall.widthMm,
      wallHeightMm: wall.heightMm,
      widthMm: ScaleMath.pxToMm(obstacle.widthPx, wall.scaleRatioX),
      heightMm: ScaleMath.pxToMm(obstacle.heightPx, wall.scaleRatioY),
      fromLeftMm:
          ScaleMath.pxToMm(obstacle.leftPx - wall.leftLinePx, wall.scaleRatioX),
      fromFloorMm: ScaleMath.pxToMm(
          wall.bottomLinePx - (obstacle.topPx + obstacle.heightPx),
          wall.scaleRatioY),
    ),
  );

  final notifier = ref.read(obstaclesProvider.notifier);
  switch (result) {
    case null:
      return;
    case _Remove():
      notifier.remove(obstacle.id);
    case _Apply(
        :final widthMm,
        :final heightMm,
        :final fromLeftMm,
        :final fromFloorMm
      ):
      final canvasW = wall.screenWidthPx;
      final canvasH = wall.screenHeightPx;
      final width = ScaleMath.mmToPx(widthMm, wall.scaleRatioX)
          .clamp(kMinObstaclePx, canvasW);
      final height = ScaleMath.mmToPx(heightMm, wall.scaleRatioY)
          .clamp(kMinObstaclePx, canvasH);
      final left =
          (wall.leftLinePx + ScaleMath.mmToPx(fromLeftMm, wall.scaleRatioX))
              .clamp(0.0, canvasW - width);
      final top = (wall.bottomLinePx -
              ScaleMath.mmToPx(fromFloorMm, wall.scaleRatioY) -
              height)
          .clamp(0.0, canvasH - height);
      notifier.update(obstacle.copyWith(
        leftPx: left,
        topPx: top,
        widthPx: width,
        heightPx: height,
      ));
  }
}

sealed class _EditorResult {
  const _EditorResult();
}

class _Remove extends _EditorResult {
  const _Remove();
}

class _Apply extends _EditorResult {
  const _Apply(this.widthMm, this.heightMm, this.fromLeftMm, this.fromFloorMm);
  final double widthMm;
  final double heightMm;
  final double fromLeftMm;
  final double fromFloorMm;
}

class _ObstacleEditorDialog extends StatefulWidget {
  const _ObstacleEditorDialog({
    required this.name,
    required this.type,
    required this.wallWidthMm,
    required this.wallHeightMm,
    required this.widthMm,
    required this.heightMm,
    required this.fromLeftMm,
    required this.fromFloorMm,
  });

  final String name;
  final ObstacleType type;
  final double wallWidthMm;
  final double wallHeightMm;
  final double widthMm;
  final double heightMm;
  final double fromLeftMm;
  final double fromFloorMm;

  @override
  State<_ObstacleEditorDialog> createState() => _ObstacleEditorDialogState();
}

class _ObstacleEditorDialogState extends State<_ObstacleEditorDialog> {
  late final _width = _ctrl(widget.widthMm);
  late final _height = _ctrl(widget.heightMm);
  late final _left = _ctrl(widget.fromLeftMm);
  late final _right =
      _ctrl(widget.wallWidthMm - widget.fromLeftMm - widget.widthMm);
  late final _floor = _ctrl(widget.fromFloorMm);
  late final _ceiling =
      _ctrl(widget.wallHeightMm - widget.fromFloorMm - widget.heightMm);

  static TextEditingController _ctrl(double mm) =>
      TextEditingController(text: mm.round().toString());

  double _read(TextEditingController c, double fallback) =>
      double.tryParse(c.text) ?? fallback;

  /// Keeps the opposite offset in step, so left + width + right = wall.
  void _sync(
      TextEditingController target,
      double total,
      TextEditingController a,
      double aFallback,
      TextEditingController b,
      double bFallback) {
    target.text =
        (total - _read(a, aFallback) - _read(b, bFallback)).round().toString();
  }

  void _horizontalFromLeft() => _sync(_right, widget.wallWidthMm, _left,
      widget.fromLeftMm, _width, widget.widthMm);
  void _horizontalFromRight() =>
      _sync(_left, widget.wallWidthMm, _right, 0, _width, widget.widthMm);
  void _verticalFromFloor() => _sync(_ceiling, widget.wallHeightMm, _floor,
      widget.fromFloorMm, _height, widget.heightMm);
  void _verticalFromCeiling() =>
      _sync(_floor, widget.wallHeightMm, _ceiling, 0, _height, widget.heightMm);

  @override
  void dispose() {
    for (final c in [_width, _height, _left, _right, _floor, _ceiling]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(TextEditingController c, String label,
          [VoidCallback? onChanged]) =>
      Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged == null ? null : (_) => onChanged(),
          decoration: InputDecoration(labelText: label, suffixText: 'mm'),
        ),
      );

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
            children: [children[0], const SizedBox(width: 12), children[1]]),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceRaised,
      title: Row(
        children: [
          Icon(obstacleIcon(widget.type), color: AppTheme.accentTaupeText),
          const SizedBox(width: 8),
          Expanded(child: Text('${widget.name} · size and position')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row([
              _field(_width, 'Width', _horizontalFromLeft),
              _field(_height, 'Height', _verticalFromFloor),
            ]),
            _row([
              _field(_left, 'From left wall', _horizontalFromLeft),
              _field(_right, 'From right wall', _horizontalFromRight),
            ]),
            _row([
              _field(_floor, 'From floor', _verticalFromFloor),
              _field(_ceiling, 'From ceiling', _verticalFromCeiling),
            ]),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context, const _Remove()),
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text('Remove ${widget.name.toLowerCase()}'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            _Apply(
              _read(_width, widget.widthMm),
              _read(_height, widget.heightMm),
              _read(_left, widget.fromLeftMm),
              _read(_floor, widget.fromFloorMm),
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
