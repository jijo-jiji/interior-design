import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wall_provider.dart';
import '../../../shared/theme.dart';

/// Wall Setup Screen — user enters real-world dimensions before tracing.
/// Computes scale ratio on the fly and stores it in WallSetupProvider.
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
  final _depthCtrl = TextEditingController(text: '150');

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _depthCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (!_formKey.currentState!.validate()) return;

    ref.read(wallSetupProvider.notifier).updateDimensions(
          widthMm: double.parse(_widthCtrl.text),
          heightMm: double.parse(_heightCtrl.text),
          depthMm: double.parse(_depthCtrl.text),
        );
    // Clear any previous obstacles
    ref.read(obstaclesProvider.notifier).clear();

    context.push('/trace', extra: widget.imagePath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wall Dimensions'),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero illustration ──────────────────────────────────────
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
                      'Enter real-world wall dimensions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These measurements set the pixel-to-mm ratio.\nEvery box you draw will be mathematically precise.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Inputs ────────────────────────────────────────────────
              _DimField(
                controller: _widthCtrl,
                label: 'Wall Width',
                hint: 'e.g. 4000',
                icon: Icons.width_normal_rounded,
              ),
              const SizedBox(height: 16),
              _DimField(
                controller: _heightCtrl,
                label: 'Wall Height',
                hint: 'e.g. 2700',
                icon: Icons.height_rounded,
              ),
              const SizedBox(height: 16),
              _DimField(
                controller: _depthCtrl,
                label: 'Wall Depth (thickness)',
                hint: 'e.g. 150',
                icon: Icons.view_in_ar_rounded,
              ),

              const SizedBox(height: 32),

              // ── Scale ratio preview ───────────────────────────────────
              ValueListenableBuilder(
                valueListenable: _widthCtrl,
                builder: (context, _, __) {
                  final w = double.tryParse(_widthCtrl.text);
                  final screenW =
                      MediaQuery.of(context).size.width - 48; // approx
                  if (w == null || w <= 0) return const SizedBox();
                  final ratio = screenW / w;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.accentDim,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate_rounded,
                            color: AppTheme.accent, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          '1 mm ≈ ${ratio.toStringAsFixed(3)} px  '
                          '(${screenW.toStringAsFixed(0)} px / ${w.toStringAsFixed(0)} mm)',
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _proceed,
                  icon: const Icon(Icons.draw_rounded),
                  label: const Text('Start Tracing'),
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
  final String hint;
  final IconData icon;

  const _DimField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: '$label (mm)',
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary),
        suffixText: 'mm',
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        final n = double.tryParse(v);
        if (n == null || n <= 0) return 'Enter a positive number';
        return null;
      },
    );
  }
}
