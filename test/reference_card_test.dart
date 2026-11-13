import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/trace/utils/homography.dart';
import 'package:static_trace/features/trace/utils/reference_card.dart';
import 'package:static_trace/features/trace/utils/wall_size.dart';

const photo = Size(4000, 3000);
const wallW = 3200.0, wallH = 2700.0;

/// The wall seen at an angle: its corners on the photo, as fractions.
const wall = [
  Offset(0.12, 0.10),
  Offset(0.85, 0.16),
  Offset(0.83, 0.86),
  Offset(0.14, 0.93),
];

/// Wall millimetres to photo fractions, through the same perspective.
final toPhoto = Homography.between(const [
  Offset(0, 0),
  Offset(wallW, 0),
  Offset(wallW, wallH),
  Offset(0, wallH),
], wall)!;

/// An A4 sheet on the wall, its centre at [at] (mm), turned [deg] degrees;
/// [landscape] for its long side across.
List<Offset> sheetAt(Offset at, {double deg = 0, bool landscape = false}) {
  final w = landscape ? kSheetLongMm : kSheetShortMm;
  final h = landscape ? kSheetShortMm : kSheetLongMm;
  final a = deg * math.pi / 180;
  Offset turn(double x, double y) => Offset(
      at.dx + x * math.cos(a) - y * math.sin(a),
      at.dy + x * math.sin(a) + y * math.cos(a));
  return [
    turn(-w / 2, -h / 2),
    turn(w / 2, -h / 2),
    turn(w / 2, h / 2),
    turn(-w / 2, h / 2),
  ].map(toPhoto.map).toList();
}

SheetMeasure measure(List<Offset> sheet, {double aspect = wallW / wallH}) =>
    measureSheet(sheet: sheet, wallCorners: wall, aspect: aspect, photo: photo)!;

void main() {
  group('the wall measured from an A4 sheet', () {
    test('upright, seen at an angle: the true size', () {
      final m = measure(sheetAt(const Offset(1600, 1300)));
      expect(m.heightMm, closeTo(wallH, 1));
      expect(m.widthMm, closeTo(wallW, 1));
      expect(m.shapeOff.abs(), lessThan(0.001));
      expect(m.shapeLooksOff, isFalse);
      expect(m.onWall, isTrue);
    });

    test('on its side, or taped on crooked: still the true size', () {
      for (final s in [
        sheetAt(const Offset(900, 1500), landscape: true),
        sheetAt(const Offset(2400, 1100), deg: 15),
        sheetAt(const Offset(1200, 800), deg: -25, landscape: true),
      ]) {
        final m = measure(s);
        expect(m.heightMm, closeTo(wallH, 2));
        expect(m.shapeLooksOff, isFalse);
      }
    });

    test('a dot a little off moves the size a little', () {
      final s = sheetAt(const Offset(1600, 1300));
      // 4 px on a 4,000 px photo, on a sheet about 260 px wide there.
      s[1] += const Offset(0.001, 0);
      final m = measure(s);
      expect((m.heightMm / wallH - 1).abs(), lessThan(0.01));
    });

    test('a dot well off: the sheet no longer looks like A4', () {
      final s = sheetAt(const Offset(1600, 1300));
      s[2] += const Offset(0, 0.03);
      s[3] += const Offset(0, 0.03);
      expect(measure(s).shapeLooksOff, isTrue);
    });

    test('a sheet off the traced wall is said to be', () {
      final s = sheetAt(const Offset(-300, 1300));
      expect(measure(s).onWall, isFalse);
    });

    test('small on the photo: said to be', () {
      expect(measure(sheetAt(const Offset(1600, 1300))).small, isFalse);
      // The same sheet on a photo a fifth of the size.
      final m = measureSheet(
          sheet: sheetAt(const Offset(1600, 1300)),
          wallCorners: wall,
          aspect: wallW / wallH,
          photo: const Size(800, 600))!;
      expect(m.small, isFalse, reason: 'the share is of the photo, not px');
      final far = [
        for (final p in sheetAt(const Offset(1600, 1300)))
          Offset(0.5 + (p.dx - 0.5) * 0.3, 0.5 + (p.dy - 0.5) * 0.3)
      ];
      final shrunk = [
        for (final p in wall)
          Offset(0.5 + (p.dx - 0.5) * 0.3, 0.5 + (p.dy - 0.5) * 0.3)
      ];
      final small = measureSheet(
          sheet: far, wallCorners: shrunk, aspect: wallW / wallH, photo: photo)!;
      expect(small.small, isTrue);
      expect(small.heightMm, closeTo(wallH, 2));
    });

    test('three dots in a line: no measurement', () {
      final s = [
        const Offset(0.4, 0.4),
        const Offset(0.5, 0.4),
        const Offset(0.6, 0.4),
        const Offset(0.4, 0.4),
      ];
      expect(
          measureSheet(
              sheet: s, wallCorners: wall, aspect: 1.2, photo: photo),
          isNull);
    });
  });

  group('where the dots start', () {
    test('an A4 sheet in the middle of the wall, in perspective', () {
      final s = startSheet(
          wallCorners: wall, aspect: wallW / wallH, heightMm: wallH);
      final m = measure(s);
      expect(m.heightMm, closeTo(wallH, 1));
      expect(m.shapeLooksOff, isFalse);
      expect(m.onWall, isTrue);
    });
  });

  group('the size estimate', () {
    test('a sheet on the wall comes before anything else', () {
      final m = measure(sheetAt(const Offset(1600, 1300)));
      final e = estimateWallSize(wallW / wallH, sheet: m);
      expect(e.cue, SizeCue.sheet);
      expect(e.heightMm, 2700);
      expect(e.widthMm, 3200);
    });

    test('a sheet off the wall is left out', () {
      final m = measure(sheetAt(const Offset(-300, 1300)));
      expect(estimateWallSize(wallW / wallH, sheet: m).cue, SizeCue.assumed);
    });
  });
}
