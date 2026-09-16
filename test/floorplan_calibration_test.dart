import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Floor Plan 2-Point Calibration Math Tests', () {
    test('Calculates Euclidean pixel distance between two calibration pins correctly', () {
      const pinA = Offset(100, 100);
      const pinB = Offset(400, 500);

      final dx = pinB.dx - pinA.dx; // 300
      final dy = pinB.dy - pinA.dy; // 400
      final distance = sqrt(dx * dx + dy * dy);

      expect(distance, 500.0);
    });

    test('Computes scale ratio accurately from known door width', () {
      const pinA = Offset(50, 200);
      const pinB = Offset(230, 200);
      final pxDist = (pinB.dx - pinA.dx).abs(); // 180 px

      const realDoorMm = 900.0;
      final scaleRatio = pxDist / realDoorMm; // 180 / 900 = 0.2 px/mm

      expect(scaleRatio, 0.2);

      // Now calculate room wall width from a 800px crop box
      const roomCropWidthPx = 800.0;
      final roomWallMm = roomCropWidthPx / scaleRatio;

      expect(roomWallMm, 4000.0);
    });
  });
}
