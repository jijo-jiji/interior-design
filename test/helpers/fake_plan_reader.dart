import 'dart:async';
import 'dart:ui' show Offset, Rect, Size;

import 'package:static_trace/features/floorplan/plan_analysis.dart';
import 'package:static_trace/features/floorplan/plan_geometry.dart';
import 'package:static_trace/features/floorplan/plan_sizes.dart';
import 'package:static_trace/features/floorplan/plan_text_reader.dart';

Rect _box(double x, double y, [double w = 0.06, double h = 0.02]) =>
    Rect.fromCenter(center: Offset(x, y), width: w, height: h);

/// The text the phone reads off a metric plan with an L-shaped kitchen: a
/// room size with DAPUR, a bedroom, and dimensions along the top edge.
/// Sizes in reading order: 3000, 2400, 2900, 1700.
PlanText lKitchenText() => findPlanText([
      [
        PlanWord('DAPUR', _box(0.70, 0.27)),
        PlanWord('3000x2400', _box(0.74, 0.30)),
      ],
      [
        PlanWord('BILIK', _box(0.24, 0.24)),
        PlanWord('TIDUR', _box(0.30, 0.24)),
      ],
      [PlanWord('2900', _box(0.71, 0.02))],
      [PlanWord('1700', _box(0.86, 0.02))],
    ]);

/// A plan's text with the kitchen named but no size printed for it.
PlanText unsizedKitchenText() => findPlanText([
      [PlanWord('KITCHEN', _box(0.5, 0.4))],
      [
        PlanWord('BEDROOM', _box(0.2, 0.4)),
        PlanWord('3600x3300', _box(0.2, 0.43))
      ],
    ]);

class FakePlanTextReader implements PlanTextReader {
  FakePlanTextReader([PlanText? text]) : text = text ?? lKitchenText();
  final PlanText text;

  @override
  Future<PlanText> read(String imagePath) async => text;
}

/// A drawing read at 10 mm per pixel, 1000 × 700 px, with the kitchen's
/// inside at [kitchen] and a 900 mm doorway in its top wall.
PlanAnalysis measuredPlan({
  Rect kitchen = const Rect.fromLTRB(400, 100, 700, 340),
  double? mmPerPx = 10,
  bool openPlan = false,
}) =>
    PlanAnalysis(
      PlanGeometry(
        imageSize: const Size(1000, 700),
        wallThicknessPx: 15,
        walls: const [Rect.fromLTRB(385, 85, 715, 100)],
        rooms: [PlanRoom('KITCHEN', kitchen)],
        mmPerPx: mmPerPx,
        kitchen: openPlan
            ? null
            : PlanRoom('KITCHEN', kitchen, openings: const {
                0: [(60.0, 150.0)],
              }),
        kitchenIsOpenPlan: openPlan,
      ),
      'data:image/png;base64,AAAA',
      const Size(2000, 1400),
    );

/// Hands the screen a fixed reading of the drawing, or none.
class FakePlanAnalyser implements PlanAnalyser {
  FakePlanAnalyser([this.result, this.gate]);
  final PlanAnalysis? result;

  /// Holds the reading back until the test completes it.
  final Completer<void>? gate;
  int analyses = 0;

  @override
  Future<PlanAnalysis?> analyse(
      String imagePath, PlanText text, PlanLabel? kitchenLabel) async {
    analyses++;
    if (gate != null) await gate!.future;
    return result;
  }
}
