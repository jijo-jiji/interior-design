import 'kitchen_catalog.dart';

enum KitchenShape { singleWall, lShape }

enum OpeningType { window, door }

/// A window or door on the main wall, in the same units as the scene payload.
class WallOpening {
  const WallOpening({
    required this.type,
    required this.leftMm,
    required this.floorMm,
    required this.widthMm,
    required this.heightMm,
  });

  final OpeningType type;
  final double leftMm;
  final double floorMm;
  final double widthMm;
  final double heightMm;

  double get rightMm => leftMm + widthMm;
  double get topMm => floorMm + heightMm;
  double get centerMm => leftMm + widthMm / 2;
}

/// The measured room, as captured by the trace / floor plan / template flows.
///
/// The main wall runs left to right from x = 0 to [mainWallMm]. For an
/// L-shape the return wall meets it at x = 0 and runs towards the viewer for
/// [returnWallMm], measured from the main wall's face.
class KitchenRoom {
  const KitchenRoom({
    required this.mainWallMm,
    required this.wallHeightMm,
    this.shape = KitchenShape.singleWall,
    this.returnWallMm = 0,
    this.openings = const [],
    this.notes = const [],
  });

  final double mainWallMm;
  final double wallHeightMm;
  final KitchenShape shape;
  final double returnWallMm;
  final List<WallOpening> openings;

  /// Anything about the input the generator could not use.
  final List<String> notes;

  /// Reads the scene payload the viewer receives (`wall` + `obstacles`).
  factory KitchenRoom.fromPayload(Map<String, dynamic> payload) {
    final wall = (payload['wall'] as Map?)?.cast<String, dynamic>() ?? const {};
    double num0(Object? v) => (v as num?)?.toDouble() ?? 0;

    final notes = <String>[];
    final shapeName = wall['shape'] as String? ?? 'singleWall';
    final returnMm = num0(wall['return_mm']);
    var shape = KitchenShape.singleWall;
    if (shapeName == 'lShape' && returnMm > 0) {
      shape = KitchenShape.lShape;
    } else if (shapeName != 'singleWall' && shapeName != 'lShape') {
      notes.add('$shapeName layouts are not generated yet; laid out the main wall only.');
    }

    final openings = <WallOpening>[];
    for (final raw in (payload['obstacles'] as List?) ?? const []) {
      final o = (raw as Map).cast<String, dynamic>();
      openings.add(WallOpening(
        type: o['type'] == 'door' ? OpeningType.door : OpeningType.window,
        leftMm: num0(o['distance_from_left_mm']),
        floorMm: num0(o['distance_from_floor_mm']),
        widthMm: num0(o['width_mm']),
        heightMm: num0(o['height_mm']),
      ));
    }

    return KitchenRoom(
      mainWallMm: num0(wall['width_mm']),
      wallHeightMm: wall['height_mm'] == null ? 2700 : num0(wall['height_mm']),
      shape: shape,
      returnWallMm: shape == KitchenShape.lShape ? returnMm : 0,
      openings: openings,
      notes: notes,
    );
  }
}

/// Which wall a module sits on.
enum RunWall { main, returnWall }

/// One generated module, positioned along its wall.
class PlacedModule {
  const PlacedModule({
    required this.id,
    required this.kind,
    required this.wall,
    required this.startMm,
    required this.widthMm,
    required this.heightMm,
    required this.depthMm,
    required this.mountMm,
  });

  final String id;
  final ModuleKind kind;
  final RunWall wall;

  /// Left edge along the main wall, or distance from the main wall's face
  /// along the return wall.
  final double startMm;
  final double widthMm;
  final double heightMm;
  final double depthMm;

  /// Height of the module's underside above the floor (0 for floor units).
  final double mountMm;

  double get endMm => startMm + widthMm;
  double get centerMm => startMm + widthMm / 2;
  bool get isWallMounted => kind == ModuleKind.wall || (kind == ModuleKind.filler && mountMm > 0);

  String get cabinetType {
    final w = widthMm.round();
    switch (kind) {
      case ModuleKind.base:
        return 'base_$w';
      case ModuleKind.drawer:
        return 'base_drawer_$w';
      case ModuleKind.sink:
        return 'base_sink_$w';
      case ModuleKind.hob:
        return 'base_hob_$w';
      case ModuleKind.tall:
        return 'tall_$w';
      case ModuleKind.corner:
        return 'corner_$w';
      case ModuleKind.wall:
        return 'wall_$w';
      case ModuleKind.filler:
        return mountMm > 0 ? 'filler_wall' : 'filler_base';
    }
  }

  String get label {
    final w = widthMm.round();
    switch (kind) {
      case ModuleKind.base:
        return 'Base $w';
      case ModuleKind.drawer:
        return 'Drawers $w';
      case ModuleKind.sink:
        return 'Sink $w';
      case ModuleKind.hob:
        return 'Hob $w';
      case ModuleKind.tall:
        return 'Tall $w';
      case ModuleKind.corner:
        return 'Corner $w';
      case ModuleKind.wall:
        return 'Wall $w';
      case ModuleKind.filler:
        return 'Filler $w';
    }
  }

  /// One entry of the `placed_cabinets` list the viewer, CPQ engine and
  /// quote payload already use. Main-wall modules keep the existing `x_mm`
  /// convention (centre, relative to the wall's centre); return-wall modules
  /// use `offset_mm` (centre, from the main wall's face).
  Map<String, dynamic> toPlacedCabinet({required double mainWallMm}) => {
        'id': id,
        'cabinet_type': cabinetType,
        'label': label,
        'kind': kind.name,
        'run': wall == RunWall.main ? 'main' : 'return',
        'width_mm': widthMm,
        'height_mm': heightMm,
        'depth_mm': depthMm,
        'mount_mm': mountMm,
        if (wall == RunWall.main) 'x_mm': (centerMm - mainWallMm / 2).round(),
        if (wall == RunWall.returnWall) 'offset_mm': centerMm.round(),
        'generated': true,
      };
}

enum LayoutTier { value, balanced, premium }

class LayoutVariant {
  const LayoutVariant({
    required this.tier,
    required this.key,
    required this.name,
    required this.modules,
    required this.warnings,
    required this.mainWallMm,
    required this.usesPlaceholderCatalog,
  });

  final LayoutTier tier;

  /// 'A', 'B' or 'C' — what the salesperson taps.
  final String key;
  final String name;
  final List<PlacedModule> modules;
  final List<String> warnings;
  final double mainWallMm;
  final bool usesPlaceholderCatalog;

  Iterable<PlacedModule> ofKind(ModuleKind kind) => modules.where((m) => m.kind == kind);

  /// e.g. "6 base · 5 wall · 1 tall"
  String get summary {
    final base = modules
        .where((m) => const {ModuleKind.base, ModuleKind.drawer, ModuleKind.sink, ModuleKind.hob, ModuleKind.corner}
            .contains(m.kind))
        .length;
    final wall = ofKind(ModuleKind.wall).length;
    final tall = ofKind(ModuleKind.tall).length;
    return [
      '$base base',
      '$wall wall',
      if (tall > 0) '$tall tall',
    ].join(' · ');
  }

  List<Map<String, dynamic>> toPlacedCabinets() =>
      [for (final m in modules) m.toPlacedCabinet(mainWallMm: mainWallMm)];
}
