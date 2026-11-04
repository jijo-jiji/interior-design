import 'plan_sizes.dart';

// ML Kit runs on Android and iOS; in the browser there's no on-device text
// reader, so a plan opened there has its sizes typed in.
export 'plan_text_reader_device.dart'
    if (dart.library.js_interop) 'plan_text_reader_web.dart';

/// Reads the text printed on a plan image.
abstract class PlanTextReader {
  Future<PlanText> read(String imagePath);
}
