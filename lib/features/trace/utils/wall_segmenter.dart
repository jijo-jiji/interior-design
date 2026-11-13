/// The wall segmentation model on this device: on a phone, through ONNX
/// Runtime; in the browser, none yet.
library;

export 'wall_segmenter_device.dart'
    if (dart.library.js_interop) 'wall_segmenter_web.dart';
