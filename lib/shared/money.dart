import 'sales_config.dart';

final _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// Formats an amount with the company currency and thousands separators:
/// `formatMoney(18450)` → "RM 18,450", `formatMoney(99.5, cents: true)` →
/// "RM 99.50".
String formatMoney(num amount, {bool cents = false}) {
  final fixed = amount.abs().toStringAsFixed(cents ? 2 : 0);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAll(_thousands, ',');
  final sign = amount < 0 ? '-' : '';
  final decimals = cents ? '.${parts[1]}' : '';
  return '$sign${SalesConfig.currency} $whole$decimals';
}

/// Parses what a salesperson types into an amount field ("1,500", "RM 500").
double? parseMoney(String text) {
  final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}
