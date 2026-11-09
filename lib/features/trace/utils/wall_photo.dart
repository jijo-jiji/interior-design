import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' show XFile;

/// A photo this size or smaller is sent as it is (a phone camera's 1080p
/// photo is a few hundred KB). Bigger ones, often from the gallery, are
/// scaled down first.
const int kSendPhotoAsIsBytes = 2 * 1024 * 1024;

/// Scaled-down photos are at most this many pixels on the long side, the
/// size the office server keeps.
const int kSentPhotoLongSide = 2400;

/// The wall photo as a data URL, to keep with the quote as a labelled photo
/// (the corners are marked on it). Null if the photo can't be read, e.g. a
/// browser `blob:` URL from before the page was reloaded.
///
/// Sent as it is when small enough: the office server turns it upright and
/// drops its metadata (GPS position included) before keeping it.
Future<String?> wallPhotoDataUrl(String path) async {
  try {
    final bytes = await XFile(path).readAsBytes();
    final isJpeg = bytes.length > 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    final isPng = bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    if ((isJpeg || isPng) && bytes.length <= kSendPhotoAsIsBytes) {
      return 'data:image/${isJpeg ? 'jpeg' : 'png'};base64,'
          '${base64Encode(bytes)}';
    }

    // Too big: decode upright (the engine applies the EXIF rotation), scale
    // down, and re-encode as JPEG in the background.
    final probe = await ui.instantiateImageCodec(bytes);
    final first = (await probe.getNextFrame()).image;
    final longSide = math.max(first.width, first.height);
    final shrink =
        longSide > kSentPhotoLongSide ? kSentPhotoLongSide / longSide : 1.0;
    final width = (first.width * shrink).round();
    final height = (first.height * shrink).round();
    first.dispose();
    final codec = await ui.instantiateImageCodec(bytes,
        targetWidth: width, targetHeight: height);
    final image = (await codec.getNextFrame()).image;
    try {
      final rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (rgba == null) return null;
      final jpeg = await compute(
          _encodeJpeg, (rgba.buffer.asUint8List(), image.width, image.height));
      return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    } finally {
      image.dispose();
    }
  } catch (_) {
    return null;
  }
}

Uint8List _encodeJpeg((Uint8List, int, int) rgba) {
  final (pixels, width, height) = rgba;
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: pixels.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: 88);
}
