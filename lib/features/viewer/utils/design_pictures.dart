import 'dart:convert';
import 'dart:typed_data';

import '../../../shared/config.dart';
import '../../../shared/platform/api_client.dart';

/// Pictures of the design, taken by the 3D page (`capturePictures`) as JPEG
/// data URLs.
class DesignPictures {
  const DesignPictures._();

  /// What a picture may weigh and still be kept on the phone beside a design
  /// that is waiting to be sent (browser storage holds about 5 MB in all).
  static const maxBytesToKeepOffline = 1500000;

  /// The picture's bytes, or null if [dataUrl] isn't a base64 image.
  static Uint8List? decode(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (!dataUrl.startsWith('data:image/') || comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }

  /// Whether [images] are small enough to keep with an unsent quote.
  static bool fitsOffline(List<String> images) =>
      images.fold<int>(0, (sum, image) => sum + image.length) <=
      maxBytesToKeepOffline;

  /// Gives the office the pictures so the client can open them from a link.
  /// Returns the page's address, or null when the office can't be reached or
  /// refuses them.
  static Future<String?> upload(
    String quoteId,
    List<String> images, {
    Uri? endpoint,
  }) async {
    final reply = await ApiClient.postJson(
      endpoint ?? Uri.parse(AppConfig.picturesUploadEndpoint(quoteId)),
      {'images': images},
      timeout: const Duration(seconds: 20),
    );
    if (reply == null || !reply.ok) return null;
    return AppConfig.picturesPageUrl(quoteId);
  }
}
