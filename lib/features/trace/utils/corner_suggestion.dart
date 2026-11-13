import 'dart:ui' show Offset;

import 'opening_finder.dart' show WallLabels;

/// How the corners were found.
enum CornerSource {
  /// From the flat patches of the depth map (corner_finder.dart): rooms
  /// whose walls show.
  planes,

  /// By our own corner model (learned_corners.dart): kitchens, where
  /// cabinets hide the walls' edges.
  learned,
}

/// What the wall-corner model found on a photo.
class CornerSuggestion {
  /// [corners]: fractions of the photo (top-left, top-right, bottom-right,
  /// bottom-left), or null if the wall couldn't be found with confidence.
  const CornerSuggestion(this.corners, {this.source, this.wallBottom})
      : available = true;

  /// No model on this device (the browser, or a build without the model
  /// file): nothing to say about the photo.
  const CornerSuggestion.unavailable()
      : corners = null,
        source = null,
        wallBottom = null,
        available = false;

  final List<Offset>? corners;
  final CornerSource? source;

  /// In a kitchen, where the wall really meets the floor behind the
  /// cabinets (bottom-right, bottom-left), when the bottom [corners] are on
  /// the cabinets' front instead: the wall is measured from these.
  final List<Offset>? wallBottom;
  final bool available;
}

/// Finds the wall in front of the camera on a photo.
abstract class CornerSuggester {
  /// [labels] fetches the photo's segmentation labels. It's called only if
  /// the depth map alone doesn't find the wall, for the corner model.
  Future<CornerSuggestion> suggest(String imagePath,
      {Future<WallLabels?> Function()? labels});
}
