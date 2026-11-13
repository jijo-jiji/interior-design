import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// A model bundled with the app, saved as a file for ONNX Runtime to open.
///
/// The copy is named after its contents. flutter_onnxruntime's own
/// createSessionFromAsset saves it under its bare file name and reuses that
/// copy whenever it exists, so after an app update with a new model the
/// tablet kept running the old one.
Future<String> modelFile(String asset) async {
  final data = await rootBundle.load(asset);
  final bytes =
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return saveModel(asset, bytes, await getTemporaryDirectory());
}

/// [bytes] saved in [dir] as `<name>-<fingerprint>.<ext>`, unless that copy
/// is already there. Older copies of the same model are deleted, including
/// the one the plugin saved under the bare name. Returns the file's path.
Future<String> saveModel(String asset, Uint8List bytes, Directory dir) async {
  final name = asset.split('/').last;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  final print = await compute(fingerprint, bytes);
  final file = File('${dir.path}${Platform.pathSeparator}$base-$print$ext');

  if (!await file.exists() || await file.length() != bytes.length) {
    await dir.create(recursive: true);
    // Written aside, then renamed: a half-written file is never reused.
    final part = File('${file.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await part.rename(file.path);
  }

  await for (final entry in dir.list()) {
    if (entry is! File || entry.path == file.path) continue;
    final other = entry.uri.pathSegments.last;
    final older = other == name ||
        (other.startsWith('$base-') && other.endsWith(ext) &&
            other.length == base.length + 1 + print.length + ext.length);
    if (older) {
      try {
        await entry.delete();
      } on FileSystemException {
        // In use or gone already: harmless, it's only a stale copy.
      }
    }
  }
  return file.path;
}

/// FNV-1a (64-bit) of [bytes], as 16 hex digits: the same bytes always give
/// the same name, and a changed model a different one.
String fingerprint(Uint8List bytes) {
  var h = -0x340d631b7bdddcdb; // 0xcbf29ce484222325, the FNV offset basis
  const prime = 0x100000001b3;
  for (final b in bytes) {
    h = (h ^ b) * prime; // wraps at 64 bits, as FNV expects
  }
  // In two halves: an int is signed, so it can't print as a 64-bit unsigned.
  String half(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
  return half(h >> 32) + half(h);
}
