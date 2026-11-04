import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/platform/photo_image.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets/nudge_buttons.dart';

/// The four marks on the plan.
enum _Marker {
  a('Point A', 'A', Color(0xFF68D391)),
  b('Point B', 'B', Color(0xFF00E5FF)),
  wallStart('Wall start', '1', AppTheme.accent),
  wallEnd('Wall end', '2', AppTheme.accent);

  const _Marker(this.label, this.badge, this.color);
  final String label;

  /// "point A", "wall end": for use mid-sentence.
  String get inSentence => label[0].toLowerCase() + label.substring(1);
  final String badge;
  final Color color;
}

/// Each arrow tap moves the selected mark this many plan pixels.
const double kMarkerNudgePx = 2;

/// Measures one wall from a floor plan image: A–B is a length the
/// salesperson knows (like a 900 mm door), which sets the scale; the two
/// wall marks give the wall's length. Marks can be dragged, placed by
/// tapping the plan, or moved with the arrow buttons.
class FloorplanCalibrateScreen extends StatefulWidget {
  final String imagePath;

  const FloorplanCalibrateScreen({super.key, required this.imagePath});

  @override
  State<FloorplanCalibrateScreen> createState() =>
      _FloorplanCalibrateScreenState();
}

class _FloorplanCalibrateScreenState extends State<FloorplanCalibrateScreen> {
  /// Positions in plan coordinates (they zoom with the plan). Set on the
  /// first layout, from the plan's size.
  Map<_Marker, Offset>? _marks;
  _Marker _selected = _Marker.wallEnd;
  Size _planSize = Size.zero;

  final _dimensionController = TextEditingController(text: '900');
  final double _ceilingHeightMm = 2700;

  Map<_Marker, Offset> _initialMarks(Size size) => {
        _Marker.a: Offset(size.width * 0.25, size.height * 0.3),
        _Marker.b: Offset(size.width * 0.55, size.height * 0.3),
        _Marker.wallStart: Offset(size.width * 0.15, size.height * 0.65),
        _Marker.wallEnd: Offset(size.width * 0.85, size.height * 0.65),
      };

  double _distance(_Marker from, _Marker to) =>
      (_marks![to]! - _marks![from]!).distance;

  /// Pixels per mm, from the A–B length; null until it's usable.
  double? get _scaleRatio {
    final realMm = double.tryParse(_dimensionController.text) ?? 0;
    final px = _distance(_Marker.a, _Marker.b);
    if (realMm <= 0 || px <= 0) return null;
    return px / realMm;
  }

  double? get _wallMm {
    final ratio = _scaleRatio;
    if (ratio == null) return null;
    return _distance(_Marker.wallStart, _Marker.wallEnd) / ratio;
  }

  void _select(_Marker marker) {
    if (_selected != marker) setState(() => _selected = marker);
  }

  void _move(_Marker marker, Offset to) {
    setState(() {
      _marks![marker] = Offset(
        to.dx.clamp(0, _planSize.width),
        to.dy.clamp(0, _planSize.height),
      );
    });
  }

  void _nudge(int dx, int dy) => _move(
        _selected,
        _marks![_selected]! + Offset(dx * kMarkerNudgePx, dy * kMarkerNudgePx),
      );

