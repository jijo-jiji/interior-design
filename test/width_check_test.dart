import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/layout/kitchen_layout_generator.dart';
import 'package:static_trace/features/layout/kitchen_layout_models.dart';
import 'package:static_trace/features/layout/width_check.dart';

const _generator = KitchenLayoutGenerator();

WidthSensitivity? check(double widthMm, LayoutTier tier,
        {double heightMm = 2700, List<WallOpening> openings = const []}) =>
    widthSensitivity(
        _generator,
        KitchenRoom(
            mainWallMm: widthMm, wallHeightMm: heightMm, openings: openings),
        tier);

void main() {
  test('a little wider and a tall unit fits: said, with how much', () {
    // Kitchen 03 as measured from its photo.
    final s = check(2860, LayoutTier.balanced, heightMm: 2680)!;
    expect(s.marginMm, 140); // 5%, to the nearest 10 mm
    expect(s.narrower, isNull);
    expect(s.wider, 'a tall unit fits');
    expect(s.message,
        'This layout depends on the exact width: 140 mm wider, a tall unit '
        'fits. Measure the width before quoting.');
  });

  test('a little narrower and the tall unit goes', () {
    final s = check(3000, LayoutTier.balanced)!;
    expect(s.narrower, 'the tall unit no longer fits');
    expect(s.message, contains('150 mm narrower'));
  });

  test('a little wider and a hob fits', () {
    expect(check(2250, LayoutTier.value)!.wider, 'a hob fits');
  });

  test('a second tall unit', () {
    expect(check(3750, LayoutTier.premium)!.wider, 'one more tall unit fits');
  });

  test('nothing that matters changes: nothing said', () {
    for (final tier in LayoutTier.values) {
      expect(check(3500, tier), isNull, reason: tier.name);
      expect(check(4500, tier), isNull, reason: tier.name);
    }
  });

  test('windows and doors scale with the wall, as a photo\'s scale would', () {
    // The same wall with a window: everything scaled the same way, so the
    // window stays centred; the check doesn't break on openings.
    final s = check(3500, LayoutTier.balanced, openings: const [
      WallOpening(
          type: OpeningType.window,
          leftMm: 1200,
          floorMm: 1000,
          widthMm: 1100,
          heightMm: 1300),
    ]);
    expect(s == null || s.message.contains('Measure the width'), isTrue);
  });
}
