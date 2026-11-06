import 'dart:convert';

import '../../../shared/platform/api_client.dart';
import '../../../shared/platform/local_store.dart';
import '../../../shared/project_status.dart';

/// Designs and quotes kept on the device (the phone's documents folder, or
/// the browser's storage), so nothing is lost when the app closes or the
/// network drops.
class OfflineStore {
  /// Also the file name on Android, so existing designs carry over.
  static const String _storeKey = 'static_trace_offline_drafts.json';
  static List<Map<String, dynamic>> _memoryCache = [];

  static Future<void> _persist(List<Map<String, dynamic>> drafts) =>
      writeLocal(_storeKey, jsonEncode(drafts));

  /// Saves or updates a quote in local storage
  static Future<void> saveDraft(Map<String, dynamic> draft) async {
    final quoteId = draft['quote_id'] ??
        'QT-OFFLINE-${DateTime.now().millisecondsSinceEpoch}';
    final toSave = Map<String, dynamic>.from(draft);
    toSave['quote_id'] = quoteId;
    toSave['is_offline_draft'] = true;
    toSave['saved_at'] = DateTime.now().toIso8601String();

    final drafts = await getDrafts();
    drafts.removeWhere((d) => d['quote_id'] == quoteId);
    drafts.insert(0, toSave);
    _memoryCache = drafts;
    await _persist(drafts);
  }

  /// Retrieves all local offline drafts
  static Future<List<Map<String, dynamic>>> getDrafts() async {
    final content = await readLocal(_storeKey);
    if (content != null) {
      try {
        final list = jsonDecode(content) as List<dynamic>;
        _memoryCache = list.cast<Map<String, dynamic>>();
      } catch (_) {
        // Unreadable: keep what's in memory.
      }
    }
    return _memoryCache;
  }

  /// Removes a draft once successfully synchronized with the cloud
  static Future<void> removeDraft(String quoteId) async {
    final drafts = await getDrafts();
    drafts.removeWhere((d) => d['quote_id'] == quoteId);
    _memoryCache = drafts;
    await _persist(drafts);
  }

  /// Saved records waiting to be sent: everything except work-in-progress
  /// drafts, which stay on the phone until the salesperson sends the quote.
  static Future<List<Map<String, dynamic>>> pendingSync() async {
    final drafts = await getDrafts();
    return drafts
        .where((d) => ProjectStatus.of(d) != ProjectStatus.draft)
        .toList();
  }

  /// Synchronizes all queued offline quotes with the FastAPI backend.
  static Future<int> syncQueue(String quoteEndpoint) async {
    final pending = await pendingSync();
    if (pending.isEmpty) return 0;

    int synced = 0;
    for (final draft in pending) {
      final reply = await ApiClient.postJson(Uri.parse(quoteEndpoint), draft);
      // Unreachable: stop and keep the rest for next time.
      if (reply == null) break;
      if (reply.ok) {
        await removeDraft(draft['quote_id'] as String);
        synced++;
      }
    }
    return synced;
  }
}
