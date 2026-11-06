import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image_picker/image_picker.dart' show XFile;

import 'plan_geometry.dart';
import 'plan_sizes.dart';

/// The drawing read off a plan image, and the picture itself for the 3D
/// floor (the same pixels the geometry is measured in).
class PlanAnalysis {
  const PlanAnalysis(this.geometry, this.imageDataUrl, this.originalSize);
  final PlanGeometry geometry;

  /// The plan image's own size in pixels, before it was scaled down to read.
  final ui.Size originalSize;

  /// A PNG data URL, or empty if the picture couldn't be made.
  final String imageDataUrl;
}

abstract class PlanAnalyser {
  Future<PlanAnalysis?> analyse(
      String imagePath, PlanText text, PlanLabel? kitchenLabel);
}

/// Plans are analysed at most this many pixels on the long side: enough for
/// walls a few pixels thick, and quick on a phone.
const int kAnalyseLongSidePx = 1400;

/// Reads the plan's walls and rooms ([analysePlan]) in a background isolate.
/// Works wherever the picture can be read: a file on the phone, a `blob:`
/// URL in the browser.
class DevicePlanAnalyser implements PlanAnalyser {
  const DevicePlanAnalyser();

  @override
  Future<PlanAnalysis?> analyse(
      String imagePath, PlanText text, PlanLabel? kitchenLabel) async {
    try {
      final bytes = await XFile(imagePath).readAsBytes();
      final probe = await ui.instantiateImageCodec(bytes);
      final first = (await probe.getNextFrame()).image;
      final original = ui.Size(first.width.toDouble(), first.height.toDouble());
      final longSide = math.max(first.width, first.height);
      final shrink =
          longSide > kAnalyseLongSidePx ? kAnalyseLongSidePx / longSide : 1.0;
      final width = (first.width * shrink).round();
      final height = (first.height * shrink).round();
      first.dispose();

      final codec = await ui.instantiateImageCodec(bytes,
          targetWidth: width, targetHeight: height);
      final image = (await codec.getNextFrame()).image;
      try {
        final rgba =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (rgba == null) return null;
        final gray = GrayImage.fromRgba(
            rgba.buffer.asUint8List(), image.width, image.height);
        final geometry = await compute(
            analysePlan, PlanAnalysisInput(gray, text, kitchenLabel));
        final url = png == null
            ? ''
            : 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
        return PlanAnalysis(geometry, url, original);
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
