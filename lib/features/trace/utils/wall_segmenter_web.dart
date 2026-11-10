import 'opening_finder.dart';
import 'wall_segmenter_api.dart';

export 'wall_segmenter_api.dart';

/// In the browser windows and doors are placed by hand.
class DeviceWallSegmenter implements WallSegmenter {
  const DeviceWallSegmenter();

  @override
  Future<WallLabels?> labels(String imagePath) async => null;
}
