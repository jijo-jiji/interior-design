import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/models/obstacle.dart';
import 'package:static_trace/features/trace/utils/payload_builder.dart';

void main() {
  group('PayloadBuilder — JSON structure', () {
    const ratio = 0.2; // 800px / 4000mm

    final obstacles = [
      Obstacle(
        type: ObstacleType.window,
        leftPx: 240,    // 1200mm from left
        topPx: 360,     // 1800mm from top → from floor = 2700 - 1800 - 1200 = -300? let's use realistic
        widthPx: 200,   // 1000mm
        heightPx: 240,  // 1200mm
      ),
    ];

    test('wall block contains correct keys', () {
      final payload = PayloadBuilder.build(
        wallWidthMm: 4000,
        wallHeightMm: 2700,
        wallDepthMm: 150,
        scaleRatio: ratio,
        obstacles: obstacles,
        canvasHeightPx: 540,
      );

      final wall = payload['wall'] as Map<String, dynamic>;
      expect(wall['width_mm'], equals(4000));
      expect(wall['height_mm'], equals(2700));
      expect(wall['depth_mm'], equals(150));
    });

    test('obstacle width converts correctly: 200px / 0.2 = 1000mm', () {
      final payload = PayloadBuilder.build(
        wallWidthMm: 4000,
        wallHeightMm: 2700,
        wallDepthMm: 150,
        scaleRatio: ratio,
        obstacles: obstacles,
        canvasHeightPx: 540,
      );

      final obs = (payload['obstacles'] as List).first as Map<String, dynamic>;
      expect(obs['width_mm'], closeTo(1000.0, 0.1));
    });

    test('distance_from_left: 240px / 0.2 = 1200mm', () {
      final payload = PayloadBuilder.build(
        wallWidthMm: 4000,
        wallHeightMm: 2700,
        wallDepthMm: 150,
        scaleRatio: ratio,
        obstacles: obstacles,
        canvasHeightPx: 540,
      );

      final obs = (payload['obstacles'] as List).first as Map<String, dynamic>;
      expect(obs['distance_from_left_mm'], closeTo(1200.0, 0.1));
    });

    test('toJson produces valid parseable JSON', () {
      final json = PayloadBuilder.toJson(
        wallWidthMm: 4000,
        wallHeightMm: 2700,
        wallDepthMm: 150,
        scaleRatio: ratio,
        obstacles: obstacles,
        canvasHeightPx: 540,
      );

      expect(() => jsonDecode(json), returnsNormally);
    });

    test('salesperson_id is hardcoded to demo_agent_01', () {
      final payload = PayloadBuilder.build(
        wallWidthMm: 4000,
        wallHeightMm: 2700,
        wallDepthMm: 150,
        scaleRatio: ratio,
        obstacles: [],
        canvasHeightPx: 540,
      );
      expect(payload['salesperson_id'], equals('demo_agent_01'));
    });
  });
}
