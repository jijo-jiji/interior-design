import '../../catalog/price_catalog.dart';

/// The main wall as the wall card sees it: its doors and windows (those to
/// be made marked with a `work` key: `hidden_door`, `door`, `window`), where
/// a new one can go, and its finish.
///
/// Pure Dart: no Flutter, no 3D page. The records are the same obstacle
/// records the layout generator, the fit checks and the server read, so a new
/// door is a door to everything else.
class WallWorkModel {
  WallWorkModel({
    required this.catalog,
    required Map<String, dynamic> wall,
    required List<Map<String, dynamic>> obstacles,
    required List<Map<String, dynamic>> cabinets,
  })  : obstacles = List.unmodifiable(obstacles),
        _cabinets = cabinets,
        widthMm = _num(wall['width_mm'], 3000),
        heightMm = _num(wall['height_mm'], 2700);

  final PriceCatalog catalog;
  final List<Map<String, dynamic>> obstacles;
  final List<Map<String, dynamic>> _cabinets;
  final double widthMm;
  final double heightMm;

  /// The kinds of opening that can be made, in the order the card offers
  /// them, as the catalogue lists them.
  List<String> get kinds => [
        for (final k in const ['hidden_door', 'door', 'window'])
          if (catalog.wallWork.openings.containsKey(k)) k,
        for (final k in catalog.wallWork.openings.keys)
          if (!const ['hidden_door', 'door', 'window'].contains(k)) k,
      ];

  // ── What things are called ───────────────────────────────────────────────

  static String kindName(String work) => switch (work) {
        'hidden_door' => 'Hidden door',
        'door' => 'New door',
        'window' => 'New window',
        _ => work.replaceAll('_', ' '),
      };

  /// The add button's word for [work]: "Hidden door", "Door", "Window".
  static String addName(String work) => switch (work) {
        'hidden_door' => 'Hidden door',
        'door' => 'Door',
        'window' => 'Window',
        _ => kindName(work),
      };

  /// "Hidden door", "New window"; for one already there "Door", "Window".
  static String nameOf(Map<String, dynamic> o) {
    final work = o['work'];
    if (work is String && work.isNotEmpty) return kindName(work);
    return o['type'] == 'door' ? 'Door' : 'Window';
  }

  /// "800 × 2100 mm".
  static String sizeOf(Map<String, dynamic> o) =>
      '${_num(o['width_mm']).round()} × ${_num(o['height_mm']).round()} mm';

  static bool isNew(Map<String, dynamic> o) =>
      o['work'] is String && (o['work'] as String).isNotEmpty;

  // ── The finish ───────────────────────────────────────────────────────────

  /// The wall to be finished, in m² to the hundredth: the whole main wall,
  /// less its doors and windows (new and old).
  double get finishAreaM2 {
    var area = widthMm * heightMm;
    for (final o in obstacles) {
      final left = _num(o['distance_from_left_mm']).clamp(0, widthMm);
      final right = (_num(o['distance_from_left_mm']) + _num(o['width_mm']))
          .clamp(0, widthMm);
      final bottom = _num(o['distance_from_floor_mm']).clamp(0, heightMm);
      final top = (_num(o['distance_from_floor_mm']) + _num(o['height_mm']))
          .clamp(0, heightMm);
      area -= (right - left) * (top - bottom);
    }
    return (area.clamp(0, double.infinity) / 1e6 * 100).round() / 100;
  }

  /// The record of a finish: what the price engines and the 3D page read.
  Map<String, dynamic> finish(String kind, {String? colour}) => {
        'kind': kind,
        'area_m2': finishAreaM2,
        if (colour != null) 'colour': colour,
      };

  // ── Where an opening can go ──────────────────────────────────────────────

  double _clearance(String type) => _num(
      catalog.layout
          .rules[type == 'door' ? 'door_clearance_mm' : 'window_clearance_mm'],
      50);

