import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wall_provider.dart';
import '../utils/reference_card.dart';
import '../widgets/photo_point.dart';
import 'trace_screen.dart' show photoRectIn;
import 'wall_setup_screen.dart'
    show kMaxWallHeightMm, kMaxWallWidthMm, kMinWallHeightMm, kMinWallWidthMm;
import '../../../shared/platform/photo_error.dart';
import '../../../shared/platform/photo_image.dart';
import '../../../shared/theme.dart';
import '../../../shared/widgets/nudge_buttons.dart';

/// Each arrow tap moves a dot this much of the photo: finer than the wall's
/// corners, since the sheet is small on the photo.
const double kSheetNudge = 0.001;

/// The panel under the photo, before large text grows it.
const double _panelHeight = 260;
const double _maxPanelShare = 0.5;

String _mm(double mm) => ((mm / 10).round() * 10)
    .toString()
    .replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');

/// The four corners of an A4 sheet taped on the wall, marked on the photo:
/// the wall's size is then measured from it instead of guessed. Opened from
/// the wall-size screen, once the wall's corners are traced. Returns true
/// once the sheet is set (or taken away).
class SheetScreen extends ConsumerStatefulWidget {
  const SheetScreen({super.key, required this.imagePath});

  final String imagePath;

  @override
  ConsumerState<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends ConsumerState<SheetScreen> {
  late List<Offset> _dots;
  WallCorner _selected = WallCorner.topLeft;

  /// While a dot is dragged: where it is on the canvas, for the loupe.
  Offset? _dragAt;

  late final ImageProvider _photo = photoProvider(widget.imagePath);

  @override
  void initState() {
    super.initState();
    final wall = ref.read(wallSetupProvider);
    _dots = wall.sheet ??
        startSheet(
          wallCorners: wall.wallCorners,
          aspect: wall.photoShape?.aspect ?? wall.widthMm / wall.heightMm,
          heightMm: wall.heightMm,
        );
  }

  /// Moves a dot to [at] (fractions of the photo), keeping it on the photo
  /// and the sheet a proper four-sided shape.
  void _move(WallCorner corner, Offset at) {
    final next = [..._dots];
    next[corner.index] =
        Offset(at.dx.clamp(0.0, 1.0), at.dy.clamp(0.0, 1.0));
    if (!isConvexQuad(next)) return;
    setState(() => _dots = next);
  }

  void _select(WallCorner corner) {
    if (_selected == corner) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = corner);
  }

  SheetMeasure? _measure(WallSetup wall) {
    final shape = wall.photoShape, size = wall.photoSize;
    if (shape == null || size == null) return null;
    return measureSheet(
        sheet: _dots,
        wallCorners: wall.wallCorners,
        aspect: shape.aspect,
        photo: size);
  }

  static bool _plausible(SheetMeasure m) =>
      m.widthMm >= kMinWallWidthMm &&
      m.widthMm <= kMaxWallWidthMm &&
      m.heightMm >= kMinWallHeightMm &&
      m.heightMm <= kMaxWallHeightMm;

  void _use() {
    ref.read(wallSetupProvider.notifier).setSheet(_dots);
    context.pop(true);
  }

