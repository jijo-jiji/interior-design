/// Shows a photo the salesperson took or picked: a file path on Android, a
/// `blob:` URL from the camera or file picker in the browser.
library;

export 'photo_image_io.dart'
    if (dart.library.js_interop) 'photo_image_web.dart';
