/// The link between the app and the 3D page (`assets/3d/index.html`): a
/// WebView on Android, an iframe in the browser. Both expose the same
/// [SceneBridge] API.
library;

export 'scene_bridge_io.dart'
    if (dart.library.js_interop) 'scene_bridge_web.dart';
