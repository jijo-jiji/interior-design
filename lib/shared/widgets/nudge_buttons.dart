import 'package:flutter/material.dart';

/// Labels for [NudgeButtons]. They are read out by TalkBack and shown as
/// tooltips, so name the result ("Wider"), not the arrow.
class NudgeLabels {
  const NudgeLabels({
    this.left = 'Move left',
    this.right = 'Move right',
    this.up = 'Move up',
    this.down = 'Move down',
  });

  final String left;
  final String right;
  final String up;
  final String down;
}

/// Arrow buttons that move or resize something one small step per tap.
///
/// This is the single-pointer, keyboard and switch-access alternative to
/// dragging (WCAG 2.5.7 and 2.1.1). [onNudge] gets -1, 0 or +1 per axis;
/// the caller picks the step size.
class NudgeButtons extends StatelessWidget {
  const NudgeButtons({
    super.key,
    required this.onNudge,
    this.horizontal = true,
    this.vertical = true,
    this.labels = const NudgeLabels(),
  });

  final void Function(int dx, int dy) onNudge;
  final bool horizontal;
  final bool vertical;
  final NudgeLabels labels;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, int dx, int dy) =>
        IconButton.outlined(
          tooltip: label,
          icon: Icon(icon),
          onPressed: () => onNudge(dx, dy),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (horizontal) button(Icons.arrow_back_rounded, labels.left, -1, 0),
        if (vertical) button(Icons.arrow_upward_rounded, labels.up, 0, -1),
        if (vertical) button(Icons.arrow_downward_rounded, labels.down, 0, 1),
        if (horizontal) button(Icons.arrow_forward_rounded, labels.right, 1, 0),
      ],
    );
  }
}
