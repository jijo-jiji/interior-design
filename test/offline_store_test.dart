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

    test('Work-in-progress drafts stay on the phone and are never sent',
        () async {
      await OfflineStore.saveDraft({
        'quote_id': 'QT-DRAFT-001',
        'status': 'draft',
        'client_name': 'Puan Aminah',
      });

      final pending = await OfflineStore.pendingSync();
      expect(pending.any((d) => d['quote_id'] == 'QT-DRAFT-001'), isFalse);

      // Nothing to send, so no network call is made and the draft is kept.
      final sent = await OfflineStore.syncQueue('http://127.0.0.1:9/quote');
      expect(sent, 0);
      final drafts = await OfflineStore.getDrafts();
      expect(drafts.any((d) => d['quote_id'] == 'QT-DRAFT-001'), isTrue);

      await OfflineStore.removeDraft('QT-DRAFT-001');
    });

    test('Saving the same quote number again updates it in place', () async {
      await OfflineStore.saveDraft({'quote_id': 'QT-SAME', 'status': 'draft'});
      await OfflineStore.saveDraft({'quote_id': 'QT-SAME', 'status': 'quote'});

      final matches = (await OfflineStore.getDrafts())
          .where((d) => d['quote_id'] == 'QT-SAME')
          .toList();
      expect(matches, hasLength(1));
      expect(matches.single['status'], 'quote');
      expect(
          (await OfflineStore.pendingSync())
              .any((d) => d['quote_id'] == 'QT-SAME'),
          isTrue);

      await OfflineStore.removeDraft('QT-SAME');
    });
  });
}
