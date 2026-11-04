import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Rect, Size;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'plan_sizes.dart';
import 'plan_text_reader.dart';

/// Text recognition wants characters about 16 px tall; dimension labels on a
/// plan sent over WhatsApp are often half that. Small plans are enlarged to
/// this many pixels on their long side before reading (at most 4×).
const double kReadLongSidePx = 2400;

/// On-device text recognition (ML Kit): offline, and the plan never leaves
/// the phone. Anything it can't do (another platform, an unreadable image)
/// comes back as no text, and the salesperson types the sizes instead.
class DevicePlanTextReader implements PlanTextReader {
  const DevicePlanTextReader();

  @override
  Future<PlanText> read(String imagePath) async {
    if (!Platform.isAndroid && !Platform.isIOS) return const PlanText();

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    ui.Image? plan;
    File? enlarged;
    try {
      final codec =
          await ui.instantiateImageCodec(await File(imagePath).readAsBytes());
      plan = (await codec.getNextFrame()).image;
      final scale =
          (kReadLongSidePx / math.max(plan.width, plan.height)).clamp(1.0, 4.0);
      final width = plan.width * scale, height = plan.height * scale;

      // ML Kit reads text turned either way, so one upright pass is enough.
      enlarged = File('${(await getTemporaryDirectory()).path}/plan_read.png');
      await enlarged.writeAsBytes(await _render(plan, scale));
      final result =
          await recognizer.processImage(InputImage.fromFilePath(enlarged.path));

      Rect fraction(Rect box) => Rect.fromLTRB(box.left / width,
          box.top / height, box.right / width, box.bottom / height);
      return findPlanText([
        for (final block in result.blocks)
          for (final line in block.lines)
            [
              for (final element in line.elements)
                PlanWord(element.text, fraction(element.boundingBox)),
            ],
      ]).withPlanSize(Size(plan.width.toDouble(), plan.height.toDouble()));
    } catch (_) {
      return const PlanText();
    } finally {
      plan?.dispose();
      await recognizer.close();
      try {
        if (enlarged != null && enlarged.existsSync()) await enlarged.delete();
      } catch (_) {}
    }
  }

  /// The plan enlarged [scale]× on white (so a transparent PNG reads as dark
  /// text on light), as PNG bytes.
  static Future<List<int>> _render(ui.Image plan, double scale) async {
    final w = (plan.width * scale).round(), h = (plan.height * scale).round();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF))
      ..scale(scale)
      ..drawImage(plan, ui.Offset.zero,
          ui.Paint()..filterQuality = ui.FilterQuality.high);

    final image = await recorder.endRecording().toImage(w, h);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
