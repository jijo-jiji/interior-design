import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'opening_finder.dart';
import 'wall_segmenter_api.dart';

export 'wall_segmenter_api.dart';

/// MLCommons' DeepLabV3+ on ADE20K (tool/fetch_wall_segmenter.py fetches
/// it): the whole photo squeezed to 512 × 512 in, 32 class scores at
/// 128 × 128 out.
const kWallSegmenterAsset = 'assets/models/wall_segment.onnx';
const int _inputSize = 512;

class DeviceWallSegmenter implements WallSegmenter {
  const DeviceWallSegmenter();

  static Future<OrtSession?>? _session;

  static Future<OrtSession?> _open() => _session ??= () async {
        try {
          final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
          if (!manifest.listAssets().contains(kWallSegmenterAsset)) {
            return null;
          }
          return await OnnxRuntime().createSessionFromAsset(
            kWallSegmenterAsset,
            options: OrtSessionOptions(intraOpNumThreads: 4),
          );
        } catch (_) {
          return null;
        }
      }();

  @override
  Future<WallLabels?> labels(String imagePath) async {
    final session = await _open();
    if (session == null) return null;
    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      // The photo upright (the decoder applies its EXIF rotation), squeezed
      // to the model's square, as it was trained.
      final bytes = await XFile(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: _inputSize, targetHeight: _inputSize);
      final image = (await codec.getNextFrame()).image;
      final rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      image.dispose();
      if (rgba == null) return null;
      final pixels = await compute(_modelInput, rgba.buffer.asUint8List());
      input = await OrtValue.fromList(pixels, [1, 3, _inputSize, _inputSize]);
      final name = session.inputNames.isEmpty
          ? 'MobilenetV2/MobilenetV2/input'
          : session.inputNames.first;
      outputs = await session.run({name: input});
      final out = outputs.values.first;
      final classes = out.shape[1], oh = out.shape[2], ow = out.shape[3];
      final flat = await out.asFlattenedList();
      final scores = Float32List(flat.length);
      for (var i = 0; i < flat.length; i++) {
        scores[i] = (flat[i] as num).toDouble();
      }
      final ids = await compute(_argmax, (scores, classes, ow * oh));
      return WallLabels(ow, oh, ids);
    } catch (_) {
      return null;
    } finally {
      await input?.dispose();
      for (final value in outputs?.values ?? const <OrtValue>[]) {
        await value.dispose();
      }
    }
  }
}

/// RGBA to the model's input: channels first, scaled to -1..1.
Float32List _modelInput(Uint8List rgba) {
  const n = _inputSize * _inputSize;
  final out = Float32List(3 * n);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < 3; c++) {
      out[c * n + i] = rgba[i * 4 + c] / 127.5 - 1;
    }
  }
  return out;
}

/// The best class for each cell, from scores laid out class by class.
Uint8List _argmax((Float32List, int, int) args) {
  final (scores, classes, cells) = args;
  final ids = Uint8List(cells);
  for (var i = 0; i < cells; i++) {
    var best = 0;
    var bestScore = scores[i];
    for (var c = 1; c < classes; c++) {
      final s = scores[c * cells + i];
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    ids[i] = best;
  }
  return ids;
}
