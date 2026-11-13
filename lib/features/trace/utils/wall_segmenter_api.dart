import 'opening_finder.dart';

/// Labels every part of a photo (wall, window, door, cabinet, ...).
abstract class WallSegmenter {
  /// Null when there's no model here, or the photo can't be read.
  Future<WallLabels?> labels(String imagePath);
}
