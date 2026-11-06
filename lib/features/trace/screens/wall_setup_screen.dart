import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wall_provider.dart';
import '../../../shared/theme.dart';

/// Plausible ranges, to catch a typo or a measurement in cm or m.
const double kMinWallWidthMm = 500, kMaxWallWidthMm = 15000;
const double kMinWallHeightMm = 1800, kMaxWallHeightMm = 5000;

/// Wall size: the salesperson types the wall's width and height from a tape
/// measure. The photo is then lined up against these on the next screen.
class WallSetupScreen extends ConsumerStatefulWidget {
  final String imagePath;
  const WallSetupScreen({super.key, required this.imagePath});

  @override
  ConsumerState<WallSetupScreen> createState() => _WallSetupScreenState();
}

class _WallSetupScreenState extends ConsumerState<WallSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _widthCtrl = TextEditingController(text: '4000');
  final _heightCtrl = TextEditingController(text: '2700');

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
    // Clear any previous obstacles
    ref.read(obstaclesProvider.notifier).clear();

    context.push('/trace', extra: widget.imagePath);
  }

  @override
  Widget build(BuildContext context) {
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
                      'Use a tape: the width from corner to corner, and the '
                      'height from floor to ceiling. Type them in millimetres.',
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _proceed,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Next: line up the photo'),
                ),
              ),
            ],
          ),
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
