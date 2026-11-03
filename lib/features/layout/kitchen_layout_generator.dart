import 'kitchen_catalog.dart';
import 'kitchen_layout_models.dart';

/// Turns an empty measured room into filled cabinet layouts — no AI, just the
/// designer's rules applied deterministically.
///
/// Produces three variants of the same room so the salesperson can flip
/// between them with the client:
///   A · Value    — fewest, simplest modules, no tall units
///   B · Balanced — one tall unit, drawers between sink and hob
///   C · Premium  — up to two tall units, drawer banks throughout
///
/// Steps, per variant:
///   1. Split the walls into runs around doors and low windows; add a corner
///      unit for an L-shape.
///   2. Reserve tall units at the outer ends of the runs, away from the sink.
///   3. Try sink positions (under the window first) and hob positions at
///      least [KitchenRules.minSinkToHobMm] away — never under a window, never
///      at the end of a run.
///   4. Fill the gaps between them with catalog widths; any leftover goes
///      into a filler. Each candidate is scored (module count and widths,
///      fillers, distance from the ideal sink/hob spot) and the best wins.
///   5. Fill the wall-cabinet band above the worktop, lined up with the base
///      modules where possible, skipping the hob (hood), windows, doors and
///      tall units.
///
/// When a variant cannot fit everything (short walls), it drops tall units
/// first, then the hob, and reports why in [LayoutVariant.warnings].
class KitchenLayoutGenerator {
  const KitchenLayoutGenerator({
    this.catalog = KitchenCatalog.placeholder,
    this.rules = KitchenRules.placeholder,
  });

  final KitchenCatalog catalog;
  final KitchenRules rules;

  List<LayoutVariant> generateAll(KitchenRoom room) =>
      [for (final tier in LayoutTier.values) generate(room, tier)];

  LayoutVariant generate(KitchenRoom room, LayoutTier tier) =>
      _VariantBuilder(catalog, rules, room, _specFor(tier)).build();

