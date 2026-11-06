import 'dart:convert';

import 'default_catalog.g.dart';

/// How a family of modules carries benchtop.
enum BenchtopMode {
  /// A worktop over the module's width.
  width,

  /// A fixed length (a corner unit's two wings).
  fixed,

  /// No worktop (wall units, tall units).
  none;

  static BenchtopMode parse(Object? value) => switch (value) {
        'fixed' => BenchtopMode.fixed,
        'none' => BenchtopMode.none,
        _ => BenchtopMode.width,
      };
}

double _d(Object? v, [double fallback = 0]) =>
    (v as num?)?.toDouble() ?? fallback;

/// A fixed module the apps can add: its size and its price.
class CatalogModule {
  const CatalogModule({
    required this.type,
    required this.label,
    required this.section,
    required this.widthMm,
    required this.heightMm,
    required this.depthMm,
    required this.mountMm,
    required this.price,
  });

  factory CatalogModule.fromJson(Map<String, dynamic> j) => CatalogModule(
        type: j['type'] as String,
        label: j['label'] as String,
        section: j['section'] as String,
        widthMm: _d(j['width_mm']),
        heightMm: _d(j['height_mm']),
        depthMm: _d(j['depth_mm']),
        mountMm: _d(j['mount_mm']),
        price: _d(j['price']),
      );

  final String type;
  final String label;

  /// `cabinet` or `appliance`.
  final String section;
  final double widthMm;
  final double heightMm;
  final double depthMm;
  final double mountMm;
  final double price;

  bool get isAppliance => section == 'appliance';
}

/// price = atRef + (width - refWidthMm) / 100 * per100mm.
class PriceRule {
  const PriceRule(
      {required this.atRef, required this.refWidthMm, required this.per100mm});

  factory PriceRule.fromJson(Map<String, dynamic> j) => PriceRule(
        atRef: _d(j['at_ref']),
        refWidthMm: _d(j['ref_width_mm']),
        per100mm: _d(j['per_100mm']),
      );

  final double atRef;
  final double refWidthMm;
  final double per100mm;
}

/// How a kind of module is priced and counted (matched by type prefix).
class CatalogFamily {
  const CatalogFamily({
    required this.id,
    required this.label,
    required this.prefixes,
    required this.group,
    required this.benchtop,
    required this.benchtopM,
    required this.labour,
    required this.appliance,
    this.price,
  });

  factory CatalogFamily.fromJson(Map<String, dynamic> j) => CatalogFamily(
        id: j['id'] as String,
        label: j['label'] as String,
        prefixes: [for (final p in j['prefixes'] as List) p as String],
        group: j['group'] as String,
        benchtop: BenchtopMode.parse(j['benchtop']),
        benchtopM: _d(j['benchtop_m']),
        labour: j['labour'] as bool? ?? true,
        appliance: j['appliance'] as bool? ?? false,
        price: j['price'] == null
            ? null
            : PriceRule.fromJson(j['price'] as Map<String, dynamic>),
      );

  final String id;
  final String label;
  final List<String> prefixes;

  /// `base`, `wall`, `tall` or `corner`: which line of the breakdown it joins.
  final String group;
  final BenchtopMode benchtop;
  final double benchtopM;
  final bool labour;
  final bool appliance;
  final PriceRule? price;
}

class StyleOption {
  const StyleOption({required this.name, required this.multiplier});

  final String name;
  final double multiplier;
}

class BenchtopOption {
  const BenchtopOption({required this.name, required this.ratePerM});

  final String name;
  final double ratePerM;
}

/// Everything the layout generator works with: module widths and sizes, and
/// the design rules.
class LayoutSpec {
  LayoutSpec(Map<String, dynamic> j)
      : baseDoorWidthsMm = _list(j['base_door_widths_mm']),
        drawerWidthsMm = _list(j['drawer_widths_mm']),
        sinkWidthsMm = _list(j['sink_widths_mm']),
        hobWidthsMm = _list(j['hob_widths_mm']),
        wallWidthsMm = _list(j['wall_widths_mm']),
        tallWidthMm = _d(j['tall_width_mm']),
        cornerSizeMm = _d(j['corner_size_mm']),
        baseHeightMm = _d(j['base_height_mm']),
        baseDepthMm = _d(j['base_depth_mm']),
        counterHeightMm = _d(j['counter_height_mm']),
        wallHeightMm = _d(j['wall_height_mm']),
        wallDepthMm = _d(j['wall_depth_mm']),
        wallMountMm = _d(j['wall_mount_mm']),
        tallHeightMm = _d(j['tall_height_mm']),
        tallDepthMm = _d(j['tall_depth_mm']),
        rules = (j['rules'] as Map<String, dynamic>);

  static List<double> _list(Object? v) =>
      [for (final w in v as List) (w as num).toDouble()];

  final List<double> baseDoorWidthsMm;
  final List<double> drawerWidthsMm;
  final List<double> sinkWidthsMm;
  final List<double> hobWidthsMm;
  final List<double> wallWidthsMm;
  final double tallWidthMm;
  final double cornerSizeMm;
  final double baseHeightMm;
  final double baseDepthMm;
  final double counterHeightMm;
  final double wallHeightMm;
  final double wallDepthMm;
  final double wallMountMm;
  final double tallHeightMm;
  final double tallDepthMm;

