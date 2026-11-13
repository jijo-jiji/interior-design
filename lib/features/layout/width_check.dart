import 'kitchen_catalog.dart';
import 'kitchen_layout_generator.dart';
import 'kitchen_layout_models.dart';

/// How far off a wall measured from a photo can be: the estimate is roughly
/// ±5% (see lib/features/trace/utils/wall_size.dart).
const double kPhotoSizeMargin = 0.05;

/// What matters for the quote when the wall is a little bigger or smaller:
/// whether the sink, hob and corner unit fit, and how many tall units.
const _counted = [
  ModuleKind.sink,
  ModuleKind.hob,
  ModuleKind.tall,
  ModuleKind.corner
];

/// Whether a layout would come out differently if the wall were [marginMm]
/// narrower or wider than measured: what changes either way, or null if
/// nothing that matters does.
class WidthSensitivity {
  const WidthSensitivity(this.marginMm, this.narrower, this.wider);

  final double marginMm;

  /// What changes on a narrower wall ("the hob no longer fits"), or null.
  final String? narrower;

  /// What changes on a wider wall ("a tall unit fits"), or null.
  final String? wider;

  /// For the salesperson.
  String get message {
    final mm = _mm(marginMm);
    final parts = [
      if (narrower != null) '$mm mm narrower, $narrower',
      if (wider != null) '$mm mm wider, $wider',
    ];
    return 'This layout depends on the exact width: ${parts.join('; ')}. '
        'Measure the width before quoting.';
  }
}

/// Lays out [room] again with everything [fraction] smaller and larger, as a
/// photo's scale being off would make it (the wall, its height, its windows
/// and doors), and compares what fits with [tier]'s layout as measured.
WidthSensitivity? widthSensitivity(
    KitchenLayoutGenerator generator, KitchenRoom room, LayoutTier tier,
    {double fraction = kPhotoSizeMargin}) {
  if (room.mainWallMm <= 0) return null;
  final margin = (room.mainWallMm * fraction / 10).roundToDouble() * 10;
  final f = margin / room.mainWallMm;
  final base = _counts(generator.generate(room, tier));
  String? change(double scale) {
    final other = _counts(generator.generate(_scaled(room, scale), tier));
    final said = [
      for (final kind in _counted)
        if (other[kind] != base[kind])
          _describe(kind, base[kind]!, other[kind]!),
    ];
    return said.isEmpty ? null : said.join(' and ');
  }

  final narrower = change(1 - f), wider = change(1 + f);
  if (narrower == null && wider == null) return null;
  return WidthSensitivity(margin, narrower, wider);
}

Map<ModuleKind, int> _counts(LayoutVariant v) => {
      for (final kind in _counted)
        kind: v.modules.where((m) => m.kind == kind).length,
    };

String _describe(ModuleKind kind, int before, int after) {
  final name = switch (kind) {
    ModuleKind.sink => 'sink',
    ModuleKind.hob => 'hob',
    ModuleKind.tall => 'tall unit',
    _ => 'corner unit',
  };
  if (before > 0 && after == 0) {
    return before == 1 ? 'the $name no longer fits' : 'no ${name}s fit';
  }
  if (before == 0) return after == 1 ? 'a $name fits' : '$after ${name}s fit';
  final d = (after - before).abs();
  if (after > before) return d == 1 ? 'one more $name fits' : '$d more ${name}s fit';
  return d == 1 ? 'one $name fewer' : '$d fewer ${name}s';
}

KitchenRoom _scaled(KitchenRoom room, double s) => KitchenRoom(
      mainWallMm: room.mainWallMm * s,
      wallHeightMm: room.wallHeightMm * s,
      shape: room.shape,
      returnWallMm: room.returnWallMm * s,
      openings: [
        for (final o in room.openings)
          WallOpening(
            type: o.type,
            leftMm: o.leftMm * s,
            floorMm: o.floorMm * s,
            widthMm: o.widthMm * s,
            heightMm: o.heightMm * s,
          ),
      ],
      notes: room.notes,
    );

String _mm(double mm) =>
    mm.round().toString().replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');
