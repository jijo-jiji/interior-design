import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/theme.dart';

/// Layer 2 — The camera screen.
/// Shows a live CameraPreview, captures the photo on tap,
/// immediately disposes the controller, and navigates to TraceScreen.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialised = false;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    // Dispose any stale controller first (handles hot reload safely)
    await _controller?.dispose();
    _controller = null;
    if (mounted) setState(() => _isInitialised = false);

    _cameras = await availableCameras();
    if (!mounted) return; // widget disposed while awaiting

    if (_cameras.isEmpty) {
      _showError('No cameras found on this device.');
      return;
    }

    // Prefer back camera for wall scanning
    final back = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    // ── Use a LOCAL variable — never touch _controller until fully ready ──
    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose(); // clean up on failure
      if (mounted) _showError('Camera error: $e');
      return;
    }

    if (!mounted) {
      // Widget was disposed while camera was initialising — don't leak
      await controller.dispose();
      return;
    }

    // Only now is it safe to assign and render CameraPreview
    setState(() {
      _controller = controller;
      _isInitialised = true;
    });
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final XFile file = await _controller!.takePicture();

      // ── Immediately dispose — no more drift ──────────────────────────────
      await _controller!.dispose();
      _controller = null;

      if (mounted) {
        context.push('/wall-setup', extra: file.path);
      }
    } catch (e) {
      setState(() => _isCapturing = false);
      _showError('Capture failed: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      await _controller?.dispose();
      _controller = null;

      if (mounted) {
        context.push('/wall-setup', extra: file.path);
      }
    } catch (e) {
      if (mounted) _showError('Failed to pick image: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Live preview ───────────────────────────────────────────────
            if (_isInitialised && _controller != null)
              CameraPreview(_controller!)
            else
              const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),

            // ── Top label ─────────────────────────────────────────────────
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Point at the wall and tap capture',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ),

            // ── Grid overlay guide lines ──────────────────────────────────
            if (_isInitialised)
              CustomPaint(
                painter: _GridOverlayPainter(),
                size: Size.infinite,
              ),

            // ── Capture and Gallery buttons ───────────────────────────────
            Positioned(
              bottom: 36,
              left: 24,
              right: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Gallery button
                  IconButton.filledTonal(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_rounded, size: 24),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(14),
                    ),
                    tooltip: 'Choose from Gallery',
                  ),

                  // Camera capture shutter button
                  GestureDetector(
                    onTap: _isCapturing ? null : _capture,
                    child: AnimatedScale(
                      scale: _isCapturing ? 0.88 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          color:
                              _isCapturing ? AppTheme.accent : Colors.white24,
                        ),
                        child: _isCapturing
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                      ),
                    ),
                  ),

                  // Balance spacer
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Wall framing guide & level overlay painter ────────────────────────────────
class _GridOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 0.7;

    final wallFramePaint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Rule of thirds
    for (int i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Central wall framing box guide (dotted corner brackets)
    final marginX = size.width * 0.08;
    final marginY = size.height * 0.12;
    final rect = Rect.fromLTRB(
        marginX, marginY, size.width - marginX, size.height - marginY);
    const bracketLen = 30.0;

    // Top-Left corner bracket
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(bracketLen, 0),
        wallFramePaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, bracketLen),
        wallFramePaint);

    // Top-Right corner bracket
    canvas.drawLine(rect.topRight, rect.topRight - const Offset(bracketLen, 0),
        wallFramePaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, bracketLen),
        wallFramePaint);

    // Bottom-Left corner bracket
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft + const Offset(bracketLen, 0), wallFramePaint);
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft - const Offset(0, bracketLen), wallFramePaint);

    // Bottom-Right corner bracket
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight - const Offset(bracketLen, 0), wallFramePaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight - const Offset(0, bracketLen), wallFramePaint);

    // Level crosshair target in center
    final center = Offset(size.width / 2, size.height / 2);
    final levelPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1.2;
    canvas.drawLine(
        center - const Offset(15, 0), center + const Offset(15, 0), levelPaint);
    canvas.drawLine(
        center - const Offset(0, 15), center + const Offset(0, 15), levelPaint);
    canvas.drawCircle(center, 4, levelPaint);
  }

  @override
  bool shouldRepaint(_GridOverlayPainter oldDelegate) => false;
}
