/// Lets Flutter controls drawn over the 3D view receive clicks and taps in
/// the browser. Does nothing on Android.
library;

export 'pointer_shield_io.dart'
    if (dart.library.js_interop) 'pointer_shield_web.dart';