  _VariantSpec _specFor(LayoutTier tier) {
    List<double> closestTo(List<double> widths, double target) => [...widths]
      ..sort((a, b) => (a - target).abs().compareTo((b - target).abs()));
    List<double> asc(List<double> widths) => [...widths]..sort();
    List<double> desc(List<double> widths) =>
        [...widths]..sort((a, b) => b.compareTo(a));
    List<_Piece> pieces(ModuleKind kind, Iterable<double> widths) =>
        [for (final w in widths) _Piece(kind, w)];
    final landingMin = rules.minSinkToHobMm;

    switch (tier) {
      case LayoutTier.value:
        return _VariantSpec(
          tier: tier,
          key: 'A',
          name: 'Value',
          tallCount: 0,
          sinkWidthsMm: asc(catalog.sinkWidthsMm),
          hobWidthsMm: asc(catalog.hobWidthsMm),
          landing: pieces(ModuleKind.base,
              asc(catalog.baseDoorWidthsMm).where((w) => w >= landingMin)),
          fill: pieces(ModuleKind.base, catalog.baseDoorWidthsMm),
          cost: (p) => 1.0 + (p.widthMm < 400 ? 0.3 : 0.0),
        );
      case LayoutTier.balanced:
        return _VariantSpec(
          tier: tier,
          key: 'B',
          name: 'Balanced',
          tallCount: 1,
          sinkWidthsMm: closestTo(catalog.sinkWidthsMm, 800),
          hobWidthsMm: closestTo(catalog.hobWidthsMm, 600),
          landing: pieces(ModuleKind.drawer,
              asc(catalog.drawerWidthsMm).where((w) => w >= landingMin)),
          fill: pieces(ModuleKind.base, catalog.baseDoorWidthsMm),
          cost: (p) => 1.0 + 0.5 * (p.widthMm - 600).abs() / 600,
        );
      case LayoutTier.premium:
        final drawers = catalog.drawerWidthsMm;
        final widest = drawers.reduce((a, b) => a > b ? a : b);
        final narrowestDrawer = drawers.reduce((a, b) => a < b ? a : b);
        return _VariantSpec(
          tier: tier,
          key: 'C',
          name: 'Premium',
          tallCount: 2,
          sinkWidthsMm: desc(catalog.sinkWidthsMm),
          hobWidthsMm: desc(catalog.hobWidthsMm),
          landing: pieces(
              ModuleKind.drawer, desc(drawers).where((w) => w >= landingMin)),
          // Drawer banks everywhere; narrow door units only where no drawer fits.
          fill: [
            ...pieces(ModuleKind.drawer, drawers),
            ...pieces(ModuleKind.base,
                catalog.baseDoorWidthsMm.where((w) => w < narrowestDrawer)),
          ],
          cost: (p) => p.kind == ModuleKind.drawer
              ? 1.0 + 0.3 * (widest - p.widthMm) / widest
              : 1.6,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Piece {
  const _Piece(this.kind, this.widthMm);
  final ModuleKind kind;
  final double widthMm;
}

class _VariantSpec {
  const _VariantSpec({
    required this.tier,
    required this.key,
    required this.name,
    required this.tallCount,
    required this.sinkWidthsMm,
    required this.hobWidthsMm,
    required this.landing,
    required this.fill,
    required this.cost,
  });

  final LayoutTier tier;
  final String key;
  final String name;
  final int tallCount;

  /// In order of preference.
  final List<double> sinkWidthsMm;
  final List<double> hobWidthsMm;

  /// Single modules preferred between the sink and the hob.
  final List<_Piece> landing;

  /// Modules used to fill the remaining base gaps.
  final List<_Piece> fill;

  /// Lower is preferred; plans minimise the sum over their modules.
  final double Function(_Piece) cost;
}

class _Span {
  const _Span(this.start, this.end);
  final double start;
  final double end;
  double get length => end - start;
  bool overlaps(double a, double b) => a < end - _eps && b > start + _eps;
  bool contains(double x) => x >= start - _eps && x <= end + _eps;
}

class _Run {
  const _Run(this.wall, this.start, this.end);
  final RunWall wall;
  final double start;
  final double end;
  double get length => end - start;
}

class _Anchor {
  const _Anchor(this.piece, this.startMm);
  final _Piece piece;
  final double startMm;
  double get endMm => startMm + piece.widthMm;
}

class _PlacedPiece {
  const _PlacedPiece(this.piece, this.startMm);
  final _Piece piece;
  final double startMm;
}

class _TallEnd {
  const _TallEnd(this.runIndex, this.atEnd);
  final int runIndex;
  final bool atEnd;
}

class _Fill {
  const _Fill(this.pieces, this.fillerMm, this.cost);
  final List<_Piece> pieces;
  final double fillerMm;
  final double cost;
}

class _Plan {
  const _Plan(this.byRun, this.cost, {this.sinkUnderWindow = false});
  final Map<int, List<_PlacedPiece>> byRun;
  final double cost;
  final bool sinkUnderWindow;

  _Plan plus(double extra, {bool? sinkUnderWindow}) =>
      _Plan(byRun, cost + extra,
          sinkUnderWindow: sinkUnderWindow ?? this.sinkUnderWindow);
}

class _SinkCandidate {
  const _SinkCandidate(this.runIndex, this.anchor, this.penalty,
      {required this.underWindow});
  final int runIndex;
  final _Anchor anchor;
  final double penalty;
  final bool underWindow;
}

class _HobOption {
  const _HobOption(this.anchors, this.penalty);
  final Map<int, List<_Anchor>> anchors;
  final double penalty;
}

const double _eps = 0.5;
const double _windowSearchStepMm = 25;
const double _searchStepMm = 50;

// Scoring weights: one module costs ~1.0, so these mean e.g. "moving the sink
// 100 mm off the window centre is worth a fifth of a module".
const double _sinkShiftFromWindowPerMm = 0.01;
const double _offTargetPerMm = 0.0005;
const double _lessPreferredWidth = 0.3;
const double _openRunPenalty = 2.0;

/// How many workable sink positions to compare before taking the best.
const int _sinkCandidatesToCompare = 12;

class _VariantBuilder {
  _VariantBuilder(this.catalog, this.rules, this.room, this.spec);

  final KitchenCatalog catalog;
  final KitchenRules rules;
  final KitchenRoom room;
  final _VariantSpec spec;

  final List<String> _warnings = [];
  final List<_Run> _runs = [];
  final Map<double, _Fill?> _baseFillCache = {};
  final Map<double, _Fill?> _wallFillCache = {};
  bool _hasCorner = false;

  /// Main-wall spans the hob and tall units must stay clear of.
  final List<_Span> _windowZones = [];

  /// Windows above the worktop that a sink can sit under, widest first.
  final List<WallOpening> _sinkWindows = [];

  late final List<_Piece> _wallPalette = [
    for (final w in catalog.wallWidthsMm) _Piece(ModuleKind.wall, w)
  ];
  late final double _smallestBaseMm =
      spec.fill.map((p) => p.widthMm).reduce((a, b) => a < b ? a : b);

  LayoutVariant build() {
    _warnings.addAll(room.notes);
    _buildRuns();

    final requestedTalls =
        room.wallHeightMm >= catalog.tallHeightMm ? spec.tallCount : 0;
    if (spec.tallCount > 0 && requestedTalls == 0) {
      _warnings.add(
          'Ceiling is lower than a tall unit (${catalog.tallHeightMm.round()} mm), so none were added.');
    }

    _Plan? plan;
    var placedTalls = 0;
    for (var talls = requestedTalls; talls >= 0 && plan == null; talls--) {
      for (final ends in _tallCombos(talls)) {
        plan = _bestPlan(ends, withSink: true, withHob: true);
        if (plan != null) break;
      }
      placedTalls = talls;
    }
    if (plan != null && placedTalls < requestedTalls) {
      _warnings.add(
          'Only $placedTalls of $requestedTalls tall units fit on these walls.');
    }
    if (plan == null) {
      plan = _bestPlan(const [], withSink: true, withHob: false);
      if (plan != null) {
        _warnings.add(
            'Not enough worktop for both a sink and a hob with the current rules — sink only.');
      }
    }
    if (plan == null) {
      plan = _bestPlan(const [], withSink: false, withHob: false) ??
          const _Plan({}, 0);
      _warnings.add(
          'Not enough wall for a sink with the current rules — storage only.');
    }
    final hasSink = plan.byRun.values
        .any((l) => l.any((p) => p.piece.kind == ModuleKind.sink));
    if (_sinkWindows.isNotEmpty && hasSink && !plan.sinkUnderWindow) {
      _warnings.add('The sink could not be centred under the window.');
    }

    return _assemble(plan);
  }

  // ── Geometry ───────────────────────────────────────────────────────────────

  void _buildRuns() {
    final w = room.mainWallMm;
    final baseBlocked = <_Span>[];
    for (final o in room.openings) {
      if (o.type == OpeningType.door) {
        baseBlocked.add(_Span(o.leftMm - rules.doorClearanceMm,
            o.rightMm + rules.doorClearanceMm));
      } else {
        if (o.floorMm < catalog.counterHeightMm - _eps) {
          // Sill below the worktop: no base cabinets in front of it.
          baseBlocked.add(_Span(o.leftMm, o.rightMm));
        } else {
          _sinkWindows.add(o);
        }
        _windowZones.add(_Span(o.leftMm - rules.windowClearanceMm,
            o.rightMm + rules.windowClearanceMm));
      }
    }
    _sinkWindows.sort((a, b) => b.widthMm.compareTo(a.widthMm));

    var mainStart = 0.0;
    if (room.shape == KitchenShape.lShape) {
      final corner = catalog.cornerSizeMm;
      _hasCorner = w >= corner &&
          room.returnWallMm >= corner &&
          !baseBlocked.any((s) => s.overlaps(0, corner));
      if (_hasCorner) {
        mainStart = corner;
      } else {
        _warnings.add(
            'A door or low window is in the corner, so no corner unit was added.');
      }
    }

    for (final seg in _subtract(_Span(mainStart, w), baseBlocked)) {
      if (seg.length >= rules.scribeToleranceMm)
        _runs.add(_Run(RunWall.main, seg.start, seg.end));
    }
    if (room.shape == KitchenShape.lShape) {
      final start = _hasCorner ? catalog.cornerSizeMm : catalog.baseDepthMm;
      if (room.returnWallMm - start >= rules.scribeToleranceMm) {
        _runs.add(_Run(RunWall.returnWall, start, room.returnWallMm));
      }
    }
  }

  static List<_Span> _subtract(_Span whole, List<_Span> holes) {
    var pieces = [whole];
    for (final h in holes) {
      final next = <_Span>[];
      for (final p in pieces) {
        if (!p.overlaps(h.start, h.end)) {
          next.add(p);
          continue;
        }
        if (h.start > p.start) next.add(_Span(p.start, h.start));
        if (h.end < p.end) next.add(_Span(h.end, p.end));
      }
      pieces = next;
    }
    return pieces;
  }

  /// Positions along an "unfolded" line: the main wall as-is, the return wall
  /// folded out to the left of the corner (negative).
  double _unfold(int runIndex, double mm) =>
      _runs[runIndex].wall == RunWall.main ? mm : -mm;

  double _sinkTargetUnfolded() {
    for (final win in _sinkWindows) {
      if (_runs.any((r) =>
          r.wall == RunWall.main &&
          win.centerMm > r.start &&
          win.centerMm < r.end)) {
        return win.centerMm;
      }
    }
    final i = _longestRun();
    if (i < 0) return 0;
    final r = _runs[i];
    return _unfold(i, r.start + r.length * 0.4);
  }

  int _longestRun() {
    var best = -1;
    for (var i = 0; i < _runs.length; i++) {
      if (best < 0 || _runs[i].length > _runs[best].length + _eps) best = i;
    }
    return best;
  }

  /// Every way to place [count] tall units, most preferred first.
  List<List<_TallEnd>> _tallCombos(int count) {
    final ends = _tallEnds();
    final out = <List<_TallEnd>>[];
    void pick(int from, List<_TallEnd> chosen) {
      if (chosen.length == count) {
        out.add(chosen);
        return;
      }
      for (var k = from; k < ends.length; k++) {
        pick(k + 1, [...chosen, ends[k]]);
      }
    }

    pick(0, const []);
    return out;
  }

  /// Outer run ends where tall units may go, furthest from the sink first.
  List<_TallEnd> _tallEnds() {
    final mains = [
      for (var i = 0; i < _runs.length; i++)
        if (_runs[i].wall == RunWall.main) i
    ];
    final returns = [
      for (var i = 0; i < _runs.length; i++)
        if (_runs[i].wall == RunWall.returnWall) i
    ];
    final candidates = <_TallEnd>[
      if (mains.isNotEmpty) _TallEnd(mains.last, true),
      if (room.shape == KitchenShape.singleWall && mains.isNotEmpty)
        _TallEnd(mains.first, false),
      if (returns.isNotEmpty) _TallEnd(returns.last, true),
    ];

    final valid = candidates.where((c) {
      final r = _runs[c.runIndex];
      if (r.length < catalog.tallWidthMm - _eps) return false;
      if (r.wall != RunWall.main) return true;
      final s = c.atEnd ? r.end - catalog.tallWidthMm : r.start;
      return !_windowZones.any((z) => z.overlaps(s, s + catalog.tallWidthMm));
    }).toList();

    final target = _sinkTargetUnfolded();
    double pos(_TallEnd c) => _unfold(
        c.runIndex, c.atEnd ? _runs[c.runIndex].end : _runs[c.runIndex].start);
    valid.sort(
        (a, b) => (pos(b) - target).abs().compareTo((pos(a) - target).abs()));
    return valid;
  }

  // ── Planning ───────────────────────────────────────────────────────────────

  _Plan? _bestPlan(List<_TallEnd> talls,
      {required bool withSink, required bool withHob}) {
    final base = <int, List<_Anchor>>{
      for (var i = 0; i < _runs.length; i++) i: []
    };
    final usable = <int, _Span>{};
    final sinkUsable = <int, _Span>{};
    for (var i = 0; i < _runs.length; i++) {
      final r = _runs[i];
      var s = r.start, e = r.end;
      var sinkS = s, sinkE = e;
      for (final t in talls.where((t) => t.runIndex == i)) {
        final piece = _Piece(ModuleKind.tall, catalog.tallWidthMm);
        if (t.atEnd) {
          base[i]!.add(_Anchor(piece, r.end - catalog.tallWidthMm));
          e -= catalog.tallWidthMm;
          sinkE = e - rules.minSinkToTallMm;
        } else {
          base[i]!.add(_Anchor(piece, r.start));
          s += catalog.tallWidthMm;
          sinkS = s + rules.minSinkToTallMm;
        }
      }
      if (e < s - _eps) return null; // two talls overlapping in a short run
      usable[i] = _Span(s, e);
      sinkUsable[i] = _Span(sinkS, sinkE);
    }

    if (!withSink) return _fillAll(base);

    _Plan? best;
    var workable = 0;
    for (final sink in _sinkCandidates(sinkUsable)) {
      if (best != null) {
        // Candidates come cheapest-penalty first; once the penalty alone is
        // worse than the best plan, nothing later can win.
        if (sink.penalty >= best.cost) break;
        // Only fall back to a sink away from the window if none fits under it.
        if (best.sinkUnderWindow && !sink.underWindow) break;
      }
      final sinkAnchors = _withAnchors(base, {
        sink.runIndex: [sink.anchor]
      });
      _Plan? local;
      if (!withHob) {
        local = _fillAll(sinkAnchors)
            ?.plus(sink.penalty, sinkUnderWindow: sink.underWindow);
      } else {
        for (final hob in _hobOptions(sink, usable)) {
          final plan = _fillAll(_withAnchors(sinkAnchors, hob.anchors));
          if (plan == null) continue;
          final total = plan.plus(sink.penalty + hob.penalty,
              sinkUnderWindow: sink.underWindow);
          if (local == null || total.cost < local.cost) local = total;
        }
      }
      if (local == null) continue;
      if (best == null || local.cost < best.cost) best = local;
      if (++workable >= _sinkCandidatesToCompare) break;
    }
    return best;
  }

  Map<int, List<_Anchor>> _withAnchors(
          Map<int, List<_Anchor>> a, Map<int, List<_Anchor>> b) =>
      {
        for (final i in a.keys) i: [...a[i]!, ...?b[i]],
      };

  /// Sink positions, cheapest first: under the window, then (if that never
  /// works) along the longest runs.
  List<_SinkCandidate> _sinkCandidates(Map<int, _Span> usable) {
    final underWindow = <_SinkCandidate>[];
    for (var rank = 0; rank < spec.sinkWidthsMm.length; rank++) {
      final w = spec.sinkWidthsMm[rank];
      for (final win in _sinkWindows) {
        for (var i = 0; i < _runs.length; i++) {
          final u = usable[i]!;
          if (_runs[i].wall != RunWall.main || !u.contains(win.centerMm))
            continue;
          for (var shift = -rules.maxSinkShiftFromWindowMm;
              shift <= rules.maxSinkShiftFromWindowMm + _eps;
              shift += _windowSearchStepMm) {
            final s = win.centerMm + shift - w / 2;
            if (s < u.start - _eps || s + w > u.end + _eps) continue;
            underWindow.add(_SinkCandidate(
              i,
              _Anchor(_Piece(ModuleKind.sink, w), s),
              shift.abs() * _sinkShiftFromWindowPerMm +
                  rank * _lessPreferredWidth,
              underWindow: true,
            ));
          }
        }
      }
    }
    underWindow.sort((a, b) => a.penalty.compareTo(b.penalty));

    final order = [for (var i = 0; i < _runs.length; i++) i]..sort((a, b) {
        final byLen = usable[b]!.length.compareTo(usable[a]!.length);
        return byLen != 0
            ? byLen
            : _runs[a].wall.index.compareTo(_runs[b].wall.index);
      });
    final elsewhere = <_SinkCandidate>[];
    for (var rank = 0; rank < spec.sinkWidthsMm.length; rank++) {
      final w = spec.sinkWidthsMm[rank];
      for (var runRank = 0; runRank < order.length; runRank++) {
        final i = order[runRank];
        final u = usable[i]!;
        final target = u.start + u.length * 0.4;
        final starts = [
          for (var s = u.start; s + w <= u.end + _eps; s += _searchStepMm) s,
          if (u.length >= w) u.end - w, // flush against the far end too
        ];
        for (final s in starts) {
          elsewhere.add(_SinkCandidate(
            i,
            _Anchor(_Piece(ModuleKind.sink, w), s),
            (s + w / 2 - target).abs() * _offTargetPerMm +
                rank * _lessPreferredWidth +
                runRank * 0.2,
            underWindow: false,
          ));
        }
      }
    }
    elsewhere.sort((a, b) => a.penalty.compareTo(b.penalty));
    return [...underWindow, ...elsewhere];
  }

  /// Landing (sink-to-hob) module combinations: preferred single modules,
  /// then pairs of fill modules.
  late final List<List<_Piece>> _landingCombos = () {
    final combos = <List<_Piece>>[
      for (final p in spec.landing) [p]
    ];
    final pairs = <List<_Piece>>[];
    for (final a in spec.fill) {
      for (final b in spec.fill) {
        if (a.widthMm < b.widthMm) continue;
        final sum = a.widthMm + b.widthMm;
        if (sum >= rules.minSinkToHobMm && sum <= rules.minSinkToHobMm + 1200)
          pairs.add([a, b]);
      }
    }
    double width(List<_Piece> l) => l.fold(0.0, (t, p) => t + p.widthMm);
    double cost(List<_Piece> l) => l.fold(0.0, (t, p) => t + spec.cost(p));
    pairs.sort((a, b) => cost(a).compareTo(cost(b)));
    final seen = <double>{for (final c in combos) width(c)};
    for (final p in pairs) {
      if (seen.add(width(p))) combos.add(p);
    }
    return combos;
  }();

  bool _clearOfWindows(int runIndex, double start, double width) =>
      _runs[runIndex].wall != RunWall.main ||
      !_windowZones.any((z) => z.overlaps(start, start + width));

  Iterable<_HobOption> _hobOptions(
      _SinkCandidate sink, Map<int, _Span> usable) sync* {
    final i = sink.runIndex;
    final u = usable[i]!;
    final s = sink.anchor;
    final side = rules.minHobSideCounterMm;

    // Same run as the sink, either side, with landing modules in between.
    for (final right in const [true, false]) {
      for (final combo in _landingCombos) {
        final landing = combo.fold(0.0, (t, p) => t + p.widthMm);
        final landingCost = combo.fold(0.0, (t, p) => t + spec.cost(p));
        for (var rank = 0; rank < spec.hobWidthsMm.length; rank++) {
          final hw = spec.hobWidthsMm[rank];
          final hobStart = right ? s.endMm + landing : s.startMm - landing - hw;
          if (right && hobStart + hw > u.end - side + _eps) continue;
          if (!right && hobStart < u.start + side - _eps) continue;
          if (!_clearOfWindows(i, hobStart, hw)) continue;
          final anchors = <_Anchor>[];
          var x = right ? s.endMm : hobStart + hw;
          for (final p in combo) {
            anchors.add(_Anchor(p, x));
            x += p.widthMm;
          }
          anchors.add(_Anchor(_Piece(ModuleKind.hob, hw), hobStart));
          yield _HobOption(
              {i: anchors}, landingCost + rank * _lessPreferredWidth);
        }
      }
    }

    // On another run (e.g. the return wall of an L-shape), near its middle.
    for (var j = 0; j < _runs.length; j++) {
      if (j == i) continue;
      final uj = usable[j]!;
      for (var rank = 0; rank < spec.hobWidthsMm.length; rank++) {
        final hw = spec.hobWidthsMm[rank];
        if (uj.length < hw + 2 * side - _eps) continue;
        final mid = uj.start + uj.length / 2;
        final starts = [
          for (var x = uj.start + side;
              x + hw <= uj.end - side + _eps;
              x += _searchStepMm)
            x,
          uj.end - side - hw,
        ];
        for (final x in starts) {
          if (!_clearOfWindows(j, x, hw)) continue;
          yield _HobOption(
            {
              j: [_Anchor(_Piece(ModuleKind.hob, hw), x)]
            },
            (x + hw / 2 - mid).abs() * _offTargetPerMm +
                rank * _lessPreferredWidth,
          );
        }
      }
    }
  }

  // ── Gap filling ────────────────────────────────────────────────────────────

  _Plan? _fillAll(Map<int, List<_Anchor>> anchorsByRun) {
    final out = <int, List<_PlacedPiece>>{};
    var cost = 0.0;
    for (var i = 0; i < _runs.length; i++) {
      final run = _runs[i];
      final anchors = [...anchorsByRun[i]!]
        ..sort((a, b) => a.startMm.compareTo(b.startMm));
      final placed = <_PlacedPiece>[];

      if (anchors.isEmpty) {
        final fill = _fill(run.length);
        if (fill == null || fill.pieces.isEmpty) {
          // Too short for a module (e.g. a sliver beside a door): leave open.
          out[i] = const [];
          if (run.length >= _smallestBaseMm) cost += _openRunPenalty;
          continue;
        }
        placed.addAll(_layGap(run.start, run.end, fill, fillerAtStart: false));
        out[i] = placed;
        cost += fill.cost;
        continue;
      }

      var cursor = run.start;
      var leftIsHard = true; // run boundary or tall
      for (final a in anchors) {
        if (a.startMm < cursor - _eps || a.endMm > run.end + _eps) return null;
        final rightIsTall = a.piece.kind == ModuleKind.tall;
        final fill = _fill(a.startMm - cursor);
        if (fill == null) return null;
        placed.addAll(_layGap(cursor, a.startMm, fill,
            fillerAtStart: leftIsHard || !rightIsTall));
        placed.add(_PlacedPiece(a.piece, a.startMm));
        cost += fill.cost;
        cursor = a.endMm;
        leftIsHard = rightIsTall;
      }
      final fill = _fill(run.end - cursor);
      if (fill == null) return null;
      placed.addAll(_layGap(cursor, run.end, fill, fillerAtStart: false));
      cost += fill.cost;
      out[i] = placed;
    }
    return _Plan(out, cost);
  }

  List<_PlacedPiece> _layGap(double start, double end, _Fill fill,
      {required bool fillerAtStart,
      ModuleKind fillerKind = ModuleKind.filler}) {
    final out = <_PlacedPiece>[];
    var x = start;
    final filler =
        fill.fillerMm > rules.scribeToleranceMm ? fill.fillerMm : 0.0;
    if (filler > 0 && fillerAtStart) {
      out.add(_PlacedPiece(_Piece(fillerKind, filler), x));
      x += filler;
    }
    for (final p in fill.pieces) {
      out.add(_PlacedPiece(p, x));
      x += p.widthMm;
    }
    if (filler > 0 && !fillerAtStart)
      out.add(_PlacedPiece(_Piece(fillerKind, filler), end - filler));
    return out;
  }

  _Fill? _fill(double gap, {bool wall = false}) {
    final key = (gap * 10).roundToDouble() / 10;
    return wall
        ? _wallFillCache.putIfAbsent(
            key, () => _computeFill(key, _wallPalette, _wallCost))
        : _baseFillCache.putIfAbsent(
            key, () => _computeFill(key, spec.fill, spec.cost));
  }

  static double _wallCost(_Piece p) => 1.0 + (p.widthMm < 400 ? 0.3 : 0.0);

  /// Cheapest set of [palette] modules for [gap], leaving either nothing
  /// (within scribing tolerance) or one filler of an allowed size.
  _Fill? _computeFill(
      double gap, List<_Piece> palette, double Function(_Piece) costOf) {
    if (gap < -_eps) return null;
    if (gap <= rules.scribeToleranceMm) return const _Fill([], 0, 0);

    final unit = palette.map((p) => p.widthMm.round()).reduce(_gcd);
    final n = gap ~/ unit;
    final best = List<double>.filled(n + 1, double.infinity);
    final choice = List<int>.filled(n + 1, -1);
    best[0] = 0;
    for (var s = 1; s <= n; s++) {
      for (var k = 0; k < palette.length; k++) {
        final steps = palette[k].widthMm.round() ~/ unit;
        if (steps > s || best[s - steps].isInfinite) continue;
        final c = best[s - steps] + costOf(palette[k]);
        if (c < best[s] - 1e-9) {
          best[s] = c;
          choice[s] = k;
        }
      }
    }

    var bestS = -1;
    var bestScore = double.infinity;
    for (var s = 0; s <= n; s++) {
      if (best[s].isInfinite) continue;
      final r = gap - s * unit;
      final double fillerCost;
      if (r <= rules.scribeToleranceMm) {
        fillerCost = 0;
      } else if (r >= rules.minFillerMm && r <= rules.maxFillerMm) {
        fillerCost = 0.5 + r / rules.maxFillerMm;
      } else {
        continue;
      }
      final score = best[s] + fillerCost;
      if (score < bestScore - 1e-9 ||
          ((score - bestScore).abs() <= 1e-9 && s > bestS)) {
        bestScore = score;
        bestS = s;
      }
    }
    if (bestS < 0) return null;

    final pieces = <_Piece>[];
    for (var s = bestS;
        s > 0;
        s -= palette[choice[s]].widthMm.round() ~/ unit) {
      pieces.add(palette[choice[s]]);
    }
    pieces.sort((a, b) => b.widthMm.compareTo(a.widthMm));
    return _Fill(pieces, gap - bestS * unit, bestScore);
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  // ── Output ────────────────────────────────────────────────────────────────

  LayoutVariant _assemble(_Plan plan) {
    final modules = <PlacedModule>[];
    var n = 0;
    String nextId() => '${spec.key}-${(++n).toString().padLeft(2, '0')}';

    PlacedModule floorModule(_Piece p, RunWall wall, double start) {
      final isTall = p.kind == ModuleKind.tall;
      final isCorner = p.kind == ModuleKind.corner;
      return PlacedModule(
        id: nextId(),
        kind: p.kind,
        wall: wall,
        startMm: start,
        widthMm: p.widthMm,
        heightMm: isTall ? catalog.tallHeightMm : catalog.baseHeightMm,
        depthMm: isCorner
            ? catalog.cornerSizeMm
            : (isTall ? catalog.tallDepthMm : catalog.baseDepthMm),
        mountMm: 0,
      );
    }

    final floor = <PlacedModule>[];
    if (_hasCorner)
      floor.add(floorModule(
          _Piece(ModuleKind.corner, catalog.cornerSizeMm), RunWall.main, 0));
    for (var i = 0; i < _runs.length; i++) {
      final pieces = plan.byRun[i] ?? const [];
      if (pieces.isEmpty && _runs[i].length >= _smallestBaseMm) {
        final where =
            _runs[i].wall == RunWall.main ? 'main wall' : 'return wall';
        _warnings.add(
            'A ${_runs[i].length.round()} mm section of the $where is left open (no module fits).');
      }
      for (final p in pieces) {
        floor.add(floorModule(p.piece, _runs[i].wall, p.startMm));
      }
    }
    modules.addAll(floor);
    modules.addAll(_wallCabinets(floor, nextId));

    return LayoutVariant(
      tier: spec.tier,
      key: spec.key,
      name: spec.name,
      modules: List.unmodifiable(modules),
      warnings: List.unmodifiable(_warnings),
      mainWallMm: room.mainWallMm,
      usesPlaceholderCatalog: catalog.isPlaceholder,
    );
  }

  /// Fills the wall-cabinet band above the worktop. Wall cabinets line up with
  /// the base module below wherever that width exists; the rest is filled
  /// with catalog widths. Nothing goes over the hob (hood), tall units,
  /// doors, or windows that reach into the band.
  List<PlacedModule> _wallCabinets(
      List<PlacedModule> floor, String Function() nextId) {
    if (room.wallHeightMm < catalog.wallBandTopMm - _eps) {
      _warnings.add(
          'Ceiling is too low for wall cabinets at the standard mounting height.');
      return const [];
    }
    final mainBlocked = <_Span>[
      for (final o in room.openings)
        if (o.type == OpeningType.door)
          _Span(o.leftMm - rules.doorClearanceMm,
              o.rightMm + rules.doorClearanceMm)
        else if (o.floorMm < catalog.wallBandTopMm &&
            o.topMm > catalog.wallMountMm)
          _Span(o.leftMm - rules.windowClearanceMm,
              o.rightMm + rules.windowClearanceMm),
    ];

    const counterKinds = {
      ModuleKind.base,
      ModuleKind.drawer,
      ModuleKind.sink,
      ModuleKind.corner,
      ModuleKind.filler
    };
    const mirroredKinds = {
      ModuleKind.base,
      ModuleKind.drawer,
      ModuleKind.sink,
      ModuleKind.corner
    };

    PlacedModule wallUnit(_PlacedPiece p, RunWall wall) => PlacedModule(
          id: nextId(),
          kind: p.piece.kind == ModuleKind.filler
              ? ModuleKind.filler
              : ModuleKind.wall,
          wall: wall,
          startMm: p.startMm,
          widthMm: p.piece.widthMm,
          heightMm: catalog.wallHeightMm,
          depthMm: catalog.wallDepthMm,
          mountMm: catalog.wallMountMm,
        );

    final out = <PlacedModule>[];
    for (final wall in RunWall.values) {
      final onWall = floor.where((m) => m.wall == wall).toList()
        ..sort((a, b) => a.startMm.compareTo(b.startMm));

      // Stretches of worktop (contiguous counter-height modules).
      final counters = <_Span>[];
      for (final m in onWall.where((m) => counterKinds.contains(m.kind))) {
        if (counters.isNotEmpty &&
            m.startMm - counters.last.end <= rules.scribeToleranceMm) {
          counters[counters.length - 1] = _Span(counters.last.start, m.endMm);
        } else {
          counters.add(_Span(m.startMm, m.endMm));
        }
      }
      final blocked = [
        if (wall == RunWall.main) ...mainBlocked,
        for (final h in onWall.where((m) => m.kind == ModuleKind.hob))
          _Span(h.startMm, h.endMm),
      ];

      for (final counter in counters) {
        for (final free in _subtract(counter, blocked)) {
          final mirrored = [
            for (final m in onWall)
              if (mirroredKinds.contains(m.kind) &&
                  m.startMm >= free.start - _eps &&
                  m.endMm <= free.end + _eps &&
                  catalog.wallWidthsMm.any((w) => (w - m.widthMm).abs() < _eps))
                _PlacedPiece(_Piece(ModuleKind.wall, m.widthMm), m.startMm),
          ];
          final placed = <_PlacedPiece>[];
          var cursor = free.start;
          for (var k = 0; k <= mirrored.length; k++) {
            final gapEnd = k < mirrored.length ? mirrored[k].startMm : free.end;
            final fill = _fill(gapEnd - cursor, wall: true);
            final touchesCabinet = k > 0 || k < mirrored.length;
            if (fill != null && (fill.pieces.isNotEmpty || touchesCabinet)) {
              // Fillers go against whatever bounds the span (wall, window, hood).
              placed.addAll(_layGap(cursor, gapEnd, fill,
                  fillerAtStart: k == 0, fillerKind: ModuleKind.filler));
            }
            if (k < mirrored.length) {
              placed.add(mirrored[k]);
              cursor = mirrored[k].startMm + mirrored[k].piece.widthMm;
            }
          }
          out.addAll(placed.map((p) => wallUnit(p, wall)));
        }
      }
    }
    return out;
  }
}
