import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../shared/platform/photo_flip.dart';
import '../../../shared/theme.dart';
import '../providers/wall_provider.dart';

/// Within these, the phone counts as level and upright (degrees).
const double kLevelRollDeg = 2;
const double kLevelPitchDeg = 6;

/// Layer 2 — The camera screen.
/// Shows a live CameraPreview, captures the photo on tap,
/// immediately disposes the controller, and navigates to TraceScreen.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  CameraController? _controller;
  StreamSubscription<AccelerometerEvent>? _tiltSub;

  /// How the phone is held right now, smoothed; null with no sensor.
  final _tilt = ValueNotifier<CaptureTilt?>(null);
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

    try {
      _cameras = await availableCameras();
    } catch (e) {
      if (mounted) _showError(_cameraProblem(e), offerGallery: true);
      return;
    }
    if (!mounted) return; // widget disposed while awaiting

    if (_cameras.isEmpty) {
      _showError(
        "This phone has no camera we can use. Choose a photo from the "
        'gallery instead.',
        offerGallery: true,
      );
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
      // 1080p: the corners are marked on this photo, and more pixels per
      // millimetre means a more exact wall.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose(); // clean up on failure
      if (mounted) _showError(_cameraProblem(e), offerGallery: true);
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
    _startLevel();
  }

  /// The level bubble: from the accelerometer, only once the camera runs
  /// (no camera, no point). Browsers are left out: most laptops have no
  /// sensor, and phone browsers ask permission first.
  void _startLevel() {
    if (kIsWeb || _tiltSub != null) return;
    _tiltSub =
        accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
            .listen(_onTilt,
                onError: (Object _) => _tilt.value = null,
                cancelOnError: true);
  }

  void _onTilt(AccelerometerEvent e) {
    final sideways = math.sqrt(e.x * e.x + e.y * e.y);
    if (sideways + e.z.abs() < 1) return; // falling, or no real reading
    // Upright, gravity reads along the phone's y axis; a clockwise turn
    // moves it towards -x. Held sideways counts as level too.
    var roll = math.atan2(-e.x, e.y) * 180 / math.pi;
    roll -= 90 * (roll / 90).roundToDouble();
    // The screen tipping back (camera looking down) moves gravity to +z.
    final pitch = math.atan2(e.z, sideways) * 180 / math.pi;
    final prev = _tilt.value;
    const k = 0.2; // smoothing
    _tilt.value = prev == null
        ? CaptureTilt(rollDeg: roll, pitchDeg: pitch)
        : CaptureTilt(
            rollDeg: prev.rollDeg + k * (roll - prev.rollDeg),
            pitchDeg: prev.pitchDeg + k * (pitch - prev.pitchDeg),
          );
  }

  Future<void> _capture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final XFile file = await _controller!.takePicture();
      // In a browser, photos from any camera not marked as the back camera
      // (e.g. a laptop webcam) come out mirrored; turn them back.
      final mirrored = kIsWeb &&
          _controller!.description.lensDirection != CameraLensDirection.back;
      final path = mirrored ? await unmirrorPhoto(file.path) : file.path;
      // A new photo: corners start afresh; keep how the phone was held.
      ref.read(wallSetupProvider.notifier).startPhoto(tilt: _tilt.value);
      ref.read(obstaclesProvider.notifier).clear();

      // ── Immediately dispose — no more drift ──────────────────────────────
      await _tiltSub?.cancel();
      _tiltSub = null;
      await _controller!.dispose();
      _controller = null;

      if (mounted) {
        context.push('/trace', extra: path);
      }
    } catch (_) {
      setState(() => _isCapturing = false);
      _showError("Couldn't take the photo. Try again.");
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      // A new photo, held who knows how.
      ref.read(wallSetupProvider.notifier).startPhoto();
      ref.read(obstaclesProvider.notifier).clear();

      await _tiltSub?.cancel();
      _tiltSub = null;
      await _controller?.dispose();
      _controller = null;

      if (mounted) {
        context.push('/trace', extra: file.path);
      }
    } catch (_) {
      if (mounted) _showError("Couldn't open that photo. Try another one.");
    }
  }

  /// Plain words for what went wrong, and what to do next. Never the raw
  /// exception: the client may be looking at the screen.
  static String _cameraProblem(Object error) {
    final code = error is CameraException ? error.code : '';
    if (kIsWeb) {
      // Browsers only allow the camera on https:// or localhost, and ask
      // permission first.
      return "This browser didn't allow the camera. Pick a photo from the "
          'gallery instead (on a tablet it can open the camera too).';
    }
    if (code.startsWith('CameraAccess') || code.contains('ermission')) {
      return 'Camera access is off. Allow it in Settings, or pick a photo '
          'from the gallery.';
    }
    return "The camera didn't start. Close other camera apps and try again, "
        'or pick a photo from the gallery.';
  }

  void _showError(String msg, {bool offerGallery = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 6),
          action: offerGallery
              ? SnackBarAction(
                  label: 'Gallery',
                  textColor: Colors.white,
                  onPressed: _pickFromGallery,
                )
              : null,
        ),
      );
  }

  @override
  void dispose() {
    _tiltSub?.cancel();
    _tilt.dispose();
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

            // ── Back ──────────────────────────────────────────────────────
            Positioned(
              top: 8,
              left: 8,
              child: IconButton.filledTonal(
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            // ── Top label ─────────────────────────────────────────────────
            Positioned(
              // Below the Back button, so a long line never covers it.
              top: 64,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Fit the whole wall in, with all four corners showing. '
                    'Keep people out of the shot. For an exact size, tape an '
                    'A4 sheet flat on the wall first.',
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: context.colors.onPrimary),
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

            // ── Level bubble ──────────────────────────────────────────────
            if (_isInitialised)
              ValueListenableBuilder<CaptureTilt?>(
                valueListenable: _tilt,
                builder: (context, tilt, _) => tilt == null
                    ? const SizedBox.shrink()
                    : _Level(tilt: tilt),
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
                    tooltip: 'Choose a photo from the gallery',
                  ),

                  // Camera capture shutter button
                  // A labelled, focusable button (not a bare gesture).
                  Semantics(
                    button: true,
                    enabled: !_isCapturing,
                    label: 'Take photo',
                    child: InkWell(
                      onTap: _isCapturing ? null : _capture,
                      customBorder: const CircleBorder(),
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

// ── Wall framing guide ───────────────────────────────────────────────────────
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

  }

  @override
  bool shouldRepaint(_GridOverlayPainter oldDelegate) => false;
}

/// A horizon line that stays level with the room, and what to do about it.
class _Level extends StatelessWidget {
  const _Level({required this.tilt});

  final CaptureTilt tilt;

  @override
  Widget build(BuildContext context) {
    final rollOk = tilt.rollDeg.abs() <= kLevelRollDeg;
    final pitchOk = tilt.pitchDeg.abs() <= kLevelPitchDeg;
    final ok = rollOk && pitchOk;
    final color = ok ? const Color(0xFF68D391) : Colors.amberAccent;
    final message = ok
        ? 'Level'
        : !pitchOk
            ? 'Hold the phone upright'
            : 'Turn the phone level';

    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The horizon: turned against the phone, so it stays level.
          Transform.rotate(
            angle: -tilt.rollDeg * math.pi / 180,
            child: Container(width: 160, height: 2, color: color),
          ),
          // Where level is, on the phone.
          for (final dx in [-96.0, 96.0])
            Transform.translate(
              offset: Offset(dx, 0),
              child: Container(width: 24, height: 2, color: Colors.white70),
            ),
          Positioned(
            bottom: 132,
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ok
                          ? Icons.check_circle_rounded
                          : Icons.screen_rotation_rounded,
                      size: 16,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      message,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
