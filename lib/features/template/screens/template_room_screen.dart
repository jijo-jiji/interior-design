import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/theme.dart';

enum RoomShape { singleWall, lShape, galley, studio }

class TemplateRoomScreen extends StatefulWidget {
  const TemplateRoomScreen({super.key});

  @override
  State<TemplateRoomScreen> createState() => _TemplateRoomScreenState();
}

class _TemplateRoomScreenState extends State<TemplateRoomScreen> {
  RoomShape _selectedShape = RoomShape.singleWall;

  double _widthMm = 4000;
  double _heightMm = 2700;
  double _returnMm = 2500;
  double _aisleMm = 1200;

  void _launch3D() {
    // Construct the wall specification for Three.js
    final payload = {
      'wall': {
        'width_mm': _widthMm,
        'height_mm': _heightMm,
        'depth_mm': 150.0,
        'shape': _selectedShape.name,
        'return_mm': _selectedShape == RoomShape.lShape ? _returnMm : 0,
        'aisle_mm': _selectedShape == RoomShape.galley ? _aisleMm : 0,
      },
      'obstacles': <Map<String, dynamic>>[],
      'salesperson_id': 'demo_agent_01',
      'created_via': 'template_dial',
    };

    final jsonStr = jsonEncode(payload);
    context.push('/viewer', extra: jsonStr);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Room size'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Shape Selector Pills ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ShapeTab(
                      label: 'Single Wall',
                      icon: Icons.horizontal_rule_rounded,
                      isSelected: _selectedShape == RoomShape.singleWall,
                      onTap: () =>
                          setState(() => _selectedShape = RoomShape.singleWall),
                    ),
                    const SizedBox(width: 8),
                    _ShapeTab(
                      label: 'L-Shape Kitchen',
                      icon: Icons.turn_right_rounded,
                      isSelected: _selectedShape == RoomShape.lShape,
                      onTap: () =>
                          setState(() => _selectedShape = RoomShape.lShape),
                    ),
                    const SizedBox(width: 8),
                    _ShapeTab(
                      label: 'Galley (2 Walls)',
                      icon: Icons.view_column_rounded,
                      isSelected: _selectedShape == RoomShape.galley,
                      onTap: () =>
                          setState(() => _selectedShape = RoomShape.galley),
                    ),
                    const SizedBox(width: 8),
                    _ShapeTab(
                      label: 'Studio Box',
                      icon: Icons.crop_square_rounded,
                      isSelected: _selectedShape == RoomShape.studio,
                      onTap: () =>
                          setState(() => _selectedShape = RoomShape.studio),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(color: AppTheme.border, height: 1),

            // ── Visual Wireframe Preview Box ──────────────────────────────
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF131720),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2C3344)),
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size(260, 160),
                    painter: _RoomWireframePainter(
                      shape: _selectedShape,
                      widthMm: _widthMm,
                      heightMm: _heightMm,
                      returnMm: _returnMm,
                    ),
                  ),
                ),
              ),
            ),

            // ── Dimension Controls ───────────────────────────────────────
            Expanded(
              flex: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Wall Width Slider
                      _DimensionSlider(
                        label: 'Main Wall Width',
                        value: _widthMm,
                        min: 2000,
                        max: 8000,
                        step: 100,
                        unit: 'mm',
                        onChanged: (val) => setState(() => _widthMm = val),
                      ),

                      const SizedBox(height: 10),

                      // Ceiling Height Slider
                      _DimensionSlider(
                        label: 'Ceiling Height',
                        value: _heightMm,
                        min: 2200,
                        max: 3600,
                        step: 50,
                        unit: 'mm',
                        onChanged: (val) => setState(() => _heightMm = val),
                      ),

                      if (_selectedShape == RoomShape.lShape) ...[
                        const SizedBox(height: 10),
                        _DimensionSlider(
                          label: 'Return Wall Length',
                          value: _returnMm,
                          min: 1200,
                          max: 5000,
                          step: 100,
                          unit: 'mm',
                          onChanged: (val) => setState(() => _returnMm = val),
                        ),
                      ],

                      if (_selectedShape == RoomShape.galley) ...[
                        const SizedBox(height: 10),
                        _DimensionSlider(
                          label: 'Galley Aisle Clearance',
                          value: _aisleMm,
                          min: 900,
                          max: 2000,
                          step: 50,
                          unit: 'mm',
                          onChanged: (val) => setState(() => _aisleMm = val),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Launch 3D Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _launch3D,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.view_in_ar_rounded),
                          label: const Text('View in 3D'),
                        ),
                      ),
                    ],
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

class _ShapeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ShapeTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accent : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.accent : AppTheme.outline,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16,
                  color: isSelected ? AppTheme.bg : AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.textTheme.labelMedium?.copyWith(
                    color: isSelected
                        ? context.colors.onPrimary
                        : context.colors.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DimensionSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final ValueChanged<double> onChanged;

  const _DimensionSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceRaised,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${value.toStringAsFixed(0)} $unit',
                style: context.textTheme.labelSmall
                    ?.copyWith(color: context.colors.primary),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.accent,
            inactiveTrackColor: AppTheme.surfaceElevated,
            thumbColor: Colors.white,
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _RoomWireframePainter extends CustomPainter {
  final RoomShape shape;
  final double widthMm;
  final double heightMm;
  final double returnMm;

  _RoomWireframePainter({
    required this.shape,
    required this.widthMm,
    required this.heightMm,
    required this.returnMm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final wallPaint = Paint()
      ..color = AppTheme.accent
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dimPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    if (shape == RoomShape.singleWall) {
      final y = size.height / 2;
      canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), wallPaint);

      // Dimension guide
      canvas.drawLine(
          Offset(20, y + 25), Offset(size.width - 20, y + 25), dimPaint);
      canvas.drawLine(Offset(20, y + 18), Offset(20, y + 32), dimPaint);
      canvas.drawLine(Offset(size.width - 20, y + 18),
          Offset(size.width - 20, y + 32), dimPaint);
    } else if (shape == RoomShape.lShape) {
      final path = Path();
      path.moveTo(30, 30);
      path.lineTo(30, size.height - 30);
      path.lineTo(size.width - 30, size.height - 30);
      canvas.drawPath(path, wallPaint);
    } else if (shape == RoomShape.galley) {
      canvas.drawLine(
          const Offset(30, 40), Offset(size.width - 30, 40), wallPaint);
      canvas.drawLine(Offset(30, size.height - 40),
          Offset(size.width - 30, size.height - 40), wallPaint);
    } else {
      // Studio
      final rect = Rect.fromLTRB(30, 30, size.width - 30, size.height - 30);
      canvas.drawRect(rect, wallPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoomWireframePainter oldDelegate) => true;
}
