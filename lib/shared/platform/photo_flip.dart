/// Undoes the mirror image the browser camera plugin makes of photos from
/// front-facing or unlabelled cameras (most laptop webcams). A mirrored wall
/// photo would put every window on the wrong side.
library;

export 'photo_flip_io.dart' if (dart.library.js_interop) 'photo_flip_web.dart';
