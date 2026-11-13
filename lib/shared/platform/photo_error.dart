import 'package:flutter/material.dart';

/// Shown in place of a photo that can't be opened (moved, deleted, or a
/// browser link that expired after a page reload).
class PhotoError extends StatelessWidget {
  const PhotoError({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          "Couldn't open this photo. Go back and take or choose it again.",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
