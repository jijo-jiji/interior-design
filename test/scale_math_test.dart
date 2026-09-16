import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/utils/scale_math.dart';

void main() {
  group('ScaleMath — pixel↔mm round-trip', () {
    const ratio = 0.2; // 800px / 4000mm

    test('computeRatio: 800px / 4000mm = 0.2', () {
      expect(
        ScaleMath.computeRatio(screenWidthPx: 800, wallWidthMm: 4000),
        closeTo(0.2, 0.0001),
      );
    });

    test('mmToPx: 1000mm * 0.2 = 200px', () {
      expect(ScaleMath.mmToPx(1000, ratio), closeTo(200.0, 0.001));
    });

    test('pxToMm: 200px / 0.2 = 1000mm', () {
      expect(ScaleMath.pxToMm(200, ratio), closeTo(1000.0, 0.001));
    });

    test('round-trip: px → mm → px is lossless', () {
      const originalPx = 153.6;
      final mm = ScaleMath.pxToMm(originalPx, ratio);
      final backPx = ScaleMath.mmToPx(mm, ratio);
      expect(backPx, closeTo(originalPx, 0.0001));
    });

    test('clampLeft: box cannot exceed canvas right edge', () {
      final clamped = ScaleMath.clampLeft(750, 100, 800);
      expect(clamped, equals(700.0));
    });

    test('clampTop: box cannot go above canvas top', () {
      final clamped = ScaleMath.clampTop(-10, 50, 600);
      expect(clamped, equals(0.0));
    });

    test('snapToGrid: snaps to nearest 50mm grid', () {
      // 74px / 0.2 = 370mm → nearest 50 = 350mm → 350 * 0.2 = 70px
      final snapped = ScaleMath.snapToGrid(74, ratio, gridMm: 50);
      expect(snapped, closeTo(70.0, 0.001));
    });
  });
}
