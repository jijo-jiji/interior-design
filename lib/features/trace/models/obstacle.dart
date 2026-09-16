import 'package:uuid/uuid.dart';

enum ObstacleType { window, door }

/// Represents a traced obstacle (window or door) on the wall photo.
/// All pixel values are relative to the LayoutBuilder constraints.
class Obstacle {
  Obstacle({
    String? id,
    required this.type,
    required this.leftPx,
    required this.topPx,
    required this.widthPx,
    required this.heightPx,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final ObstacleType type;

  // Mutable — updated as the user drags / resizes
  double leftPx;
  double topPx;
  double widthPx;
  double heightPx;

  Obstacle copyWith({
    double? leftPx,
    double? topPx,
    double? widthPx,
    double? heightPx,
  }) =>
      Obstacle(
        id: id,
        type: type,
        leftPx: leftPx ?? this.leftPx,
        topPx: topPx ?? this.topPx,
        widthPx: widthPx ?? this.widthPx,
        heightPx: heightPx ?? this.heightPx,
      );

  String get label => type == ObstacleType.window ? 'Window' : 'Door';
}
