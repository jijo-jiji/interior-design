import '../../catalog/price_catalog.dart';

/// What a cabinet on the wall can become without taking it out: the other
/// sizes of the same unit, and the other units that go in the same place
/// (a drawer unit or a dishwasher for a base unit, an oven tower for a tall
/// one…). Every choice says whether it fits where the cabinet is; [swap]
/// makes the change and keeps the cabinet in its place.
///
/// Works on the `placed_cabinets` records the 3D page, the price engine and
/// the quote already use. Main-wall records hold `x_mm`, the centre measured
/// from the wall's centre; side-wall (L-shape) records hold `offset_mm`, the
/// centre measured from the main wall's face.
class CabinetChoices {
  CabinetChoices({
    required this.catalog,
    required List<Map<String, dynamic>> cabinets,
    required Map<String, dynamic> wall,
    List<dynamic> obstacles = const [],
  })  : cabinets = List.unmodifiable(cabinets),
        _wallMm = _num(wall['width_mm'], 3000),
        _returnMm = wall['shape'] == 'lShape' ? _num(wall['return_mm']) : 0,
        _obstacles = obstacles;

  final PriceCatalog catalog;
  final List<Map<String, dynamic>> cabinets;
  final double _wallMm;
  final double _returnMm;
  final List<dynamic> _obstacles;

  /// Overlaps smaller than this (rounding) don't count.
  static const _slackMm = 1.0;