  /// The raw rules (read by `KitchenRules.fromJson`).
  final Map<String, dynamic> rules;
}

/// The catalogue: prices, sizes, finishes, tax and the pricing rules, as data.
///
/// The server owns it (`GET /api/catalog`); the app keeps a copy for offline
/// use. [current] is what every price and layout in the app reads. It starts
/// as the sample catalogue embedded in the app, so prices work from the first
/// launch with no network.
class PriceCatalog {
  PriceCatalog.fromJson(Map<String, dynamic> j)
      : json = j,
        version = (j['version'] as num).toInt(),
        name = j['name'] as String,
        isPlaceholder = j['is_placeholder'] as bool? ?? true,
        currencySymbol = j['currency_symbol'] as String? ?? 'RM',
        taxLabel = (j['tax'] as Map)['label'] as String,
        taxRate = _d((j['tax'] as Map)['rate']),
        labourRate = _d(j['labour_rate_per_cabinet']),
        unknownModulePrice = _d(j['unknown_module_price'], 300),
        obstacleAllowances = {
          for (final e in (j['obstacle_allowances'] as Map).entries)
            e.key as String: _d(e.value),
        },
        styleOptions = {
          for (final e in (j['style_options'] as Map).entries)
            e.key as String: StyleOption(
              name: (e.value as Map)['name'] as String,
              multiplier: _d((e.value as Map)['multiplier'], 1),
            ),
        },
        benchtopOptions = {
          for (final e in (j['benchtop_options'] as Map).entries)
            e.key as String: BenchtopOption(
              name: (e.value as Map)['name'] as String,
              ratePerM: _d((e.value as Map)['rate_per_m']),
            ),
        },
        modules = [
          for (final m in j['modules'] as List)
            CatalogModule.fromJson(m as Map<String, dynamic>),
        ],
        families = [
          for (final f in j['families'] as List)
            CatalogFamily.fromJson(f as Map<String, dynamic>),
        ],
        layout = LayoutSpec(j['layout'] as Map<String, dynamic>) {
    _modulesByType = {for (final m in modules) m.type: m};
  }

  /// The sample catalogue shipped inside the app.
  factory PriceCatalog.builtIn() => PriceCatalog.fromJson(
      jsonDecode(kDefaultCatalogJson) as Map<String, dynamic>);

  /// What the app prices and lays out with. Replaced when a newer catalogue
  /// arrives from the server (see `CatalogRepository`).
  static PriceCatalog current = PriceCatalog.builtIn();

  /// The document as received, kept so it can be cached as it was.
  final Map<String, dynamic> json;
  final int version;
  final String name;

  /// True while the numbers are samples.
  final bool isPlaceholder;
  final String currencySymbol;
  final String taxLabel;
  final double taxRate;
  final double labourRate;
  final double unknownModulePrice;
  final Map<String, double> obstacleAllowances;
  final Map<String, StyleOption> styleOptions;
  final Map<String, BenchtopOption> benchtopOptions;
  final List<CatalogModule> modules;
  final List<CatalogFamily> families;
  final LayoutSpec layout;

  late final Map<String, CatalogModule> _modulesByType;

  CatalogModule? module(String type) => _modulesByType[type];

  /// The family with the longest prefix of [type], if any.
  CatalogFamily? familyFor(String type) {
    CatalogFamily? best;
    var bestLength = -1;
    for (final family in families) {
      for (final prefix in family.prefixes) {
        if (type.startsWith(prefix) && prefix.length > bestLength) {
          best = family;
          bestLength = prefix.length;
        }
      }
    }
    return best;
  }

  /// The list price of one module, before the finish multiplier: its own
  /// price if it is a fixed module, else its family's price for [widthMm],
  /// else the unknown-module price.
  double unitPrice(String type, double? widthMm) {
    final fixed = module(type);
    if (fixed != null) return fixed.price;
    final rule = familyFor(type)?.price;
    if (rule != null) {
      final width =
          (widthMm == null || widthMm == 0) ? rule.refWidthMm : widthMm;
      final price =
          rule.atRef + (width - rule.refWidthMm) / 100 * rule.per100mm;
      return price < 0 ? 0 : price;
    }
    return unknownModulePrice;
  }

  double benchtopMetres(String type, double? widthMm) {
    final family = familyFor(type);
    if (family == null || family.benchtop == BenchtopMode.none) return 0;
    if (family.benchtop == BenchtopMode.fixed) return family.benchtopM;
    final width = (widthMm == null || widthMm == 0)
        ? (family.price?.refWidthMm ?? 600)
        : widthMm;
    return width / 1000;
  }

  bool carriesLabour(String type) => familyFor(type)?.labour ?? true;
  bool isAppliance(String type) => familyFor(type)?.appliance ?? false;
  String groupOf(String type) => familyFor(type)?.group ?? 'base';

  /// The fixed modules a salesperson can add by hand, in catalogue order.
  List<CatalogModule> get cabinetModules => [
        for (final m in modules)
          if (!m.isAppliance) m
      ];
  List<CatalogModule> get applianceModules => [
        for (final m in modules)
          if (m.isAppliance) m
      ];
}
