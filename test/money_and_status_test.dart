import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/shared/money.dart';
import 'package:static_trace/shared/project_status.dart';

void main() {
  group('formatMoney', () {
    test('uses RM and thousands separators', () {
      expect(formatMoney(18450), 'RM 18,450');
      expect(formatMoney(999), 'RM 999');
      expect(formatMoney(1234567.8), 'RM 1,234,568');
    });

    test('shows cents when asked', () {
      expect(formatMoney(99.5, cents: true), 'RM 99.50');
      expect(formatMoney(1500, cents: true), 'RM 1,500.00');
    });

    test('puts the sign before the currency', () {
      expect(formatMoney(-130), '-RM 130');
    });
  });

  group('parseMoney', () {
    test('reads what a salesperson types', () {
      expect(parseMoney('1,500'), 1500);
      expect(parseMoney('RM 500.50'), 500.5);
      expect(parseMoney(' 250 '), 250);
    });

    test('returns null for nothing useful', () {
      expect(parseMoney(''), isNull);
      expect(parseMoney('abc'), isNull);
    });
  });

  group('ProjectStatus.of', () {
    test('a paid deposit always means deposit paid', () {
      expect(
        ProjectStatus.of({'status': 'draft', 'deposit_paid': 500.0}),
        ProjectStatus.deposit,
      );
    });

    test('reads saved statuses', () {
      expect(ProjectStatus.of({'status': 'draft'}), ProjectStatus.draft);
      expect(ProjectStatus.of({'status': 'quote'}), ProjectStatus.quote);
    });

    test('records from before statuses existed are sent quotes', () {
      expect(ProjectStatus.of({'quote_id': 'QT-1'}), ProjectStatus.quote);
    });

    test('labels are client-safe', () {
      expect(ProjectStatus.values.map((s) => s.label),
          ['Draft', 'Quote sent', 'Deposit paid']);
    });
  });
}
