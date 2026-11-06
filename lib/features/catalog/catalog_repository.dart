import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../shared/config.dart';
import '../../shared/platform/api_client.dart';
import '../../shared/platform/local_store.dart';
import 'price_catalog.dart';

/// How a refresh from the office server went.
enum CatalogSyncStatus {
  /// A catalogue arrived and is now in use (and kept for offline use).
  updated,

  /// The office has the version the app already uses.
  unchanged,

  /// The office could not be reached; the app keeps what it has.
  offline,

  /// The office answered with something that is not a usable catalogue; the
  /// app keeps what it has.
  rejected,
}

class CatalogSync {
  const CatalogSync(this.status, this.catalog);

  final CatalogSyncStatus status;

  /// What the app prices with after this attempt.
  final PriceCatalog catalog;
}

/// Keeps the app's catalogue (prices, sizes, finishes, tax) in step with the
/// office server, without ever making a quote wait for the network.
///
/// The app starts on the sample catalogue shipped inside it, switches to the
/// last copy it saved from the office as soon as the app opens, and swaps in
/// the office's current one when it can reach it. A reply that does not parse
/// is ignored, so a bad response can never leave the app without prices.
class CatalogRepository {
  const CatalogRepository._();

  /// The file (or browser storage key) holding the last catalogue received.
  static const cacheKey = 'static_trace_catalog.json';

  static Uri get url => Uri.parse('${AppConfig.backendBaseUrl}/api/catalog');

  /// Where the copy is kept; tests swap these for an in-memory map.
  @visibleForTesting
  static Future<String?> Function(String key) read = readLocal;
  @visibleForTesting
  static Future<void> Function(String key, String value) write = writeLocal;

  /// Puts the last saved copy into use. Returns it, or null if there is none
  /// (or it is damaged), in which case the app keeps what it has.
  static Future<PriceCatalog?> loadCached() async {
    final cached = _parse(await read(cacheKey));
    if (cached != null) PriceCatalog.current = cached;
    return cached;
  }

  /// Asks the office for its current catalogue and, if it is usable, puts it
  /// into use and keeps a copy for offline use.
  static Future<CatalogSync> refresh({Uri? from}) async {
    final before = PriceCatalog.current;
    final reply = await ApiClient.getJson(from ?? url);
    if (reply == null || !reply.ok) {
      return CatalogSync(CatalogSyncStatus.offline, before);
    }
    final fresh = _parse(reply.body);
    if (fresh == null) {
      return CatalogSync(CatalogSyncStatus.rejected, before);
    }
    PriceCatalog.current = fresh;
    await write(cacheKey, jsonEncode(fresh.json));
    return CatalogSync(
      fresh.version == before.version
          ? CatalogSyncStatus.unchanged
          : CatalogSyncStatus.updated,
      fresh,
    );
  }

  /// Cached copy first (instant, works offline), then the office.
  static Future<CatalogSync> sync({Uri? from}) async {
    await loadCached();
    return refresh(from: from);
  }

  static PriceCatalog? _parse(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return PriceCatalog.fromJson(decoded);
    } catch (_) {
      // Not JSON, or not the catalogue's shape (a missing or mistyped field).
      return null;
    }
  }
}
