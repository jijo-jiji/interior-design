import '../../catalog/price_catalog.dart';

/// Prices a kitchen. Every number comes from the [PriceCatalog]; the rules
/// are the same as the office server's and the Studio's (see
/// assets/catalog and test/fixtures/pricing_cases.json), so the figure on the
/// tablet is the figure on the PDF the client signs.
class CPQEngine {
  // The catalogue's tables, under the names the screens already use.
  static Map<String, double> get cabinetPrices => {
        for (final m in PriceCatalog.current.modules) m.type: m.price,
      };
  static Map<String, double> get styleMultipliers => {
        for (final e in PriceCatalog.current.styleOptions.entries)
          e.key: e.value.multiplier,
      };
  static Map<String, String> get styleNames => {
        for (final e in PriceCatalog.current.styleOptions.entries)
          e.key: e.value.name,
      };
  static Map<String, double> get benchtopRates => {
        for (final e in PriceCatalog.current.benchtopOptions.entries)
          e.key: e.value.ratePerM,
      };
  static Map<String, String> get benchtopNames => {
        for (final e in PriceCatalog.current.benchtopOptions.entries)
          e.key: e.value.name,
      };
  static double get labourRatePerCabinet => PriceCatalog.current.labourRate;
  static double get windowAllowance =>
      PriceCatalog.current.obstacleAllowances['window'] ?? 0;
  static double get doorAllowance =>
      PriceCatalog.current.obstacleAllowances['door'] ?? 0;

  /// Malaysian service tax, from the catalogue (the wire field is still
  /// called `gst`, so stored consultations keep working).
  static double get gstRate => PriceCatalog.current.taxRate;

  static double _round2(double v) => (v * 100).round() / 100;

  static CPQSummary calculate({
    required List<Map<String, dynamic>> placedCabinets,
    required List<dynamic> obstacles,
    required String styleArchetype,
    String? benchtopMaterial,
    PriceCatalog? catalog,
    Map<String, dynamic>? wallFinish,
  }) {
    final cat = catalog ?? PriceCatalog.current;
    final style = cat.styleOptions[styleArchetype];
    final mult = style?.multiplier ?? 1.00;

    // One line per type and width, in first-seen order; each unit price is
    // rounded to the sen before it is multiplied (as the server does).
    final groups = <String, ({String type, double? width, int qty})>{};
    for (final cab in placedCabinets) {
      final type = cab['cabinet_type'] as String? ?? 'base_600';
      final width = (cab['width_mm'] as num?)?.toDouble();
      final key = '$type|${(width ?? 0).round()}';
      final seen = groups[key];
      groups[key] = (type: type, width: width, qty: (seen?.qty ?? 0) + 1);
    }

    final groupTotals = <String, double>{
      'base': 0,
      'wall': 0,
      'tall': 0,
      'corner': 0,
    };
    var cabinetsTotal = 0.0;
    for (final g in groups.values) {
      final unit = _round2(cat.unitPrice(g.type, g.width) * mult);
      final total = _round2(unit * g.qty);
      cabinetsTotal += total;
      groupTotals[cat.groupOf(g.type)] =
          (groupTotals[cat.groupOf(g.type)] ?? 0) + total;
    }

    final labourModules =
        placedCabinets.where((c) => cat.carriesLabour(_typeOf(c))).length;
    final labourTotal = _round2(cat.labourRate * labourModules);

    var metres = 0.0;
    for (final cab in placedCabinets) {
      metres += cat.benchtopMetres(
          _typeOf(cab), (cab['width_mm'] as num?)?.toDouble());
    }
    metres = (metres * 1000).round() / 1000;

    // Benchtop stone calculation (optional material)
    final benchtop =
        benchtopMaterial == null ? null : cat.benchtopOptions[benchtopMaterial];
    final benchtopTotal =
        (benchtop != null && benchtop.ratePerM > 0 && metres > 0)
            ? _round2(benchtop.ratePerM * metres)
            : 0.0;

    var obstacleAllowance = 0.0;
    for (final obs in obstacles) {
      final type = (obs is Map ? obs['type'] : null) as String? ?? '';
      obstacleAllowance += cat.obstacleAllowances[type] ?? 0;
    }

    final wallLines = wallWorkLines(cat, obstacles, wallFinish);
    final wallWorkTotal =
        _round2(wallLines.fold(0.0, (sum, line) => sum + line.total));

    final subtotal = _round2(cabinetsTotal +
            labourTotal +
            benchtopTotal +
            obstacleAllowance +
            wallWorkTotal)
        .clamp(0.0, double.infinity);
    final gst = _round2(subtotal * cat.taxRate);
    final totalPrice = _round2(subtotal + gst);

    // 36-month estimate with 6% interest factor
    final monthlyPayment = totalPrice > 0 ? (totalPrice / 36.0 * 1.06) : 0.0;

    return CPQSummary(
      baseCabinetTotal: groupTotals['base']!,
      wallCabinetTotal: groupTotals['wall']!,
      tallCabinetTotal: groupTotals['tall']!,
      cornerCabinetTotal: groupTotals['corner']!,
      benchtopTotal: benchtopTotal,
      benchtopLinearMetres: metres,
      benchtopMaterial: benchtop?.name,
      labourTotal: labourTotal,
      obstacleAllowance: obstacleAllowance,
      wallWorkTotal: wallWorkTotal,
      wallWorkLines: wallLines,
      subtotal: subtotal,
      gst: gst,
      totalPrice: totalPrice,
      monthlyPayment: monthlyPayment,
      totalModules: placedCabinets.length,
      labourModules: labourModules,
      styleArchetype: styleArchetype,
      styleName: style?.name ?? 'Custom',
      materialMultiplier: mult,
      catalogVersion: cat.version,
    );
  }

