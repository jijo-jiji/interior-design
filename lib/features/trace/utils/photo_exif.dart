import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;

/// EXIF tag: focal length in 35 mm film.
const int _focal35mmTag = 0xA405;

/// The camera's focal length (35 mm equivalent) from a photo's EXIF data, or
/// null when the photo doesn't say: screenshots, PNGs, most edited images.
/// Works for a file path and a browser `blob:` URL alike.
Future<double?> readFocal35mm(String path) async {
  try {
    final bytes = await XFile(path).readAsBytes();
    final exif = img.decodeJpgExif(bytes);
    if (exif == null) return null;
    final focal = exif.exifIfd[_focal35mmTag]?.toInt();
    return focal != null && focal > 0 ? focal.toDouble() : null;
  } catch (_) {
    return null;
  }
}
