import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shared/theme.dart';

/// What the "Pictures" button shows: the design as pictures to show the
/// client right there, and two ways to send them on.
class PicturesSheet extends StatefulWidget {
  const PicturesSheet({
    super.key,
    required this.pictures,
    required this.onSendWhatsApp,
    required this.onOpenToSave,
  });

  /// The pictures' bytes, front view first.
  final List<Uint8List> pictures;

  /// Both return once the office has the pictures (or has failed to).
  final Future<void> Function() onSendWhatsApp;
  final Future<void> Function() onOpenToSave;

  static Future<void> show(
    BuildContext context, {
    required List<Uint8List> pictures,
    required Future<void> Function() onSendWhatsApp,
    required Future<void> Function() onOpenToSave,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => PicturesSheet(
          pictures: pictures,
          onSendWhatsApp: onSendWhatsApp,
          onOpenToSave: onOpenToSave,
        ),
      );

  @override
  State<PicturesSheet> createState() => _PicturesSheetState();
}

const _labels = ['Front view of the design', 'Angled view of the design'];

class _PicturesSheetState extends State<PicturesSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pictures of the design',
                style: context.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Show them to the client now, or send them a link.',
              style: context.textTheme.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < widget.pictures.length; i++) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  widget.pictures[i],
                  fit: BoxFit.cover,
                  semanticLabel: _labels[i % _labels.length],
                  gaplessPlayback: true,
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(widget.onSendWhatsApp),
                  icon: const Icon(Icons.chat_outlined, size: 18),
                  label: const Text('Send on WhatsApp'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(widget.onOpenToSave),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open to save'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