  static String _typeOf(Map<String, dynamic> cab) =>
      cab['cabinet_type'] as String? ?? 'base_600';

  /// The quote lines for openings to be made in the wall (an obstacle with a
  /// `work` the catalogue lists: one line per kind, in first-seen order) and
  /// the wall's finish (`{kind, area_m2}`, the area rounded to 0.01 m² before
  /// it is priced). No finish multiplier; the same rule as the server's.
  static List<QuoteLine> wallWorkLines(PriceCatalog cat, List<dynamic> obstacles,
      Map<String, dynamic>? wallFinish) {
    final lines = <QuoteLine>[];
    final counts = <String, int>{};
    for (final obs in obstacles) {
      final work = obs is Map ? obs['work'] : null;
      if (work is String && cat.wallWork.openings.containsKey(work)) {
        counts[work] = (counts[work] ?? 0) + 1;
      }
    }
    for (final e in counts.entries) {
      final item = cat.wallWork.openings[e.key]!;
      lines.add(QuoteLine(
        description: 'Wall work \u2014 ${item.name}',
        qty: e.value,
        unitPrice: item.price,
        total: _round2(item.price * e.value),
      ));
    }
    if (wallFinish != null) {
      final finish = cat.wallWork.finishes[wallFinish['kind']];
      final area = _round2((wallFinish['area_m2'] as num?)?.toDouble() ?? 0);
      if (finish != null && finish.ratePerM2 > 0 && area > 0) {
        final total = _round2(finish.ratePerM2 * area);
        lines.add(QuoteLine(
          description: 'Wall finish \u2014 ${finish.name} '
              '(${area.toStringAsFixed(2)} m\u00b2 @ '
              '${cat.currencySymbol}${finish.ratePerM2.toStringAsFixed(0)}/m\u00b2)',
          qty: 1,
          unitPrice: total,
          total: total,
        ));
      }
    }
    return lines;
  }
}

/// One line of a quote, as the server prints it.
class QuoteLine {
  const QuoteLine({
    required this.description,
    required this.qty,
    required this.unitPrice,
    required this.total,
  });

  final String description;
  final int qty;
  final double unitPrice;
  final double total;
}

class CPQSummary {
  final double baseCabinetTotal;
  final double wallCabinetTotal;
  final double tallCabinetTotal;
  final double cornerCabinetTotal;
  final double benchtopTotal;
  final double benchtopLinearMetres;
  final String? benchtopMaterial;
  final double labourTotal;
  final double obstacleAllowance;

  /// Openings to be made in the wall and its finish, and their lines.
  final double wallWorkTotal;
  final List<QuoteLine> wallWorkLines;
  final double subtotal;
  final double gst;
  final double totalPrice;
  final double monthlyPayment;
  final int totalModules;

  /// How many of them carry installation labour (fillers don't).
  final int labourModules;

  /// The catalogue version this was priced with.
  final int catalogVersion;
  final String styleArchetype;
  final String styleName;
  final double materialMultiplier;

  const CPQSummary({
    required this.baseCabinetTotal,
    required this.wallCabinetTotal,
    required this.tallCabinetTotal,
    required this.cornerCabinetTotal,
    this.benchtopTotal = 0.0,
    this.benchtopLinearMetres = 0.0,
    this.benchtopMaterial,
    required this.labourTotal,
    required this.obstacleAllowance,
    this.wallWorkTotal = 0.0,
    this.wallWorkLines = const [],
    required this.subtotal,
    required this.gst,
    required this.totalPrice,
    required this.monthlyPayment,
    required this.totalModules,
    required this.labourModules,
    required this.catalogVersion,
    required this.styleArchetype,
    required this.styleName,
    required this.materialMultiplier,
  });
}
