import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wall_provider.dart';
import '../utils/homography.dart';
import '../utils/opening_finder.dart' show WallLabels;
import '../utils/wall_size.dart';
import '../../../shared/theme.dart';

/// Plausible ranges, to catch a typo or a measurement in cm or m.
const double kMinWallWidthMm = 500, kMaxWallWidthMm = 15000;
const double kMinWallHeightMm = 1800, kMaxWallHeightMm = 5000;

/// How far the wall's shape on the photo may differ from the typed size
/// before the screen says so: tighter when the photo says what lens took it.
const double kShapeToleranceKnownLens = 0.06;
const double kShapeToleranceAssumedLens = 0.10;

String _mm(double mm) =>
    mm.round().toString().replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');

/// Wall size, after the wall has been traced on the photo. It comes filled
/// in from the photo: the traced corners give the proportions, and the
/// worktop or a door the scale (wall_size.dart). The salesperson checks it;
/// typing either measurement works the other out from the photo. Returns
/// true to the trace screen once a size is set.
class WallSetupScreen extends ConsumerStatefulWidget {
  final String imagePath;
  const WallSetupScreen({super.key, required this.imagePath});

  @override
  ConsumerState<WallSetupScreen> createState() => _WallSetupScreenState();
}

class _WallSetupScreenState extends ConsumerState<WallSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;

  /// The size worked out from the photo, if it wasn't set yet.
  WallSizeEstimate? _estimate;

  /// Which measurements the salesperson typed.
  bool _typedWidth = false, _typedHeight = false;

  @override
  void initState() {
    super.initState();
    final wall = ref.read(wallSetupProvider);
    var (width, height) = (wall.widthMm, wall.heightMm);
    final shape = _shape(wall);
    if (!wall.sizeFromTape && shape != null) {
      final estimate = _estimateFrom(
          wall, shape, ref.read(wallLabelsProvider(widget.imagePath)).valueOrNull);
      (width, height) = (estimate.widthMm, estimate.heightMm);
      _estimate = estimate;
      // The labels may still be on their way: a better estimate when they
      // come, unless a measurement has been typed by then.
      ref.listenManual<AsyncValue<WallLabels?>>(
          wallLabelsProvider(widget.imagePath), (_, next) {
        final labels = next.valueOrNull;
        if (labels == null || _typedWidth || _typedHeight || !mounted) return;
        final w = ref.read(wallSetupProvider);
        final s = _shape(w);
        if (s == null) return;
        final better = _estimateFrom(w, s, labels);
        setState(() {
          _estimate = better;
          _widthCtrl.text = better.widthMm.round().toString();
          _heightCtrl.text = better.heightMm.round().toString();
        });
      });
    }
    _widthCtrl = TextEditingController(text: width.round().toString());
    _heightCtrl = TextEditingController(text: height.round().toString());
    _widthCtrl.addListener(_rebuild);
    _heightCtrl.addListener(_rebuild);
  }

  static WallSizeEstimate _estimateFrom(
          WallSetup wall, WallShapeEstimate shape, WallLabels? labels) =>
      estimateWallSize(shape.aspect,
          labels: labels, wallCorners: wall.wallCorners);

  void _rebuild() => setState(() {});

  /// One measurement typed: the other follows from the photo's proportions,
  /// unless it was typed too.
  void _typed({required bool width}) {
    if (width) {
      _typedWidth = true;
    } else {
      _typedHeight = true;
    }
    final shape = _shape(ref.read(wallSetupProvider));
    if (shape == null) return;
    // Only once what's typed is a plausible size: halfway through typing
    // "2860" the other box must not flash 0, 10, 190 ...
    if (width && !_typedHeight) {
      final w = double.tryParse(_widthCtrl.text);
      if (w != null && w >= kMinWallWidthMm && w <= kMaxWallWidthMm) {
        _heightCtrl.text = ((w / shape.aspect / 10).round() * 10).toString();
      }
    } else if (!width && !_typedWidth) {
      final h = double.tryParse(_heightCtrl.text);
      if (h != null && h >= kMinWallHeightMm && h <= kMaxWallHeightMm) {
        _widthCtrl.text = ((h * shape.aspect / 10).round() * 10).toString();
      }
    }
  }

  /// The wall's proportions on the photo, once its corners are traced.
  static WallShapeEstimate? _shape(WallSetup wall) =>
      listEquals(wall.corners, kStartCorners) ? null : wall.photoShape;

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (!_formKey.currentState!.validate()) return;

    final estimate = _estimate;
    ref.read(wallSetupProvider.notifier).updateDimensions(
          widthMm: double.parse(_widthCtrl.text),
          heightMm: double.parse(_heightCtrl.text),
          // Wall thickness only shapes the 3D wall; a standard brick wall.
          depthMm: ref.read(wallSetupProvider).depthMm,
          sizeFrom: _typedWidth || _typedHeight
              ? 'typed'
              : estimate?.cue.name,
        );
    context.pop(true);
  }

  /// What the screen says about the numbers in the boxes.
  String _explanation(WallSetup wall) {
    const fix = 'If a size looks wrong, measure it and type it in: the other '
        'follows from the photo.';
    final shape = _shape(wall);
    if (_typedWidth != _typedHeight && shape != null) {
      return _typedWidth
          ? 'Height worked out from your width and the photo.'
          : 'Width worked out from your height and the photo.';
    }
    final estimate = _estimate;
    if (estimate != null && !_typedWidth && !_typedHeight) {
      return switch (estimate.cue) {
        SizeCue.worktop => 'Measured from the photo, using the worktop '
            '(about ${_mm(kWorktopMm)} mm high) as a guide. $fix',
        SizeCue.door => 'Measured from the photo, using the door on this wall '
            '(about ${_mm(kDoorTopMm)} mm high) as a guide. $fix',
        SizeCue.assumed => 'From the photo\'s proportions, taking the usual '
            '${_mm(kAssumedCeilingMm)} mm ceiling. $fix',
      };
    }
    if (shape != null) {
      return 'Type a measurement to change it: the other follows from the '
          'photo.';
    }
    return 'Use a tape: the width from corner to corner, and the height from '
        'floor to ceiling. Type them in millimetres.';
  }

  @override
  Widget build(BuildContext context) {
    final wall = ref.watch(wallSetupProvider);
    final shape = _shape(wall);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wall size'),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.straighten_rounded,
                      size: 48,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      shape != null ? 'Wall size from the photo' : 'Measure the wall',
                      style: context.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _explanation(wall),
                        style: context.textTheme.bodyMedium
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _DimField(
                controller: _widthCtrl,
                label: 'Wall width',
                what: 'wall width',
                hint: 'e.g. 3600',
                icon: Icons.width_normal_rounded,
                min: kMinWallWidthMm,
                max: kMaxWallWidthMm,
                onTyped: () => _typed(width: true),
              ),
              const SizedBox(height: 16),
              _DimField(
                controller: _heightCtrl,
                label: 'Ceiling height',
                what: 'ceiling height',
                hint: 'e.g. 2700',
                icon: Icons.height_rounded,
                min: kMinWallHeightMm,
                max: kMaxWallHeightMm,
                onTyped: () => _typed(width: false),
              ),
              if (shape != null)
                _SizeCheck(
                  shape: shape,
                  widthMm: double.tryParse(_widthCtrl.text),
                  heightMm: double.tryParse(_heightCtrl.text),
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _proceed,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Next: windows & doors'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speaks up when the typed size disagrees with the traced wall's
/// proportions: catches a misread tape, or a corner on the wrong wall.
/// Silent otherwise, and never a tick: four points always fit some
/// rectangle in perspective, so matching proportions don't prove the
/// corners (the lean check on the next screen does that).
class _SizeCheck extends StatelessWidget {
  const _SizeCheck({
    required this.shape,
    required this.widthMm,
    required this.heightMm,
  });

  final WallShapeEstimate shape;
  final double? widthMm;
  final double? heightMm;

  @override
  Widget build(BuildContext context) {
    final w = widthMm, h = heightMm;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return const SizedBox.shrink();
    }
    final off = shape.aspect / (w / h) - 1;
    final tolerance = shape.focalSource == FocalSource.assumed
        ? kShapeToleranceAssumedLens
        : kShapeToleranceKnownLens;
    if (off.abs() <= tolerance) return const SizedBox.shrink();
    final looksWide = (shape.aspect * h / 10).round() * 10.0;
    const color = AppTheme.danger;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'On the photo this wall looks about ${_mm(looksWide)} mm wide '
                'for a ${_mm(h)} mm height, not ${_mm(w)}. Check the tape, '
                'or the corners.',
                style: context.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DimField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  /// Used mid-sentence in error messages: "wall width".
  final String what;
  final String hint;
  final IconData icon;
  final double min;
  final double max;

  /// Called when the salesperson types in the field (not when the screen
  /// fills it).
  final VoidCallback onTyped;

  const _DimField({
    required this.controller,
    required this.label,
    required this.what,
    required this.hint,
    required this.icon,
    required this.min,
    required this.max,
    required this.onTyped,
  });

  String? _validate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter the $what in mm';
    final mm = double.tryParse(text);
    if (mm == null) return 'Numbers only, in mm';
    if (mm < min) {
      return 'That looks small for a $what. Is it in mm? '
          '(${min.round()}–${max.round()} mm)';
    }
    if (mm > max) {
      return 'That looks big for a $what. Is it in mm? '
          '(${min.round()}–${max.round()} mm)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary),
        suffixText: 'mm',
        errorMaxLines: 3,
      ),
      validator: _validate,
      onChanged: (_) => onTyped(),
    );
  }
}