  /// What the wall would hold: an opening of [work] at [widthMm], left edge
  /// at [leftMm].
  Map<String, dynamic> record(String work, double widthMm, double leftMm) {
    final item = catalog.wallWork.openings[work]!;
    final height = item.heightMm.clamp(100.0, heightMm - item.sillMm - 50);
    return {
      'type': work == 'window' ? 'window' : 'door',
      'distance_from_left_mm': leftMm.roundToDouble(),
      'distance_from_floor_mm': item.sillMm,
      'width_mm': widthMm,
      'height_mm': height.toDouble(),
      'work': work,
    };
  }

  /// The free stretches of wall (from the left end, in mm) an opening as high
  /// as [o] can use: not over a cabinet at that height, not over another
  /// door or window, and clear of each by the catalogue's clearance.
  /// [except]: the index of the opening being moved or resized.
  List<({double start, double end, String after})> _free(Map<String, dynamic> o,
      {int? except}) {
    final type = o['type'] as String? ?? 'door';
    final gap = _clearance(type);
    final bottom = _num(o['distance_from_floor_mm']);
    final top = bottom + _num(o['height_mm']);
    final blocks = <({double from, double to, String name})>[
      (from: double.negativeInfinity, to: gap, name: 'the wall end'),
      (from: widthMm - gap, to: double.infinity, name: 'the wall end'),
    ];
    for (final c in _cabinets) {
      if ((c['run'] ?? 'main') != 'main') continue;
      final w = _num(c['width_mm']);
      final mount = _num(c['mount_mm']);
      final h = _num(c['height_mm']);
      // Overlapping in height only (a window above the worktop clears the
      // floor units).
      if (mount >= top || mount + h <= bottom) continue;
      final left = widthMm / 2 + _num(c['x_mm']) - w / 2;
      blocks.add((
        from: left - gap,
        to: left + w + gap,
        name: c['label'] as String? ?? 'a cabinet',
      ));
    }
    for (var i = 0; i < obstacles.length; i++) {
      if (i == except) continue;
      final other = obstacles[i];
      final left = _num(other['distance_from_left_mm']);
      final otherGap = _clearance(other['type'] as String? ?? 'door');
      final g = gap > otherGap ? gap : otherGap;
      blocks.add((
        from: left - g,
        to: left + _num(other['width_mm']) + g,
        name: nameOf(other).toLowerCase(),
      ));
    }
    blocks.sort((a, b) => a.from.compareTo(b.from));
    final free = <({double start, double end, String after})>[];
    var cursor = double.negativeInfinity;
    var after = 'the wall end';
    for (final b in blocks) {
      if (b.from > cursor && cursor.isFinite) {
        free.add((start: cursor, end: b.from, after: after));
      }
      if (b.to > cursor) {
        cursor = b.to;
        after = b.name;
      }
    }
    return free;
  }

  /// The widest free stretch an opening of [work] could use, in mm (0: none).
  double widestFreeMm(String work) {
    final probe = record(work, 1, 0);
    var best = 0.0;
    for (final f in _free(probe)) {
      if (f.end - f.start > best) best = f.end - f.start;
    }
    return best;
  }

  /// The obstacles with a new opening of [work] (its usual width, or the
  /// widest offered that fits) placed in the free stretch nearest [nearMm]
  /// (the spot double-tapped; else the middle of the wall), centred on it if
  /// it can be. Null if no free stretch is wide enough.
  List<Map<String, dynamic>>? add(String work, {double? nearMm}) {
    final item = catalog.wallWork.openings[work];
    if (item == null) return null;
    final widths = [
      item.widthMm,
      for (final w in [...item.widthsMm]..sort((a, b) => b.compareTo(a)))
        if (w != item.widthMm) w,
    ];
    final want = nearMm ?? widthMm / 2;
    for (final width in widths) {
      final free = _free(record(work, width, 0))
          .where((f) => f.end - f.start >= width)
          .toList();
      if (free.isEmpty) continue;
      double distance(({double start, double end, String after}) f) =>
          want < f.start ? f.start - want : (want > f.end ? want - f.end : 0);
      free.sort((a, b) => distance(a).compareTo(distance(b)));
      final f = free.first;
      final left = (want - width / 2).clamp(f.start, f.end - width);
      return [...obstacles, record(work, width, left.toDouble())];
    }
    return null;
  }

