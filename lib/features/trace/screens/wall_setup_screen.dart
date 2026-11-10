import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wall_provider.dart';
import '../utils/homography.dart';
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

/// Wall size, after the wall has been traced on the photo: the width comes
/// filled in from the traced corners' proportions, to be confirmed with a
/// tape. Returns true to the trace screen once a size is set.
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

  /// The width the traced corners suggest, if the size wasn't set yet.
  double? _estimatedWidth;

  @override
  void initState() {
    super.initState();
    final wall = ref.read(wallSetupProvider);
    var width = wall.widthMm;
    final shape = _shape(wall);
    if (!wall.sizeFromTape && shape != null) {
      width = (wall.heightMm * shape.aspect / 10).roundToDouble() * 10;
      _estimatedWidth = width;
    }
    _widthCtrl = TextEditingController(text: width.round().toString());
    _heightCtrl =
        TextEditingController(text: wall.heightMm.round().toString());
    _widthCtrl.addListener(_rebuild);
    _heightCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

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

    ref.read(wallSetupProvider.notifier).updateDimensions(
          widthMm: double.parse(_widthCtrl.text),
          heightMm: double.parse(_heightCtrl.text),
          // Wall thickness only shapes the 3D wall; a standard brick wall.
          depthMm: ref.read(wallSetupProvider).depthMm,
        );
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final shape = _shape(ref.watch(wallSetupProvider));
    final estimate = _estimatedWidth;
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
                      'Measure the wall',
                      style: context.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      estimate != null
                          ? 'From the photo, this wall is about ${_mm(estimate)} mm '
                              'wide if the ceiling is '
                              '${_mm(double.tryParse(_heightCtrl.text) ?? 0)} mm '
                              'high. Check both with a tape and correct them.'
                          : 'Use a tape: the width from corner to corner, and '
                              'the height from floor to ceiling. Type them in '
                              'millimetres.',
                      style: context.textTheme.bodyMedium
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
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

  const _DimField({
    required this.controller,
    required this.label,
    required this.what,
    required this.hint,
    required this.icon,
    required this.min,
    required this.max,
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
    );
  }
}
