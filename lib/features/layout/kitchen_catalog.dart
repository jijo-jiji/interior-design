/// PLACEHOLDER catalog and design rules for the kitchen layout generator.
///
/// Every number in this file is a stand-in until SS Love's designer returns
/// `notes/SS-Love-designer-checklist.xlsx`. The generator reads nothing else,
/// so replacing these values with the designer's real module list, sizes and
/// rules is the only change needed to make its suggestions match how they
/// actually design. Later this becomes tenant-scoped catalog data loaded from
/// the backend instead of a Dart constant.
library;

enum ModuleKind { base, drawer, sink, hob, tall, corner, wall, filler }

class KitchenCatalog {
  const KitchenCatalog({
    required this.baseDoorWidthsMm,
    required this.drawerWidthsMm,
    required this.sinkWidthsMm,
    required this.hobWidthsMm,
    required this.tallWidthMm,
    required this.wallWidthsMm,
    required this.cornerSizeMm,
    required this.baseHeightMm,
    required this.baseDepthMm,
    required this.counterHeightMm,
    required this.wallHeightMm,
    required this.wallDepthMm,
    required this.wallMountMm,
    required this.tallHeightMm,
    required this.tallDepthMm,
    required this.isPlaceholder,
  });

  final List<double> baseDoorWidthsMm;
  final List<double> drawerWidthsMm;
  final List<double> sinkWidthsMm;
  final List<double> hobWidthsMm;
  final double tallWidthMm;
  final List<double> wallWidthsMm;

  /// L-shape corner unit footprint (square, along each wall).
  final double cornerSizeMm;

  final double baseHeightMm;
  final double baseDepthMm;

  /// Finished worktop height from the floor. Windows with a sill below this
  /// block the base run.
  final double counterHeightMm;

  final double wallHeightMm;
  final double wallDepthMm;

  /// Height of the underside of wall cabinets above the floor.
  final double wallMountMm;

  final double tallHeightMm;
  final double tallDepthMm;

  /// True while this is sample data, so the UI can say so.
  final bool isPlaceholder;

  double get wallBandTopMm => wallMountMm + wallHeightMm;

  /// Sizes match the existing `CABINET_SPECS` in `assets/3d/index.html` so
  /// generated layouts look the same as manually placed cabinets.
  static const placeholder = KitchenCatalog(
    baseDoorWidthsMm: [300, 400, 450, 500, 600, 800, 900],
    drawerWidthsMm: [400, 450, 500, 600, 800, 900],
    sinkWidthsMm: [800, 900],
    hobWidthsMm: [600, 800],
    tallWidthMm: 600,
    wallWidthsMm: [300, 400, 450, 500, 600, 800, 900],
    cornerSizeMm: 900,
    baseHeightMm: 850,
    baseDepthMm: 600,
    counterHeightMm: 890,
    wallHeightMm: 700,
    wallDepthMm: 320,
    wallMountMm: 1400,
    tallHeightMm: 2100,
    tallDepthMm: 600,
    isPlaceholder: true,
  );
}

class KitchenRules {
  const KitchenRules({
    required this.minSinkToHobMm,
    required this.minHobSideCounterMm,
    required this.minSinkToTallMm,
    required this.minFillerMm,
    required this.maxFillerMm,
    required this.scribeToleranceMm,
    required this.doorClearanceMm,
    required this.windowClearanceMm,
    required this.maxSinkShiftFromWindowMm,
  });

  /// Worktop between the sink and hob cabinets.
  final double minSinkToHobMm;

  /// Worktop on each side of the hob (no hob at a run end or against a tall).
  final double minHobSideCounterMm;

  /// Worktop between the sink and a tall unit (somewhere to drain).
  final double minSinkToTallMm;

  final double minFillerMm;
  final double maxFillerMm;

  /// Gaps up to this size are absorbed by scribing on site, not a filler.
  final double scribeToleranceMm;

  /// Clear space kept between cabinets and a door opening.
  final double doorClearanceMm;

  /// Clear space kept between wall cabinets and a window opening.
  final double windowClearanceMm;

  /// How far the sink may move off the window centre to make the run fit.
  final double maxSinkShiftFromWindowMm;

  static const placeholder = KitchenRules(
    minSinkToHobMm: 600,
    minHobSideCounterMm: 300,
    minSinkToTallMm: 300,
    minFillerMm: 25,
    maxFillerMm: 150,
    scribeToleranceMm: 10,
    doorClearanceMm: 50,
    windowClearanceMm: 50,
    maxSinkShiftFromWindowMm: 300,
  );
}
