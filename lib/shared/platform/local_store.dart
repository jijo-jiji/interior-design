/// Small text storage that survives an app restart: a file in the app's
/// documents folder on Android, `localStorage` in the browser.
library;

export 'local_store_io.dart'
    if (dart.library.js_interop) 'local_store_web.dart';
