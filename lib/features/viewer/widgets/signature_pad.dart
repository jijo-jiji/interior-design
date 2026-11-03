import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../shared/theme.dart';

/// Touch signature controller to retrieve PNG bytes / base64 string
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  List<List<Offset>> get strokes => List.unmodifiable(_strokes);

  bool get isEmpty => _strokes.isEmpty || _strokes.every((s) => s.isEmpty);
  bool get isNotEmpty => !isEmpty;

  void addPoint(Offset point) {
    if (_strokes.isEmpty) {
      _strokes.add([point]);
    } else {
      _strokes.last.add(point);
    }
    notifyListeners();
  }

  void startStroke(Offset point) {
    _strokes.add([point]);
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// Converts the captured signature strokes into a base64 encoded PNG string
  Future<String?> toBase64Png({double width = 400, double height = 180}) async {
    if (isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width, height),
    );

    // Draw white background
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Draw signature strokes
    final strokePaint = Paint()
      ..color = const Color(0xFF0F172A) // Dark slate ink
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, strokePaint);
        continue;
      }
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length - 1; i++) {
        final p0 = stroke[i];
        final p1 = stroke[i + 1];
        path.quadraticBezierTo(
            p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, strokePaint);
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    final bytes = byteData.buffer.asUint8List();
    return base64Encode(bytes);
  }
}

/// A lightweight, touch-optimized signature canvas widget
class SignaturePad extends StatefulWidget {
  final SignatureController controller;
  final double height;

  const SignaturePad({
    super.key,
    required this.controller,
    this.height = 160,
  });

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              widget.controller.isNotEmpty ? AppTheme.accent : AppTheme.border,
          width: widget.controller.isNotEmpty ? 1.5 : 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            // Baseline guide line
            Positioned(
              left: 20,
              right: 20,
              bottom: 36,
              child: Container(
                height: 1,
                color: AppTheme.border,
              ),
            ),

            // Hint label
            if (widget.controller.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.draw_rounded,
                          color: AppTheme.textTertiary, size: 18),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Sign here with finger to confirm design',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Signature capture gesture detector
            GestureDetector(
              onPanStart: (details) {
                widget.controller.startStroke(details.localPosition);
              },
              onPanUpdate: (details) {
                widget.controller.addPoint(details.localPosition);
              },
              child: CustomPaint(
                painter: _SignaturePainter(strokes: widget.controller.strokes),
                size: Size.infinite,
              ),
            ),

            // Clear button
            if (widget.controller.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  onTap: () => widget.controller.clear(),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_rounded,
                            size: 14, color: AppTheme.danger),
                        SizedBox(width: 4),
                        Text(
                          'Clear',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.accent // Deep Espresso archival ink
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.5, paint);
        continue;
      }
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length - 1; i++) {
        final p0 = stroke[i];
        final p1 = stroke[i + 1];
        path.quadraticBezierTo(
            p0.dx, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
