import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/theme.dart';

class FloorplanCalibrateScreen extends StatefulWidget {
  final String imagePath;

  const FloorplanCalibrateScreen({super.key, required this.imagePath});

  @override
  State<FloorplanCalibrateScreen> createState() =>
      _FloorplanCalibrateScreenState();
}

class _FloorplanCalibrateScreenState extends State<FloorplanCalibrateScreen> {
  Offset _pinA = const Offset(80, 200);
  Offset _pinB = const Offset(220, 200);

  final _dimensionController = TextEditingController(text: '900');
  double _ceilingHeightMm = 2700;

  // Selected room crop box (left, top, right, bottom in canvas coords)
  Rect _roomBox = const Rect.fromLTWH(50, 120, 280, 220);

  double get _pixelDistance {
    final dx = _pinB.dx - _pinA.dx;
    final dy = _pinB.dy - _pinA.dy;
    return sqrt(dx * dx + dy * dy);
  }

  double get _scaleRatio {
    final realMm = double.tryParse(_dimensionController.text) ?? 900;
    if (realMm <= 0) return 0.2;
    return _pixelDistance / realMm; // px per mm
  }

  void _generate3D() {
    final ratio = _scaleRatio;
    final wallWidthMm =
        ratio > 0 ? (_roomBox.width / ratio).clamp(1500.0, 12000.0) : 4000.0;

    final payload = {
      'wall': {
        'width_mm': wallWidthMm.roundToDouble(),
        'height_mm': _ceilingHeightMm,
        'depth_mm': 150.0,
        'created_via': 'floorplan_calibration',
      },
      'obstacles': <Map<String, dynamic>>[],
      'salesperson_id': 'demo_agent_01',
    };

    final jsonStr = jsonEncode(payload);
    context.push('/viewer', extra: jsonStr);
  }

  @override
  void dispose() {
    _dimensionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _scaleRatio;
    final currentMm = ratio > 0 ? (_roomBox.width / ratio).round() : 4000;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Set the scale'),
        actions: [
          TextButton.icon(
            onPressed: _generate3D,
            icon: const Icon(Icons.view_in_ar_rounded, color: AppTheme.accent),
            label: const Text(
              'View in 3D',
              style: TextStyle(
                  color: AppTheme.accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Instructions Banner ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.surfaceRaised,
              child: Row(
                children: [
                  const Icon(Icons.straighten_rounded,
                      color: AppTheme.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Drag A and B to the ends of a length you know, like a door (usually 900 mm) or a labelled wall.',
                      style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Interactive Calibration Canvas ────────────────────────────
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Blueprint background photo
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 3.5,
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  // Calibration line & Room Box overlay
                  CustomPaint(
                    size: Size.infinite,
                    painter: _CalibrationOverlayPainter(
                      pinA: _pinA,
                      pinB: _pinB,
                      roomBox: _roomBox,
                      scaleRatio: ratio,
                    ),
                  ),

                  // Pin A (Neon Green)
                  Positioned(
                    left: _pinA.dx - 18,
                    top: _pinA.dy - 18,
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() => _pinA += d.delta),
                      child: _PinWidget(
                          label: 'A', color: const Color(0xFF68D391)),
                    ),
                  ),

                  // Pin B (Neon Cyan)
                  Positioned(
                    left: _pinB.dx - 18,
                    top: _pinB.dy - 18,
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() => _pinB += d.delta),
                      child: _PinWidget(
                          label: 'B', color: const Color(0xFF00E5FF)),
                    ),
                  ),

                  // Room crop box resize handle (Bottom-Right)
                  Positioned(
                    left: _roomBox.right - 14,
                    top: _roomBox.bottom - 14,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        setState(() {
                          _roomBox = Rect.fromLTRB(
                            _roomBox.left,
                            _roomBox.top,
                            max(_roomBox.left + 80,
                                _roomBox.right + d.delta.dx),
                            max(_roomBox.top + 60,
                                _roomBox.bottom + d.delta.dy),
                          );
                        });
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.open_with_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bottom Calibration Parameters ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: AppTheme.surfaceRaised,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Real distance between Pin A & B
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _dimensionController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Length A–B (mm)',
                            labelStyle: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11),
                            prefixIcon: const Icon(Icons.straighten,
                                color: AppTheme.accent, size: 16),
                            filled: true,
                            fillColor: AppTheme.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Room Wall Width calculated readout
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2433),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF2C3344)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Wall width',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$currentMm mm',
                                style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Button to extrude into 3D
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _generate3D,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.view_in_ar_rounded, size: 18),
                      label: const Text(
                        'View in 3D',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinWidget extends StatelessWidget {
  final String label;
  final Color color;

  const _PinWidget({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _CalibrationOverlayPainter extends CustomPainter {
  final Offset pinA;
  final Offset pinB;
  final Rect roomBox;
  final double scaleRatio;

  _CalibrationOverlayPainter({
    required this.pinA,
    required this.pinB,
    required this.roomBox,
    required this.scaleRatio,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Line connecting Pin A and Pin B
    final linePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(pinA, pinB, linePaint);

    // 2. Room Box outline
    final boxPaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppTheme.accent.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    canvas.drawRect(roomBox, fillPaint);
    canvas.drawRect(roomBox, boxPaint);
  }

  @override
  bool shouldRepaint(covariant _CalibrationOverlayPainter oldDelegate) => true;
}
