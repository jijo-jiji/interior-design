/// Business settings that clients see on screen.
///
/// One place to change them per company (SS Love is the first). The tax rate
/// itself still lives in CPQEngine.gstRate while pricing is on hold; confirm
/// the SST treatment, deposit rules and price list with the owner before
/// showing real quotes.
class SalesConfig {
  SalesConfig._();

  static const String brandName = 'SS Love';
  static const String brandTagline = 'Kitchens & built-in cabinets';

  /// Shown before every amount, e.g. "RM 18,450".
  static const String currency = 'RM';

  /// Label for the tax line in the price breakdown.
  static const String taxLabel = 'SST';
}