  Map<String, dynamic>? find(String id) {
    for (final c in cabinets) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  /// How the 3D page draws the record: base, drawer, sink, hob, wall, tall,
  /// corner, filler, dishwasher, oven, fridge or hood.
  String kindOf(Map<String, dynamic> c) =>
      c['kind'] as String? ??
      catalog.kindOf(c['cabinet_type'] as String? ?? '');

  /// The cabinet's own name, as the client would say it.
  String nameOf(Map<String, dynamic> c) =>
      c['label'] as String? ?? catalog.module(_type(c))?.label ?? _type(c);

  /// What is in it, in a few words (what the 3D view draws).
  String describe(Map<String, dynamic> c) {
    final w = _num(c['width_mm']);
    final doors = w >= 500 ? '2 doors' : '1 door';
    return switch (kindOf(c)) {
      'base' => 'Floor unit with $doors',
      'drawer' => 'Floor unit with 3 drawers',
      'hob' => 'Hob on the worktop, 3 drawers below',
      'sink' => 'Sink and tap on the worktop, $doors below, open at the back '
          'for the pipes',
      'wall' => 'Wall unit with $doors and a light strip underneath',
      'tall' => 'Floor-to-top unit, doors below and above',
      'corner' => 'Corner unit, reaching into the corner',
      'dishwasher' => 'Built-in dishwasher behind a door in the cabinet finish',
      'oven' => 'Oven tower: a drawer, an oven, a compact oven or microwave, '
          'and a cupboard on top',
      'fridge' => 'Fridge-freezer space with a cupboard on top',
      'hood' => 'Rangehood over the hob, with its chimney',
      'filler' => 'Filler strip that closes a small gap',
      _ => 'Cabinet',
    };
  }

  /// Width × height × depth, in mm.
  String sizeOf(Map<String, dynamic> c) =>
      '${_mm(c['width_mm'])} × ${_mm(c['height_mm'])} × ${_mm(c['depth_mm'])} mm';

  /// The same unit in the other widths the catalogue makes, narrowest first
  /// (the current one included, marked [CabinetChoice.current]).
  List<CabinetChoice> sizesFor(String id) {
    final c = find(id);
    if (c == null) return const [];
    final family = _families[kindOf(c)];
    if (family == null) return const [];
    final widths = family.widths(catalog.layout);
    if (widths.length < 2) return const [];
    return [
      for (final w in widths) _choice(c, family, w),
    ];
  }

  /// The other units that go in the same place, each at the width nearest
  /// the cabinet's own (the current one first).
  List<CabinetChoice> typesFor(String id) {
    final c = find(id);
    if (c == null) return const [];
    final kind = kindOf(c);
    final group = _groupOfKind[kind];
    if (group == null) return const [];
    final width = _num(c['width_mm']);
    final out = <CabinetChoice>[];
    for (final f in _families.values) {
      if (f.group != group) continue;
      final widths = f.widths(catalog.layout);
      if (widths.isEmpty) continue;
      out.add(_choice(c, f, _nearest(widths, width)));
    }
    // Appliance units the catalogue sells at one size (dishwasher, oven
    // tower, fridge recess, rangehood), when no family above draws them.
    final offered = {for (final f in _families.values) f.kind};
    for (final m in catalog.modules) {
      if (!m.isAppliance) continue;
      final mKind = catalog.kindOf(m.type);
      if (offered.contains(mKind) || _groupOfKind[mKind] != group) continue;
      out.add(_moduleChoice(c, m, mKind));
    }
    out.sort((a, b) => a.current == b.current ? 0 : (a.current ? -1 : 1));
    return out;
  }

  /// [c] turned into [choice], in the same place: its left end stays put if
  /// the new unit fits that way, else its right end, else its centre. The
  /// result is the whole list with the one record replaced (same id), or
  /// null if [choice] doesn't fit.
  List<Map<String, dynamic>>? swap(String id, CabinetChoice choice) {
    final c = find(id);
    final placed = c == null
        ? null
        : _placeFor(c, choice.widthMm, _bandsOfKind(choice.kind));
    if (c == null || placed == null) return null;
    final isReturn = c['run'] == 'return';
    final center = placed + choice.widthMm / 2;
    final record = <String, dynamic>{
      for (final e in c.entries)
        if (!const {'x_mm', 'offset_mm'}.contains(e.key)) e.key: e.value,
      'cabinet_type': choice.type,
      'label': choice.label,
      'kind': choice.kind,
      'run': isReturn ? 'return' : 'main',
      'width_mm': choice.widthMm,
      'height_mm': choice.heightMm,
      'depth_mm': choice.depthMm,
      'mount_mm': choice.mountMm,
      if (isReturn) 'offset_mm': center.round() else 'x_mm': center.round(),
      // Drawn and priced from its own size, like a generated unit.
      'generated': true,
    };
    return [for (final x in cabinets) x['id'] == id ? record : x];
  }

  // ── Adding a unit ─────────────────────────────────────────────────────────

  /// What a unit from the tray (or the appliance list) can be: the widths
  /// the catalogue makes of it, the tray's own one marked current; or itself
  /// alone if it is sold at one size (an appliance, a corner unit). Each says
  /// if there is room for it anywhere on these walls.
  List<CabinetChoice> addChoices(String type) {
    final module = catalog.module(type);
    if (module == null && catalog.familyFor(type) == null) return const [];
    final kind = catalog.kindOf(type);
    final family = _families[kind];
    final widths = family?.widths(catalog.layout) ?? const <double>[];
    final List<CabinetChoice> made;
    if (family != null && widths.isNotEmpty && !(module?.isAppliance ?? false)) {
      final own = module?.widthMm ?? widths.first;
      made = [
        for (final w in widths)
          _newChoice(family, w, current: (w - own).abs() < 0.5),
      ];
    } else if (module != null) {
      made = [
        CabinetChoice(
          kind: kind,
          type: module.type,
          label: module.label,
          widthMm: module.widthMm,
          heightMm: module.heightMm,
          depthMm: module.depthMm,
          mountMm: module.mountMm,
          current: true,
        ),
      ];
    } else {
      return const [];
    }
    return [
      for (final c in made)
        placementsFor(c).isEmpty
            ? c.withProblem('No room for it on these walls')
            : c,
    ];
  }

  CabinetChoice _newChoice(_Family f, double widthMm, {required bool current}) {
    final w = widthMm.round();
    return CabinetChoice(
      kind: f.kind,
      type: '${f.prefix}$w',
      label: '${f.label} $w',
      widthMm: widthMm,
      heightMm: f.height(catalog.layout),
      depthMm: f.depth(catalog.layout),
      mountMm: f.mount(catalog.layout),
      current: current,
    );
  }

  /// Every free space on these walls a [choice] fits in, at its height
  /// (floor, wall units, or both for a tall unit): its left end against the
  /// cabinet (or wall end) on the left. The ones beside [near] (the
  /// selected cabinet) come first.
  List<Placement> placementsFor(CabinetChoice choice, {String? near}) {
    final bands = _bandsOfKind(choice.kind);
    final out = <Placement>[];
    for (final run in ['main', if (_returnMm > 0) 'return']) {
      final (lo, hi) = _runBounds(run);
      final blocked = _blockersOn(run, bands)
        ..sort((a, b) => a.$1.compareTo(b.$1));
      final free = <(double, double)>[];
      var cursor = lo;
      for (final (s, e) in blocked) {
        if (s > cursor) free.add((cursor, s < hi ? s : hi));
        if (e > cursor) cursor = e;
      }
      if (cursor < hi) free.add((cursor, hi));
      for (final (s, e) in free) {
        if (e - s + _slackMm < choice.widthMm) continue;
        final left = _neighbour(run, s, bands, endsAt: true);
        final right = _neighbour(run, e, bands, endsAt: false);
        final where = left != null
            ? 'Next to ${nameOf(left)}'
            : run == 'return'
                ? 'On the side wall'
                : s <= lo + _slackMm
                    ? 'At the left end'
                    : right != null
                        ? 'Before ${nameOf(right)}'
                        : 'In the gap';
        out.add(Placement(
          run: run,
          startMm: s,
          freeMm: e - s,
          label: '$where · ${_mm(e - s)} mm free',
          beside: {
            if (left != null) left['id'] as String,
            if (right != null) right['id'] as String,
          },
        ));
      }
    }
    if (near == null) return out;
    return [
      ...out.where((p) => p.beside.contains(near)),
      ...out.where((p) => !p.beside.contains(near)),
    ];
  }

  /// The cabinet on [run] at [band] height whose end (or start) is at [at].
  Map<String, dynamic>? _neighbour(String run, double at, Set<_Band> bands,
      {required bool endsAt}) {
    for (final o in cabinets) {
      if ((o['run'] == 'return') != (run == 'return')) continue;
      if (_bandsOf(o).intersection(bands).isEmpty) continue;
      final (s, e) = _span(o);
      if (((endsAt ? e : s) - at).abs() <= _slackMm) return o;
    }
    return null;
  }

  /// The record [choice] gets at [at], with [id].
  Map<String, dynamic> recordFor(
      CabinetChoice choice, Placement at, String id) {
    final center = at.startMm + choice.widthMm / 2;
    return {
      'id': id,
      'cabinet_type': choice.type,
      'label': choice.label,
      'kind': choice.kind,
      'run': at.run,
      'width_mm': choice.widthMm,
      'height_mm': choice.heightMm,
      'depth_mm': choice.depthMm,
      'mount_mm': choice.mountMm,
      if (at.run == 'return') 'offset_mm': center.round() else 'x_mm': center.round(),
      // Drawn and priced from its own size, like a generated unit.
      'generated': true,
    };
  }

  /// Every cabinet, and [choice] added at [at].
  List<Map<String, dynamic>> add(
          CabinetChoice choice, Placement at, String id) =>
      [...cabinets, recordFor(choice, at, id)];

  // ── Choices ───────────────────────────────────────────────────────────────

  CabinetChoice _choice(Map<String, dynamic> c, _Family f, double widthMm) {
    final sameGroup = _groupOfKind[kindOf(c)] == f.group;
    // A unit of the same height band keeps the cabinet's own height, depth
    // and mounting, so it lines up with its neighbours.
    final h = sameGroup
        ? _num(c['height_mm'], f.height(catalog.layout))
        : f.height(catalog.layout);
    final d = sameGroup
        ? _num(c['depth_mm'], f.depth(catalog.layout))
        : f.depth(catalog.layout);
    final mount = sameGroup
        ? _num(c['mount_mm'], f.mount(catalog.layout))
        : f.mount(catalog.layout);
    final w = widthMm.round();
    final type = '${f.prefix}$w';
    return CabinetChoice(
      kind: f.kind,
      type: type,
      label: '${f.label} $w',
      widthMm: widthMm,
      heightMm: h,
      depthMm: d,
      mountMm: mount,
      current:
          kindOf(c) == f.kind && (_num(c['width_mm']) - widthMm).abs() < 0.5,
      problem: _problem(c, widthMm, _bandsOfKind(f.kind)),
    );
  }

  CabinetChoice _moduleChoice(
          Map<String, dynamic> c, CatalogModule m, String kind) =>
      CabinetChoice(
        kind: kind,
        type: m.type,
        label: m.label,
        widthMm: m.widthMm,
        heightMm: m.heightMm,
        depthMm: m.depthMm,
        mountMm: m.mountMm,
        current: _type(c) == m.type,
        problem: _problem(c, m.widthMm, _bandsOfKind(kind)),
      );

  // ── Fitting ───────────────────────────────────────────────────────────────

  /// Why a [widthMm] unit doesn't fit where [c] is, or null if it does.
  String? _problem(Map<String, dynamic> c, double widthMm, Set<_Band> bands) {
    if (_placeFor(c, widthMm, bands) != null) return null;
    final room = _roomAround(c, bands);
    return room <= 0
        ? "Doesn't fit here"
        : 'Too wide for the ${_mm(room)} mm free here';
  }

  /// Where the left (or near) end of a [widthMm] unit goes, or null.
  double? _placeFor(Map<String, dynamic> c, double widthMm, Set<_Band> bands) {
    final (start, end) = _span(c);
    for (final s in [start, end - widthMm, (start + end - widthMm) / 2]) {
      if (_free(c, s, s + widthMm, bands)) return s;
    }
    return null;
  }

  /// The width of the free space [c] stands in, wall to neighbour.
  double _roomAround(Map<String, dynamic> c, Set<_Band> bands) {
    final (start, end) = _span(c);
    final (lo, hi) = _bounds(c);
    var left = lo, right = hi;
    for (final (s, e) in _blockers(c, bands)) {
      if (e <= start + _slackMm) left = left > e ? left : e;
      if (s >= end - _slackMm) right = right < s ? right : s;
    }
    return right - left;
  }

  bool _free(Map<String, dynamic> c, double s, double e, Set<_Band> bands) {
    final (lo, hi) = _bounds(c);
    if (s < lo - _slackMm || e > hi + _slackMm) return false;
    for (final (bs, be) in _blockers(c, bands)) {
      if (s < be - _slackMm && bs < e - _slackMm) return false;
    }
    return true;
  }

  /// What else takes the same run and height band: the other cabinets, and
  /// on the main wall the doors and windows (with the catalogue's clearance).
  List<(double, double)> _blockers(Map<String, dynamic> c, Set<_Band> bands) =>
      _blockersOn(c['run'] == 'return' ? 'return' : 'main', bands,
          except: c['id'] as String?);

  List<(double, double)> _blockersOn(String run, Set<_Band> bands,
      {String? except}) {
    final isReturn = run == 'return';
    final out = <(double, double)>[];
    for (final o in cabinets) {
      if (o['id'] == except || (o['run'] == 'return') != isReturn) continue;
      if (_bandsOf(o).intersection(bands).isEmpty) continue;
      out.add(_span(o));
    }
    if (!isReturn) {
      final rules = catalog.layout.rules;
      for (final o in _obstacles) {
        if (o is! Map) continue;
        final from = _num(o['distance_from_left_mm']) - _wallMm / 2;
        final width = _num(o['width_mm']);
        final bottom = _num(o['distance_from_floor_mm']);
        final top = bottom + _num(o['height_mm']);
        final isDoor = o['type'] == 'door';
        final clear = _num(
            rules[isDoor ? 'door_clearance_mm' : 'window_clearance_mm'], 50);
        final layout = catalog.layout;
        final blocked = <_Band>{
          if (isDoor || bottom < layout.counterHeightMm) _Band.floor,
          if (isDoor ||
              (top > layout.wallMountMm &&
                  bottom < layout.wallMountMm + layout.wallHeightMm))
            _Band.wall,
        };
        if (blocked.intersection(bands).isEmpty) continue;
        out.add((from - clear, from + width + clear));
      }
    }
    return out;
  }

  /// Where a run may hold cabinets: the main wall end to end; the side wall
  /// from past the corner to its end.
  (double, double) _bounds(Map<String, dynamic> c) =>
      _runBounds(c['run'] == 'return' ? 'return' : 'main');

  (double, double) _runBounds(String run) {
    if (run != 'return') return (-_wallMm / 2, _wallMm / 2);
    final hasCorner = cabinets.any((o) => kindOf(o) == 'corner');
    return (
      hasCorner ? catalog.layout.cornerSizeMm : catalog.layout.baseDepthMm,
      _returnMm
    );
  }

  /// The record's start and end along its run.
  (double, double) _span(Map<String, dynamic> c) {
    final w = _num(c['width_mm']);
    final center =
        c['run'] == 'return' ? _num(c['offset_mm']) : _num(c['x_mm']);
    return (center - w / 2, center + w / 2);
  }

  /// A filler strip is a wall one if it hangs (or is named so).
  Set<_Band> _bandsOf(Map<String, dynamic> c) {
    final kind = kindOf(c);
    if (kind == 'filler') {
      return _num(c['mount_mm']) > 0 || _type(c) == 'filler_wall' ? {_Band.wall} : {_Band.floor};
    }
    return _bandsOfKind(kind);
  }

  static Set<_Band> _bandsOfKind(String kind) => switch (kind) {
        'wall' || 'hood' => {_Band.wall},
        'tall' || 'oven' || 'fridge' => {_Band.floor, _Band.wall},
        _ => {_Band.floor},
      };

  // ── Catalogue knowledge ───────────────────────────────────────────────────

  static const _groupOfKind = {
    'base': 'base',
    'drawer': 'base',
    'sink': 'base',
    'hob': 'base',
    'dishwasher': 'base',
    'wall': 'wall',
    'hood': 'wall',
    'tall': 'tall',
    'oven': 'tall',
    'fridge': 'tall',
  };

  /// The families a salesperson can size, with the catalogue's widths. The
  /// type names are the ones the layout generator uses (`base_450`,
  /// `base_drawer_600`…), so they price by width and draw from their size.
  static final _families = <String, _Family>{
    'base': _Family('base', 'base', 'base_', 'Base', (l) => l.baseDoorWidthsMm),
    'drawer': _Family(
        'drawer', 'base', 'base_drawer_', 'Drawers', (l) => l.drawerWidthsMm),
    'sink':
        _Family('sink', 'base', 'base_sink_', 'Sink', (l) => l.sinkWidthsMm),
    'hob': _Family('hob', 'base', 'base_hob_', 'Hob', (l) => l.hobWidthsMm),
    'wall': _Family('wall', 'wall', 'wall_', 'Wall', (l) => l.wallWidthsMm),
    'tall': _Family('tall', 'tall', 'tall_', 'Tall', (l) => [l.tallWidthMm]),
  };

  String _type(Map<String, dynamic> c) => c['cabinet_type'] as String? ?? '';

  static double _nearest(List<double> widths, double w) =>
      widths.reduce((a, b) => (a - w).abs() <= (b - w).abs() ? a : b);

  static double _num(Object? v, [double fallback = 0]) =>
      (v as num?)?.toDouble() ?? fallback;

  static String _mm(Object? v) => (_num(v)).round().toString();
}

/// One thing a cabinet can become.
class CabinetChoice {
  const CabinetChoice({
    required this.kind,
    required this.type,
    required this.label,
    required this.widthMm,
    required this.heightMm,
    required this.depthMm,
    required this.mountMm,
    required this.current,
    this.problem,
  });

