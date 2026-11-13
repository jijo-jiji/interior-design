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

/// How a render is lit.
enum RenderEngine {
  /// Many frames, each lit from another part of the sky, averaged: soft
  /// shadows and darker corners, in tens of seconds.
  sky,

  /// True lighting: light paths are followed on the graphics chip, so light
  /// bounces between surfaces. Slower, and needs a recent device.
  path,
}

/// How much detail a true-lighting render goes to.
enum RenderQuality { standard, fine }

/// A render being asked for.
class RenderRequest {
  const RenderRequest(this.engine, [this.quality = RenderQuality.standard]);

  final RenderEngine engine;
  final RenderQuality quality;

  /// The call that asks the 3D page for it. [skySamples] is how many frames
  /// the sky-averaged render takes.
  String javaScript({required int skySamples}) => switch (engine) {
        RenderEngine.sky => "renderPictures('render', {samples: $skySamples})",
        RenderEngine.path => switch (quality) {
            // The page stops at the samples or the seconds, whichever comes
            // first, so a slow device still gets a picture (a noisier one:
            // the picture is as clean as the samples it reached).
            RenderQuality.standard =>
              "renderPictures('render', {engine: 'path', samples: 300, "
                  "minSamples: 24, seconds: 120})",
            RenderQuality.fine =>
              "renderPictures('render', {engine: 'path', samples: 1000, "
                  "minSamples: 64, seconds: 300})",
          },
      };

  /// How long to wait for the page: both pictures, with the shader build.
  Duration get timeout => switch (engine) {
        RenderEngine.sky => const Duration(minutes: 10),
        RenderEngine.path => quality == RenderQuality.fine
            ? const Duration(minutes: 25)
            : const Duration(minutes: 12),
      };
}

/// What a true-lighting render reached: how many samples each picture got
/// (the more, the cleaner), how long each took, and the graphics chip.
class RenderStats {
  const RenderStats({
    this.samples = const [],
    this.seconds = const [],
    this.gpu = '',
  });

  /// Reads the page's `stats`; null when it sent none (or nonsense).
  static RenderStats? fromJson(Object? json) {
    if (json is! Map) return null;
    List<num> numbers(Object? value) => value is List
        ? [
            for (final v in value)
              if (v is num) v
          ]
        : const [];
    final samples = numbers(json['samples']);
    if (samples.isEmpty) return null;
    return RenderStats(
      samples: [for (final s in samples) s.round()],
      seconds: [for (final s in numbers(json['seconds'])) s.toDouble()],
      gpu: json['gpu'] is String ? (json['gpu'] as String).trim() : '',
    );
  }

  final List<int> samples;
  final List<double> seconds;
  final String gpu;

  String _list(Iterable<String> items) => items.join(' and ');

  /// What to show: the samples and seconds, and the chip when known.
  String get summary {
    final seconds = this.seconds.map(
        (s) => s == s.roundToDouble() ? '${s.round()}' : s.toStringAsFixed(1));
    final took = seconds.isEmpty ? '' : ', in ${_list(seconds)} s';
    final chip = gpu.isEmpty ? '' : '\nGraphics: $gpu';
    return 'Light paths traced: ${_list(samples.map((s) => '$s'))} samples'
        '$took.$chip';
  }
}

/// What a render made.
class RenderResult {
  const RenderResult(this.images, this.engine,
      {this.fellBack = false, this.stats});

  final List<String> images;

  /// What a true-lighting render reached (null for the other kind).
  final RenderStats? stats;

  /// The engine that made [images]: the one asked for, unless the device
  /// couldn't ([fellBack]).
  final RenderEngine engine;
  final bool fellBack;
}
