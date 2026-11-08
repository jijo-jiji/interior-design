import 'dart:convert';

import 'package:flutter/services.dart';

/// The finish textures the 3D page puts on cabinets, worktops and the floor
/// (`assets/3d/textures/`, described by its `manifest.json`).
///
/// The page is loaded from a string, so it can't fetch files itself: after it
/// loads, the app hands it the manifest and each image as a data URL
/// (`registerFinishTextures`, `registerFinishFile`, `finishTexturesReady`).
/// Without them the page draws its own simpler textures.
class FinishTextures {
  const FinishTextures._();

  static const folder = 'assets/3d/textures/';

  /// The manifest and the data URLs, built once: about 4 MB of text. The
  /// result is kept, not the future, so every caller reads it in its own zone.
  static ({String manifest, Map<String, String> files})? _value;

  static Future<({String manifest, Map<String, String> files})> load(
      [AssetBundle? bundle]) async {
    return _value ??= await _read(bundle ?? rootBundle);
  }

  /// For tests, which read the assets again.
  static void forget() => _value = null;

  static Future<({String manifest, Map<String, String> files})> _read(
      AssetBundle bundle) async {
    final manifestText = await bundle.loadString('${folder}manifest.json');
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    final names = <String>{
      for (final entry in (manifest['textures'] as Map<String, dynamic>).values)
        for (final key in const ['albedo', 'normal', 'roughness'])
          if ((entry as Map<String, dynamic>)[key] != null)
            entry[key] as String,
      for (final value in (manifest['micro'] as Map<String, dynamic>).values)
        if (value is String && value.endsWith('.jpg')) value,
    };
    final files = <String, String>{};
    for (final name in names) {
      final bytes = await bundle.load('$folder$name');
      files[name] =
          'data:image/jpeg;base64,${base64Encode(bytes.buffer.asUint8List())}';
    }
    return (manifest: manifestText, files: files);
  }

  /// Hands everything to the page through [run] (one JavaScript call each, so
  /// no single call is huge). Returns false if the textures couldn't be read
  /// or sent, in which case the page keeps its own.
  static Future<bool> send(
    Future<void> Function(String javaScript) run, {
    AssetBundle? bundle,
  }) async {
    try {
      final loaded = await load(bundle);
      await run('registerFinishTextures(${jsonEncode(loaded.manifest)})');
      for (final entry in loaded.files.entries) {
        await run(
            'registerFinishFile(${jsonEncode(entry.key)}, ${jsonEncode(entry.value)})');
      }
      await run('finishTexturesReady()');
      return true;
    } catch (_) {
      return false;
    }
  }
}
