// The lean check: on the straightened wall, upright edges stand upright when
// the corners are right, and lean when one is off.
//
// The photo is a rendered room seen 25° from the left (made by
// tool/wall_benchmark/make_synthetic.py), with its true corners.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:static_trace/features/floorplan/plan_geometry.dart';
import 'package:static_trace/features/trace/utils/wall_lean.dart';

GrayImage gray(img.Image photo) {
  final px = Uint8List(photo.width * photo.height);
  for (final p in photo) {
    px[p.y * photo.width + p.x] = p.luminance.toInt();
  }
  return GrayImage(photo.width, photo.height, px);
}

void main() {
  final photo = img.decodeJpg(
      File('test/fixtures/walls/from-left-25.jpg').readAsBytesSync())!;
  final truth = jsonDecode(
          File('test/fixtures/walls/from-left-25.json').readAsStringSync())
      as Map<String, dynamic>;
  final corners = [
    for (final c in truth['wall_corners_px'] as List)
      Offset((c[0] as num).toDouble(), (c[1] as num).toDouble())
  ];
  final image = gray(photo);
  const aspect = 4000 / 2700;

  test('right corners: upright edges stand upright', () {
    final lean = uprightLean(WallLeanInput(image, corners, aspect))!;
    expect(lean.abs(), lessThan(kLeanWarnDeg));
  });

  test('corners tapped a few pixels off still pass', () {
    const jitter = [Offset(3, -4), Offset(-4, 3), Offset(4, 4), Offset(-3, -3)];
    final shaky = [for (var i = 0; i < 4; i++) corners[i] + jitter[i]];
    final lean = uprightLean(WallLeanInput(image, shaky, aspect))!;
    expect(lean.abs(), lessThan(kLeanWarnDeg));
  });

  test('a corner well off (as on the phone, 100 px) is caught', () {
    // Where the top-right corner was dragged to on the emulator: the
    // proportions barely changed (0.6%), but the window moved 224 mm.
    final wrong = [corners[0], const Offset(1307, 280), corners[2], corners[3]];
    final lean = uprightLean(WallLeanInput(image, wrong, aspect))!;
    expect(lean.abs(), greaterThan(kLeanWarnDeg));
  });

  test('a blank wall has nothing to tell by', () {
    final blank = GrayImage(400, 300, Uint8List(400 * 300)..fillRange(0, 400 * 300, 200));
    const box = [Offset(20, 20), Offset(380, 20), Offset(380, 280), Offset(20, 280)];
    expect(uprightLean(WallLeanInput(blank, box, aspect)), isNull);
  });
}
