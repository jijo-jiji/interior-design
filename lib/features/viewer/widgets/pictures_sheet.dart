import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../utils/design_pictures.dart';

/// What the "Pictures" button shows: the design as pictures to show the
/// client right there, a slower "realistic render" of the same views, and
/// two ways to send them on.
class PicturesSheet extends StatefulWidget {
  const PicturesSheet({
    super.key,
    required this.initial,
    required this.initialRender,
    this.initialStats,
    required this.progress,
    required this.onRender,
    required this.onCancelRender,
    required this.onSendWhatsApp,
    required this.onOpenToSave,
  });

  /// The pictures as data URLs, front view first.
  final List<String> initial;

  /// [initial] are already this kind of render (null: quick pictures).
  final RenderEngine? initialRender;

  /// What that render reached, if it was a true-lighting one.
  final RenderStats? initialStats;

  /// How far a render has got (0 to 1), or null when none is running.
  final ValueListenable<double?> progress;

  /// Makes the render asked for; null if it was cancelled or failed.
  final Future<RenderResult?> Function(RenderRequest request) onRender;
  final VoidCallback onCancelRender;

  /// Both return once the office has the pictures (or has failed to). They
  /// are given the pictures on show now.
  final Future<void> Function(List<String> images) onSendWhatsApp;
  final Future<void> Function(List<String> images) onOpenToSave;

  @override
  State<PicturesSheet> createState() => _PicturesSheetState();
}

const _labels = ['Front view of the design', 'Angled view of the design'];

class _PicturesSheetState extends State<PicturesSheet> {
  late List<String> _images = widget.initial;
  late RenderEngine? _rendered = widget.initialRender;
  late RenderStats? _stats = widget.initialStats;
  bool _fellBack = false;
  RenderQuality _quality = RenderQuality.standard;
  bool _sending = false;
  bool _rendering = false;

  Future<void> _send(Future<void> Function(List<String>) action) async {
    setState(() => _sending = true);
    try {
      await action(_images);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _render(RenderRequest request) async {
    setState(() => _rendering = true);
    try {
      final made = await widget.onRender(request);
      if (made != null && mounted) {
        setState(() {
          _images = made.images;
          _rendered = made.engine;
          _fellBack = made.fellBack;
          _stats = made.stats;
        });
      }
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = [
      for (final image in _images)
        if (DesignPictures.decode(image) case final picture?) picture,
    ];
    return PopScope(
      // Not while a render is running: Cancel it first.
      canPop: !_rendering,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Pictures of the design',
                        style: context.textTheme.titleMedium),
                  ),
                  if (_rendered != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.successDim,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                          _rendered == RenderEngine.path
                              ? 'True-lighting render'
                              : 'Realistic render',
                          style: context.textTheme.labelSmall
                              ?.copyWith(color: AppTheme.success)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Show them to the client now, or send them a link.',
                style: context.textTheme.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              if (_rendered == RenderEngine.path && _stats != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${_stats!.summary}\nMore samples make a cleaner picture.',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
              if (_fellBack) ...[
                const SizedBox(height: 8),
                Text(
                  "This device can't do true lighting, so the realistic "
                  'render was made instead.',
                  style: context.textTheme.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              for (var i = 0; i < bytes.length; i++) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    bytes[i],
                    fit: BoxFit.cover,
                    semanticLabel: _labels[i % _labels.length],
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              if (_rendering)
                _RenderProgress(
                  progress: widget.progress,
                  onCancel: widget.onCancelRender,
                )
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _sending ? null : () => _send(widget.onSendWhatsApp),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('Send on WhatsApp'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _sending ? null : () => _send(widget.onOpenToSave),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open to save'),
                    ),
                    if (_sending)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (_rendered == null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _sending
                        ? null
                        : () => _render(const RenderRequest(RenderEngine.sky)),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Make a realistic render'),
                  ),
                  Text(
                    'Softer light and shadows. Takes a little while; the '
                    'quote uses it if the design has not changed.',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _sending
                        ? null
                        : () =>
                            _render(RenderRequest(RenderEngine.path, _quality)),
                    icon: const Icon(Icons.wb_incandescent_outlined, size: 18),
                    label: const Text('Make a true-lighting render'),
                  ),
                  Text(
                    'Light bounces off the oak, the walls and the floor, '
                    'like in a photograph. Slower, and needs a recent '
                    'device. You can cancel.',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Standard'),
                        selected: _quality == RenderQuality.standard,
                        onSelected: (_) =>
                            setState(() => _quality = RenderQuality.standard),
                      ),
                      ChoiceChip(
                        label: const Text('Fine detail (slower)'),
                        selected: _quality == RenderQuality.fine,
                        onSelected: (_) =>
                            setState(() => _quality = RenderQuality.fine),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RenderProgress extends StatelessWidget {
  const _RenderProgress({required this.progress, required this.onCancel});

  final ValueListenable<double?> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final percent = value == null ? null : (value * 100).round();
        final text = percent == null ? 'Rendering…' : 'Rendering… $percent%';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: text,
              child: LinearProgressIndicator(value: value, minHeight: 6),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(text, style: context.textTheme.bodyMedium)),
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
              ],
            ),
          ],
        );
      },
    );
  }
}
