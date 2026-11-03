import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../../../shared/project_status.dart';

/// True local offline storage for customer proposals & digital signatures.
/// Ensures on-site field quotes are preserved across app closures or lost connectivity.
class OfflineStore {
  static const String _fileName = 'static_trace_offline_drafts.json';
  static List<Map<String, dynamic>> _memoryCache = [];

  static Future<File?> _getLocalFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      // In test environments where path_provider is not mocked
      return null;
    }
  }

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

    final file = await _getLocalFile();
    if (file != null) {
      await file.writeAsString(jsonEncode(drafts));
    }
  }

  /// Retrieves all local offline drafts
  static Future<List<Map<String, dynamic>>> getDrafts() async {
    final file = await _getLocalFile();
    if (file != null && await file.exists()) {
      try {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _memoryCache = list.cast<Map<String, dynamic>>();
        return _memoryCache;
      } catch (_) {
        return _memoryCache;
      }
    }
    return _memoryCache;
  }

  /// Removes a draft once successfully synchronized with the cloud
  static Future<void> removeDraft(String quoteId) async {
    final drafts = await getDrafts();
    drafts.removeWhere((d) => d['quote_id'] == quoteId);
    _memoryCache = drafts;

    final file = await _getLocalFile();
    if (file != null) {
      await file.writeAsString(jsonEncode(drafts));
    }
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
    final client = HttpClient();

    for (final draft in pending) {
      try {
        final req = await client.postUrl(Uri.parse(quoteEndpoint));
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        req.write(jsonEncode(draft));
        final resp = await req.close();
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          await removeDraft(draft['quote_id']);
          synced++;
        }
      } catch (_) {
        // Stop on first network failure; preserve remaining drafts
        break;
      }
    }
    client.close();
    return synced;
  }
}
