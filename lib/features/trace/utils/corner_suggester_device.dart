import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'corner_finder.dart';
import 'corner_suggestion.dart';
import 'learned_corners.dart';
import 'model_file.dart';
import 'opening_finder.dart' show WallLabels;

/// Depth Anything V2 Small, 8-bit (tool/fetch_wall_model.py fetches it).
const kWallModelAsset = 'assets/models/wall_depth.onnx';

/// The model sees the photo at this many pixels on its short side (the
/// size it was trained at); smaller inputs lose too much accuracy.
const int kDepthShortSide = 518;

/// Finds the wall's corners on the phone, nothing leaving the device: the
/// depth model's map first; if its flat patches don't show the wall (a
/// kitchen), our corner model reads that map with the segmentation labels.
class DeviceCornerSuggester implements CornerSuggester {
  const DeviceCornerSuggester();

  /// Each model opened once, on first use; null if it isn't in this build or
  /// can't run here.
  static final _sessions = <String, Future<OrtSession?>>{};

  static Future<OrtSession?> _open(String asset) =>
      _sessions[asset] ??= () async {
        try {
          final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
          if (!manifest.listAssets().contains(asset)) return null;
          return await OnnxRuntime().createSession(
            await modelFile(asset),
            options: OrtSessionOptions(intraOpNumThreads: 4),
          );
        } catch (_) {
          return null;
        }
      }();

  @override
  Future<CornerSuggestion> suggest(String imagePath,
      {Future<WallLabels?> Function()? labels}) async {
    final session = await _open(kWallModelAsset);
    if (session == null) return const CornerSuggestion.unavailable();
    final photo = await _depth(session, imagePath);
    if (photo == null) return const CornerSuggestion(null);
    final (depth, aspect) = photo;

    final corners = await compute(_find, depth);
    if (corners != null) {
      return CornerSuggestion(corners, source: CornerSource.planes);
    }
    if (labels == null) return const CornerSuggestion(null);
    WallLabels? found;
    try {
      found = await labels();
    } catch (_) {
      found = null;
    }
    if (found == null) return const CornerSuggestion(null);
    final learned = await _learned(depth, found, aspect);
    return learned == null
        ? const CornerSuggestion(null)
        : CornerSuggestion(learned.corners,
            source: CornerSource.learned, wallBottom: learned.wallBottom);
  }

  /// The photo's depth map, and its shape (width / height). Null if it
  /// can't be read.
  Future<(DepthMap, double)?> _depth(
      OrtSession session, String imagePath) async {
    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      // The photo upright (the decoder applies its EXIF rotation), at the
      // model's size: both sides a multiple of 14, its patch size.
      final bytes = await XFile(imagePath).readAsBytes();
      final probe = await ui.instantiateImageCodec(bytes);
      final first = (await probe.getNextFrame()).image;
      final aspect = first.width / first.height;
      final scale = kDepthShortSide / math.min(first.width, first.height);
      final w = (first.width * scale / 14).round() * 14;
      final h = (first.height * scale / 14).round() * 14;
      first.dispose();
      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: w, targetHeight: h);
      final image = (await codec.getNextFrame()).image;
      final rgba =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      image.dispose();
      if (rgba == null) return null;

      final pixels =
          await compute(_modelInput, (rgba.buffer.asUint8List(), w, h));
      input = await OrtValue.fromList(pixels, [1, 3, h, w]);
      final name = session.inputNames.isEmpty
          ? 'pixel_values'
          : session.inputNames.first;
      outputs = await session.run({name: input});
      final out = outputs.values.first;
      final oh = out.shape[out.shape.length - 2], ow = out.shape.last;
      final flat = await out.asFlattenedList();
      final depth = Float32List(flat.length);
      for (var i = 0; i < flat.length; i++) {
        depth[i] = (flat[i] as num).toDouble();
      }
      return (DepthMap(ow, oh, depth), aspect);
    } catch (_) {
      return null;
    } finally {
      await input?.dispose();
      for (final value in outputs?.values ?? const <OrtValue>[]) {
        await value.dispose();
      }
    }
  }

  /// Our corner model's corners, if it's sure of them.
  Future<LearnedCorners?> _learned(
      DepthMap depth, WallLabels labels, double aspect) async {
    final session = await _open(kCornerModelAsset);
    if (session == null) return null;
    OrtValue? input;
    Map<String, OrtValue>? outputs;
    try {
      final x = await compute(_learnedInput, (depth, labels, aspect));
      input = await OrtValue.fromList(
          x, [1, kCornerModelChannels, kCornerModelSize, kCornerModelSize]);
      final name =
          session.inputNames.isEmpty ? 'room' : session.inputNames.first;
      outputs = await session.run({name: input});
      final flat = await outputs.values.first.asFlattenedList();
      return trustedCorners([for (final v in flat) (v as num).toDouble()]);
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

List<ui.Offset>? _find(DepthMap depth) => cornersFromDepth(depth);

Float32List _learnedInput((DepthMap, WallLabels, double) args) =>
    cornerModelInput(args.$1, args.$2, args.$3);

/// RGBA pixels to the model's input: channels first, ImageNet-normalised.
Float32List _modelInput((Uint8List, int, int) photo) {
  final (rgba, w, h) = photo;
  const mean = [0.485, 0.456, 0.406];
  const std = [0.229, 0.224, 0.225];
  final n = w * h;
  final out = Float32List(3 * n);
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < 3; c++) {
      out[c * n + i] = (rgba[i * 4 + c] / 255 - mean[c]) / std[c];
    }
  }
  return out;
}
