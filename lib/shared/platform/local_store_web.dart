import 'package:web/web.dart' as web;

/// The text saved under [key], or null if there is none.
Future<String?> readLocal(String key) async {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    // Storage blocked (private browsing, site data off).
    return null;
  }
}

/// Saves [value] under [key], replacing what was there.
Future<void> writeLocal(String key, String value) async {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {
    // Storage full or blocked: the copy in memory is all there is.
  }
}