  void _generate3D() {
    final wallWidthMm = (_wallMm ?? 4000).clamp(1000.0, 15000.0);

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

  Widget _buildPlan(Size size) {
    _planSize = size;
    if (_marks == null) {
      // The marks are placed once the plan's size is known, during layout;
      // rebuild once so the readout below can show the wall width.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final marks = _marks ??= _initialMarks(size);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: photoImage(widget.imagePath),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CalibrationOverlayPainter(
                  pinA: marks[_Marker.a]!,
                  pinB: marks[_Marker.b]!,
                  wallStart: marks[_Marker.wallStart]!,
                  wallEnd: marks[_Marker.wallEnd]!,
                ),
              ),
            ),
          ),
          // Tapping the plan places the selected mark. A pointer shortcut
          // only: screen-reader and switch users use the arrow buttons.
          Positioned.fill(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (d) => _move(_selected, d.localPosition),
              ),
            ),
          ),
          for (final marker in _Marker.values)
            Positioned(
              left: marks[marker]!.dx - 24,
              top: marks[marker]!.dy - 24,
              child: Semantics(
                button: true,
                selected: marker == _selected,
                label: marker.label,
                hint: 'Select, then use the arrows below to move it',
                excludeSemantics: true,
                onTap: () => _select(marker),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _select(marker),
                  onPanStart: (_) => _select(marker),
                  onPanUpdate: (d) => _move(marker, _marks![marker]! + d.delta),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: _PinWidget(
                        label: marker.badge,
                        color: marker.color,
                        selected: marker == _selected,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallMm = _marks == null ? null : _wallMm;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Measure from the plan'),
        actions: [
          TextButton.icon(
            onPressed: _generate3D,
            icon: const Icon(Icons.view_in_ar_rounded, color: AppTheme.accent),
            label: const Text('View in 3D'),
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
                      '1. Mark a length you know, like a 900 mm door (A–B).\n'
                      '2. Mark the two ends of the kitchen wall (1–2).',
                      style: context.textTheme.labelSmall
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            // ── The plan: pinch to zoom; the marks zoom with it ──────────
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) => InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: _buildPlan(constraints.biggest),
                  ),
                ),
              ),
            ),

            // ── Bottom panel ──────────────────────────────────────────────
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Real distance between A and B
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _dimensionController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              style: context.textTheme.bodySmall
                                  ?.copyWith(color: context.colors.onSurface),
                              decoration: InputDecoration(
                                labelText: 'Length A–B (mm)',
                                labelStyle: context.textTheme.labelSmall
                                    ?.copyWith(
                                        color: context.colors.onSurfaceVariant),
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

                          // The measured wall
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceRaised,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Wall width (1–2)',
                                    style: context.textTheme.labelSmall
                                        ?.copyWith(
                                            color: context
                                                .colors.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    wallMm == null
                                        ? 'Enter A–B'
                                        : '${wallMm.round()} mm',
                                    style: context.textTheme.labelLarge
                                        ?.copyWith(
                                            color: context.colors.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Pick a mark, then tap the plan or use the arrows.',
                        style: context.textTheme.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final marker in _Marker.values)
                            ChoiceChip(
                              label: Text(marker.label),
                              showCheckmark: false,
                              selected: marker == _selected,
                              onSelected: (_) => _select(marker),
                            ),
                          NudgeButtons(
                            labels: NudgeLabels(
                              left: 'Move ${_selected.inSentence} left',
                              right: 'Move ${_selected.inSentence} right',
                              up: 'Move ${_selected.inSentence} up',
                              down: 'Move ${_selected.inSentence} down',
                            ),
                            onNudge: _nudge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Button to extrude into 3D
                      SizedBox(
                        width: double.infinity,
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

class _PinWidget extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;

  const _PinWidget({
    required this.label,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final dark = color.computeLuminance() < 0.3;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppTheme.danger : Colors.white,
          width: selected ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: context.textTheme.labelMedium
              ?.copyWith(color: dark ? Colors.white : const Color(0xFF0F172A)),
        ),
      ),
    );
  }
}

class _CalibrationOverlayPainter extends CustomPainter {
  final Offset pinA;
  final Offset pinB;
  final Offset wallStart;
  final Offset wallEnd;

  _CalibrationOverlayPainter({
    required this.pinA,
    required this.pinB,
    required this.wallStart,
    required this.wallEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The known length, A–B
    canvas.drawLine(
      pinA,
      pinB,
      Paint()
        ..color = const Color(0xFF00A3B5)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // The wall being measured, 1–2
    canvas.drawLine(
      wallStart,
      wallEnd,
      Paint()
        ..color = AppTheme.accent.withValues(alpha: 0.85)
        ..strokeWidth = 5.0
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CalibrationOverlayPainter oldDelegate) =>
      oldDelegate.pinA != pinA ||
      oldDelegate.pinB != pinB ||
      oldDelegate.wallStart != wallStart ||
      oldDelegate.wallEnd != wallEnd;
}
