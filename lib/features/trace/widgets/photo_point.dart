import 'package:flutter/material.dart';

/// A point to place exactly on a photo: a ring with a crosshair, 48 dp to
/// grab. Dragged, or selected and moved with arrow buttons elsewhere.
class PointHandle extends StatelessWidget {
  const PointHandle({
    super.key,
    required this.label,
    required this.at,
    required this.selected,
    required this.onSelect,
    required this.onDrag,
    required this.onDragEnd,
  });

  /// What the point is, for screen readers: "Top left corner".
  final String label;
  final Offset at;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  static const double _hit = 48;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: at.dx - _hit / 2,
      top: at.dy - _hit / 2,
      width: _hit,
      height: _hit,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        hint: selected
            ? 'Use the arrows below the photo to move it'
            : 'Select, then use the arrows below the photo to move it',
        excludeSemantics: true,
        onTap: onSelect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelect,
          onPanStart: (_) => onSelect(),
          onPanUpdate: (d) => onDrag(d.delta),
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: CustomPaint(
            painter: _RingPainter(selected: selected),
          ),
        ),
      ),
    );
  }
}

/// The points' colour on the photo, and the selected one's.
const Color kPointColor = Color(0xFF68D391);
const Color _pointSelected = Colors.white;

class _RingPainter extends CustomPainter {
  _RingPainter({required this.selected});

  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final color = selected ? _pointSelected : kPointColor;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 5 : 4;
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 2;
    canvas.drawCircle(c, 13, shadow);
    canvas.drawCircle(c, 13, ring);
    // A crosshair with a gap at the centre, so the point itself stays clear.
    final hair = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (final d in const [Offset(1, 0), Offset(0, 1)]) {
      canvas.drawLine(c + d * 4, c + d * 11, hair);
      canvas.drawLine(c - d * 4, c - d * 11, hair);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.selected != selected;
}

/// While a point is dragged, the photo under it, magnified, above the
/// finger (below it near the top of the photo), so it lands exactly on the
/// corner.
class PhotoLoupe extends StatelessWidget {
  const PhotoLoupe({super.key, required this.at, required this.canvas});

  final Offset at;
  final Size canvas;

  static const double _size = 116;
  static const double _lift = 100;

  @override
  Widget build(BuildContext context) {
    final above = at.dy - _lift - _size / 2 >= 0;
    final centre = Offset(
      at.dx.clamp(_size / 2, canvas.width - _size / 2).toDouble(),
      at.dy + (above ? -_lift : _lift),
    );
    return Positioned(
      left: centre.dx - _size / 2,
      top: centre.dy - _size / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size(_size, _size),
          magnificationScale: 2.5,
          focalPointOffset: at - centre,
          decoration: const MagnifierDecoration(
            shape: CircleBorder(
              side: BorderSide(color: Colors.white, width: 2),
            ),
            shadows: [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
      ),
    );
  }
}
