import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File?> _file(String key) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$key');
  } catch (_) {
    // No documents folder (e.g. in tests): nothing is kept on disk.
    return null;
  }
}

/// The text saved under [key], or null if there is none.
Future<String?> readLocal(String key) async {
  final file = await _file(key);
  if (file == null || !await file.exists()) return null;
  try {
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

/// Saves [value] under [key], replacing what was there.
Future<void> writeLocal(String key, String value) async {
  final file = await _file(key);
  if (file != null) await file.writeAsString(value);
}
