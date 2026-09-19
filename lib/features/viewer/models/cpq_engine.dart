class CPQEngine {
  static const Map<String, double> cabinetPrices = {
    'base_800': 420.00,
    'base_600': 340.00,
    'wall_600': 280.00,
    'tall_600': 620.00,
    'corner_900': 580.00,
    // Appliance modules: cabinetry, cutouts and services for each unit.
    'sink_600': 480.00,
    'cooktop_600': 520.00,
    'dishwasher_600': 360.00,
    'oven_tower_600': 1450.00,
    'fridge_recess_700': 390.00,
    'rangehood_900': 690.00,
  };

  /// Which modules carry benchtop over them. Mirrored in backend/main.py and
  /// frontend/src/pricing.ts — the pricing contract test fails if they drift.
  static const List<String> benchtopTypePrefixes = [
    'base', 'corner', 'sink', 'cooktop', 'dishwasher',
  ];

  static bool _carriesBenchtop(String type) =>
      benchtopTypePrefixes.any(type.startsWith);

  static const Map<String, double> styleMultipliers = {
    'japandi': 1.00,
    'minimalist': 1.08,
    'nordic': 1.12,
    'industrial': 1.18,
  };

  static const Map<String, String> styleNames = {
    'japandi': 'Japandi Natural',
    'minimalist': 'Modern Minimalist',
    'nordic': 'Warm Nordic',
    'industrial': 'Industrial Luxe',
  };

  static const double labourRatePerCabinet = 120.00;
  static const double windowAllowance = -50.00;
  static const double doorAllowance = -80.00;
  // Malaysian service tax. Mirrors GST_RATE in backend/main.py; the field is
  // still named gst on the wire so stored consultations keep working.
  static const double gstRate = 0.08;

  static const Map<String, double> benchtopRates = {
    'quartz_calacatta': 380.00,
    'granite_black': 480.00,
    'laminate_matte': 160.00,
  };

  static const Map<String, String> benchtopNames = {
    'quartz_calacatta': 'Calacatta Engineered Quartz',
    'granite_black': 'Nero Absolute Granite',
    'laminate_matte': 'Ultra-Matte Mineral Laminate',
  };

  static CPQSummary calculate({
    required List<Map<String, dynamic>> placedCabinets,
    required List<dynamic> obstacles,
    required String styleArchetype,
    String? benchtopMaterial,
  }) {
    final mult = styleMultipliers[styleArchetype] ?? 1.00;

    double baseCabinetTotal = 0.0;
    double wallCabinetTotal = 0.0;
    double tallCabinetTotal = 0.0;
    double cornerCabinetTotal = 0.0;
    double benchtopLinearMetres = 0.0;

    for (final cab in placedCabinets) {
      final type = cab['cabinet_type'] as String? ?? 'base_600';
      final basePrice = cabinetPrices[type] ?? 300.00;
      final adjustedPrice = basePrice * mult;

      if (type.startsWith('corner')) {
        cornerCabinetTotal += adjustedPrice;
        benchtopLinearMetres += 1.8; // 900mm along each wing
      } else if (type.startsWith('wall') || type.startsWith('rangehood')) {
        wallCabinetTotal += adjustedPrice;
      } else if (type.startsWith('tall') ||
          type.startsWith('oven_tower') ||
          type.startsWith('fridge')) {
        tallCabinetTotal += adjustedPrice;
      } else {
        baseCabinetTotal += adjustedPrice;
        if (_carriesBenchtop(type)) {
          final wMm = (cab['width_mm'] as num?)?.toDouble() ??
              (type == 'base_800' ? 800.0 : 600.0);
          benchtopLinearMetres += wMm * 0.001;
        }
      }
    }

    final int totalModules = placedCabinets.length;
    final double labourTotal = totalModules * labourRatePerCabinet;

    // Benchtop stone calculation (optional material)
    double benchtopTotal = 0.0;
    if (benchtopMaterial != null && benchtopRates.containsKey(benchtopMaterial)) {
      final rate = benchtopRates[benchtopMaterial]!;
      benchtopTotal = benchtopLinearMetres * rate;
    }

    double obstacleAllowance = 0.0;
    for (final obs in obstacles) {
      final obsType = obs['type'] as String? ?? '';
      if (obsType == 'window') obstacleAllowance += windowAllowance;
      else if (obsType == 'door') obstacleAllowance += doorAllowance;
    }

    final rawMaterialsTotal = baseCabinetTotal + wallCabinetTotal + tallCabinetTotal + cornerCabinetTotal + benchtopTotal;
    final subtotal = (rawMaterialsTotal + labourTotal + obstacleAllowance).clamp(0.0, double.infinity);
    final gst = subtotal * gstRate;
    final totalPrice = subtotal + gst;

    // 36-month estimate with 6% interest factor
    final monthlyPayment = totalPrice > 0 ? (totalPrice / 36.0 * 1.06) : 0.0;

    return CPQSummary(
      baseCabinetTotal: baseCabinetTotal,
      wallCabinetTotal: wallCabinetTotal,
      tallCabinetTotal: tallCabinetTotal,
      cornerCabinetTotal: cornerCabinetTotal,
      benchtopTotal: benchtopTotal,
      benchtopLinearMetres: benchtopLinearMetres,
      benchtopMaterial: benchtopMaterial != null ? benchtopNames[benchtopMaterial] : null,
      labourTotal: labourTotal,
      obstacleAllowance: obstacleAllowance,
      subtotal: subtotal,
      gst: gst,
      totalPrice: totalPrice,
      monthlyPayment: monthlyPayment,
      totalModules: totalModules,
      styleArchetype: styleArchetype,
      styleName: styleNames[styleArchetype] ?? 'Custom',
      materialMultiplier: mult,
    );
  }
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
  final double subtotal;
  final double gst;
  final double totalPrice;
  final double monthlyPayment;
  final int totalModules;
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
    required this.subtotal,
    required this.gst,
    required this.totalPrice,
    required this.monthlyPayment,
    required this.totalModules,
    required this.styleArchetype,
    required this.styleName,
    required this.materialMultiplier,
  });
}