  /// Why [work] can't be added, or null if it can.
  String? whyNot(String work) {
    if (add(work) != null) return null;
    final widest = widestFreeMm(work).round();
    return widest <= 0
        ? 'No free wall for it: move or remove cabinets first'
        : 'Only $widest mm of free wall: move or remove cabinets first';
  }

  /// The opening [index] moved by [dxMm], as far as it can go that way.
  /// Null if it can't move at all.
  List<Map<String, dynamic>>? move(int index, double dxMm) {
    final o = obstacles[index];
    final left = _num(o['distance_from_left_mm']);
    final width = _num(o['width_mm']);
    final free = _free(o, except: index)
        .where((f) => f.start <= left + 1 && f.end >= left + width - 1);
    if (free.isEmpty) return null;
    final f = free.first;
    final to = (left + dxMm).clamp(f.start, f.end - width).roundToDouble();
    if ((to - left).abs() < 0.5) return null;
    return [
      for (var i = 0; i < obstacles.length; i++)
        i == index
            ? {...obstacles[i], 'distance_from_left_mm': to}
            : obstacles[i],
    ];
  }

  /// The widths the opening [index] can have, each with why not if it
  /// doesn't fit where it is (its left edge kept, else its right edge).
  List<({double widthMm, bool current, String? problem})> widthsFor(int index) {
    final o = obstacles[index];
    final item = catalog.wallWork.openings[o['work']];
    if (item == null) return const [];
    final widths = {...item.widthsMm, _num(o['width_mm'])}.toList()..sort();
    return [
      for (final w in widths)
        (
          widthMm: w,
          current: w == _num(o['width_mm']),
          problem: resize(index, w) != null || w == _num(o['width_mm'])
              ? null
              : 'Too wide for the ${_roomAround(index).round()} mm free here',
        ),
    ];
  }

  double _roomAround(int index) {
    final o = obstacles[index];
    final left = _num(o['distance_from_left_mm']);
    for (final f in _free(o, except: index)) {
      if (f.start <= left + 1 && f.end >= left + _num(o['width_mm']) - 1) {
        return f.end - f.start;
      }
    }
    return _num(o['width_mm']);
  }

  /// The opening [index] at [widthMm], its left edge kept (else its right
  /// edge); null if it doesn't fit.
  List<Map<String, dynamic>>? resize(int index, double widthMm) {
    final o = obstacles[index];
    final left = _num(o['distance_from_left_mm']);
    final right = left + _num(o['width_mm']);
    final free = _free(o, except: index)
        .where((f) => f.start <= left + 1 && f.end >= right - 1);
    if (free.isEmpty) return null;
    final f = free.first;
    double? at;
    if (left + widthMm <= f.end + 0.5) {
      at = left;
    } else if (right - widthMm >= f.start - 0.5) {
      at = right - widthMm;
    }
    if (at == null) return null;
    return [
      for (var i = 0; i < obstacles.length; i++)
        i == index
            ? {
                ...obstacles[i],
                'distance_from_left_mm': at,
                'width_mm': widthMm
              }
            : obstacles[i],
    ];
  }

  /// Without the opening [index]. Only one to be made can be taken out; one
  /// already there is part of the room.
  List<Map<String, dynamic>> remove(int index) => [
        for (var i = 0; i < obstacles.length; i++)
          if (i != index || !isNew(obstacles[i])) obstacles[i],
      ];

  static double _num(Object? v, [double fallback = 0]) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? fallback);
}
