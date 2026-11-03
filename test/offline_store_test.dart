import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/utils/offline_store.dart';

void main() {
  group('OfflineStore Unit Tests', () {
    test('Saves and retrieves offline drafts in memory/disk', () async {
      final sampleDraft = {
        'quote_id': 'QT-TEST-001',
        'client_name': 'Sarah Connor',
        'client_phone': '+61 400 999 888',
        'total_price': 4200.0,
        'style_archetype': 'minimalist',
        'placed_cabinets': [
          {'cabinet_type': 'base_800', 'x_mm': -400.0}
        ],
      };

      await OfflineStore.saveDraft(sampleDraft);
      final drafts = await OfflineStore.getDrafts();

      expect(drafts, isNotEmpty);
      expect(drafts.any((d) => d['quote_id'] == 'QT-TEST-001'), isTrue);
      expect(
          drafts
              .firstWhere((d) => d['quote_id'] == 'QT-TEST-001')['client_name'],
          'Sarah Connor');

      // Test removal upon sync
      await OfflineStore.removeDraft('QT-TEST-001');
      final remaining = await OfflineStore.getDrafts();
      expect(remaining.any((d) => d['quote_id'] == 'QT-TEST-001'), isFalse);
    });
  });
}
