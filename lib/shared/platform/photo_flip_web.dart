import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Draws the photo at [path] (a `blob:` URL) flipped left-to-right and
/// returns a `blob:` URL for the flipped copy. Returns [path] unchanged if
/// the browser can't do it, so a photo is never lost.
Future<String> unmirrorPhoto(String path) async {
  try {
    final image = web.HTMLImageElement()..src = path;
    await image.decode().toDart;
    final w = image.naturalWidth, h = image.naturalHeight;
    final canvas = web.HTMLCanvasElement()
      ..width = w
      ..height = h;
    canvas.context2D
      ..translate(w.toDouble(), 0)
      ..scale(-1, 1)
      ..drawImage(image, 0, 0);
    final done = Completer<web.Blob?>();
    canvas.toBlob(
      ((web.Blob? blob) => done.complete(blob)).toJS,
      'image/jpeg',
      0.92.toJS,
    );
    final blob = await done.future;
    if (blob == null) return path;
    web.URL.revokeObjectURL(path);
    return web.URL.createObjectURL(blob);
  } catch (_) {
    return path;
  }
}
