import 'dart:ui' show Offset;

/// What the wall-corner model found on a photo.
class CornerSuggestion {
  /// [corners]: fractions of the photo (top-left, top-right, bottom-right,
  /// bottom-left), or null if the wall couldn't be found with confidence.
  const CornerSuggestion(this.corners) : available = true;

  /// No model on this device (the browser, or a build without the model
  /// file): nothing to say about the photo.
  const CornerSuggestion.unavailable()
      : corners = null,
        available = false;

  final List<Offset>? corners;
  final bool available;
}

/// Finds the wall in front of the camera on a photo.
abstract class CornerSuggester {
  Future<CornerSuggestion> suggest(String imagePath);
}