  final String kind;

  /// The `cabinet_type` it would have.
  final String type;
  final String label;
  final double widthMm;
  final double heightMm;
  final double depthMm;
  final double mountMm;

  /// It is what the cabinet already is.
  final bool current;

  /// Why it can't go here (too wide…), or null if it fits.
  final String? problem;

  bool get fits => problem == null;

  CabinetChoice withProblem(String? problem) => CabinetChoice(
        kind: kind,
        type: type,
        label: label,
        widthMm: widthMm,
        heightMm: heightMm,
        depthMm: depthMm,
        mountMm: mountMm,
        current: current,
        problem: problem,
      );
}

/// A free space a new unit can go in.
class Placement {
  const Placement({
    required this.run,
    required this.startMm,
    required this.freeMm,
    required this.label,
    this.beside = const {},
  });

  /// `main` or `return` (the side wall of an L).
  final String run;

  /// Where the unit's left (near) end goes: from the wall's centre on the
  /// main wall, from the main wall's face on the side wall.
  final double startMm;

  /// How much room the space has.
  final double freeMm;

  /// "Next to Sink 900 · 600 mm free".
  final String label;

  /// The cabinets on either side of the space.
  final Set<String> beside;

  @override
  bool operator ==(Object other) =>
      other is Placement && other.run == run && (other.startMm - startMm).abs() < 0.5;

  @override
  int get hashCode => Object.hash(run, startMm.round());
}

enum _Band { floor, wall }

class _Family {
  const _Family(this.kind, this.group, this.prefix, this.label, this._widths);

  final String kind;
  final String group;
  final String prefix;
  final String label;
  final List<double> Function(LayoutSpec) _widths;

  List<double> widths(LayoutSpec l) => [
        for (final w in _widths(l))
          if (w > 0) w
      ];

  double height(LayoutSpec l) => switch (group) {
        'wall' => l.wallHeightMm,
        'tall' => l.tallHeightMm,
        _ => l.baseHeightMm,
      };

  double depth(LayoutSpec l) => switch (group) {
        'wall' => l.wallDepthMm,
        'tall' => l.tallDepthMm,
        _ => l.baseDepthMm,
      };

  double mount(LayoutSpec l) => group == 'wall' ? l.wallMountMm : 0;
}
