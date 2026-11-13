/// The wall-corner model on this device: on a phone, Depth Anything V2 Small
/// through ONNX Runtime; in the browser, none yet.
library;

export 'corner_suggester_device.dart'
    if (dart.library.js_interop) 'corner_suggester_web.dart';