  void _noSheet() {
    ref.read(wallSetupProvider.notifier).setSheet(null);
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wall = ref.watch(wallSetupProvider);
    final measure = _measure(wall);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: context.colors.onPrimary,
        titleTextStyle: context.textTheme.titleMedium
            ?.copyWith(color: context.colors.onPrimary),
        title: const Text('Mark the A4 sheet'),
        leading: const BackButton(),
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => _photoView(c.biggest, wall),
            ),
          ),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(_panelHeight).clamp(
                _panelHeight, MediaQuery.sizeOf(context).height * _maxPanelShare),
            child: Material(
              color: AppTheme.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _panel(context, wall, measure),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoView(Size canvas, WallSetup wall) {
    final rect = photoRectIn(canvas, wall.photoSize);
    Offset toCanvas(Offset f) =>
        rect.topLeft + Offset(f.dx * rect.width, f.dy * rect.height);
    Offset toPhoto(Offset p) => Offset(
        (p.dx - rect.left) / rect.width, (p.dy - rect.top) / rect.height);
    final dots = [for (final d in _dots) toCanvas(d)];
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fromRect(
          rect: rect,
          child: Image(
            image: _photo,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const PhotoError(),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _SheetPainter(
              sheet: dots,
              wall: [for (final c in wall.wallCorners) toCanvas(c)],
            ),
            size: Size.infinite,
          ),
        ),
        // Pointer shortcut only: screen-reader and switch users move the
        // dots with the arrow buttons instead.
        Positioned.fill(
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                HapticFeedback.selectionClick();
                _move(_selected, toPhoto(d.localPosition));
              },
            ),
          ),
        ),
        for (final corner in WallCorner.values)
          PointHandle(
            label: 'Sheet’s ${corner.label.toLowerCase()} corner',
            at: dots[corner.index],
            selected: corner == _selected,
            onSelect: () => _select(corner),
            onDrag: (delta) {
              _move(
                corner,
                _dots[corner.index] +
                    Offset(delta.dx / rect.width, delta.dy / rect.height),
              );
              setState(() => _dragAt = toCanvas(_dots[corner.index]));
            },
            onDragEnd: () => setState(() => _dragAt = null),
          ),
        if (_dragAt case final at?) PhotoLoupe(at: at, canvas: canvas),
      ],
    );
  }

  Widget _panel(BuildContext context, WallSetup wall, SheetMeasure? m) {
    final muted = context.textTheme.bodySmall
        ?.copyWith(color: context.colors.onSurfaceVariant);
    final name = _selected.label.toLowerCase();
    final usable = m != null && m.onWall && _plausible(m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text('The sheet’s corners', style: context.textTheme.titleSmall),
            ElevatedButton.icon(
              onPressed: usable ? _use : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Use this sheet'),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Put a dot on each corner of the A4 sheet taped on the wall. It must '
          'be flat on the wall itself, not on a cabinet. Drag a dot, or pick '
          'one and tap the photo.',
          style: muted,
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          child: _Readout(measure: m, plausible: m != null && _plausible(m)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final corner in WallCorner.values)
              ChoiceChip(
                label: Text(corner.label),
                showCheckmark: false,
                selected: corner == _selected,
                onSelected: (_) => _select(corner),
              ),
            NudgeButtons(
              labels: NudgeLabels(
                left: 'Move sheet’s $name corner left',
                right: 'Move sheet’s $name corner right',
                up: 'Move sheet’s $name corner up',
                down: 'Move sheet’s $name corner down',
              ),
              onNudge: (dx, dy) => _move(
                  _selected,
                  _dots[_selected.index] +
                      Offset(dx * kSheetNudge, dy * kSheetNudge)),
            ),
          ],
        ),
        if (wall.sheet != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: _noSheet,
              child: const Text('There’s no sheet on this wall'),
            ),
          ),
      ],
    );
  }
}

/// What the sheet, as marked, makes of the wall, and anything that looks
/// wrong with it.
class _Readout extends StatelessWidget {
  const _Readout({required this.measure, required this.plausible});

  final SheetMeasure? measure;
  final bool plausible;

  @override
  Widget build(BuildContext context) {
    final m = measure;
    final notes = <String>[
      if (m == null) 'Trace the wall’s corners first.',
      if (m != null && !m.onWall)
        'Part of the sheet is off the wall you traced. It must be on that '
            'wall itself.',
      if (m != null && m.onWall && !plausible)
        'That isn’t a likely wall size. Check the dots.',
      if (m != null && m.onWall && plausible && m.shapeLooksOff)
        'This doesn’t look like an A4 sheet on the wall. Check its four dots, '
            'and the wall’s corners.',
      if (m != null && m.onWall && plausible && m.small)
        'The sheet is small on this photo, so the size may be a few per cent '
            'off. A photo from closer measures better.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (m != null && m.onWall && plausible)
          Text(
            'From this sheet the wall is about ${_mm(m.widthMm)} mm wide and '
            '${_mm(m.heightMm)} mm high.',
            style: context.textTheme.bodyMedium,
          ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(note,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.danger)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The traced wall, faintly, and the sheet's outline.
class _SheetPainter extends CustomPainter {
  _SheetPainter({required this.sheet, required this.wall});

  final List<Offset> sheet, wall;

  @override
  void paint(Canvas canvas, Size size) {
    Path shape(List<Offset> p) => Path()..addPolygon(p, true);
    canvas.drawPath(
        shape(wall),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    canvas.drawPath(
        shape(sheet),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    canvas.drawPath(
        shape(sheet),
        Paint()
          ..color = kPointColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_SheetPainter old) => old.sheet != sheet || old.wall != wall;
}
