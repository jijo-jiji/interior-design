// Lengths as printed on floor plans or typed by the salesperson, in mm.
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/floorplan/plan_sizes.dart';

void main() {
  group('parseLengthMm', () {
    test('a plain number is millimetres, with or without thousands commas', () {
      expect(parseLengthMm('3000'), 3000);
      expect(parseLengthMm('3,000'), 3000);
      expect(parseLengthMm(' 2450 '), 2450);
    });

    test('metric units', () {
      expect(parseLengthMm('3000mm'), 3000);
      expect(parseLengthMm('3.6 m'), closeTo(3600, 0.001));
      expect(parseLengthMm('3.0M'), closeTo(3000, 0.001));
      expect(parseLengthMm('360cm'), 3600);
    });

    test('feet and inches, the way plans print them', () {
      // 9'8" = 116 in = 2946.4 mm
      expect(parseLengthMm('9\'8"'), closeTo(2946.4, 0.01));
      expect(parseLengthMm('9\' 8"'), closeTo(2946.4, 0.01));
      expect(parseLengthMm('9\'-8"'), closeTo(2946.4, 0.01));
      expect(parseLengthMm('9\' - 8"'), closeTo(2946.4, 0.01));
      expect(parseLengthMm('9\'8'), closeTo(2946.4, 0.01));
      expect(parseLengthMm('9ft 8in'), closeTo(2946.4, 0.01));
      expect(parseLengthMm('10\''), closeTo(3048, 0.01));
      expect(parseLengthMm('10\'0"'), closeTo(3048, 0.01));
      expect(parseLengthMm('96"'), closeTo(2438.4, 0.01));
      expect(parseLengthMm('9\'8 1/2"'), closeTo(2959.1, 0.01));
    });

    test('typographic quotes from plans and phone keyboards', () {
      expect(parseLengthMm('9’8”'), closeTo(2946.4, 0.01));
      expect(parseLengthMm('9′8″'), closeTo(2946.4, 0.01));
      expect(parseLengthMm("9'8''"), closeTo(2946.4, 0.01));
    });

    test('a wall across two printed segments can be summed', () {
      // 9'5" + 5'8" = 15'1" = 181 in
      expect(parseLengthMm('9\'5" + 5\'8"'), closeTo(4597.4, 0.01));
      expect(parseLengthMm('2400+600'), 3000);
      expect(parseLengthMm('3 m + 600'), closeTo(3600, 0.001));
    });

    test('anything else is not a length', () {
      for (final text in [
        '',
        '  ',
        'abc',
        '3000 x 2400',
        '+',
        '3000+',
        '0',
        '-500',
        '9\'8"x',
        'm'
      ]) {
        expect(parseLengthMm(text), isNull, reason: '"$text"');
      }
    });
  });

  test('hasExplicitUnit tells a plain number from one with a unit', () {
    expect(hasExplicitUnit('3.6'), isFalse);
    expect(hasExplicitUnit('3600'), isFalse);
    expect(hasExplicitUnit('3.6 m'), isTrue);
    expect(hasExplicitUnit('9\'8'), isTrue);
    expect(hasExplicitUnit('9’8”'), isTrue);
    expect(hasExplicitUnit('96 in'), isTrue);
  });

  test('formatMm rounds and groups thousands', () {
    expect(formatMm(2946.4), '2,946 mm');
    expect(formatMm(15000), '15,000 mm');
    expect(formatMm(600), '600 mm');
  });

  group('findPlanText', () {
    PlanWord w(String text, [double x = 0]) =>
        PlanWord(text, Rect.fromLTWH(x, 0, 0.03, 0.01));
    List<String> sizes(List<List<PlanWord>> lines) => findPlanText(lines)
        .sizes
        .map((s) => '${s.text}=${s.mm.round()}')
        .toList();
    List<String> oneWordLines(List<String> words) => sizes([
          for (final t in words) [w(t)]
        ]);

    test('picks the dimension labels off an imperial plan', () {
      // The top dimension row of floor_plan/What-is-a-floor-plan-...png.
      expect(
        sizes([
          [w('7\'2"'), w('7\'8"', 0.2), w('8\'0"', 0.4), w('10\'5"', 0.6)],
        ]),
        ['7\'2"=2184', '7\'8"=2337', '8\'0"=2438', '10\'5"=3175'],
      );
    });

    test('room names and areas are labels, not sizes', () {
      final text = findPlanText([
        [w('Kitchen')],
        [w('85'), w('sq', 0.1), w('ft', 0.2)],
        [w('1500'), w('sq', 0.1), w('ft', 0.2)],
      ]);
      expect(text.sizes, isEmpty);
      expect(text.labels.map((l) => l.text),
          ['Kitchen', '85 sq ft', '1500 sq ft']);
    });

    test('a room size gives both of its sizes, and keeps the room name', () {
      final text = findPlanText([
        [w('DAPUR'), w('3000x2400', 0.1)],
        [w('BILIK'), w('3.6'), w('x'), w('3.0m')],
      ]);
      expect(
        text.sizes.map((s) => '${s.text}=${s.mm.round()}'),
        ['3000=3000', '2400=2400', '3.6m=3600', '3.0m=3000'],
      );
      // The line is kept as the room's label: it's how the kitchen is found.
      expect(text.labels.map((l) => l.text),
          ['DAPUR 3000x2400', 'BILIK 3.6 x 3.0m']);
      expect(text.sizes.first.line, 'DAPUR 3000x2400');
    });

    test('a room size in feet', () {
      expect(
          sizes([
            [w('KITCHEN'), w('18\''), w('x'), w('10\'')],
          ]),
          ['18\'=5486', '10\'=3048']);
    });

    test('millimetre plans: 3–5 digit numbers, punctuation stripped', () {
      expect(oneWordLines(['3000', '(2,400)', '12', '250']),
          ['3000=3000', '(2,400)=2400']);
    });

    test('joins feet and inches the reader split into two words', () {
      final text = findPlanText([
        [w('15\''), w('1"', 0.1), w('17\'', 0.3), w('1', 0.4)],
      ]);
      expect(text.sizes.map((s) => s.text), ['15\' 1"', '17\' 1']);
      // The box covers both words, so the whole label is the tap target.
      expect(text.sizes.first.box, const Rect.fromLTRB(0, 0, 0.13, 0.01));
    });

    // Read off floor_plan/What-is-a-floor-plan-with-dimensions.png on the
    // emulator: the small foot mark is the mark most often lost.
    test('on an imperial plan, a lost foot mark is put back', () {
      expect(
        oneWordLines(['10\'5"', '151"', '80"', '171"', '105"', '1110"']),
        [
          '10\'5"=3175',
          '15\'1"=4597',
          '8\'0"=2438',
          '17\'1"=5207',
          '10\'5"=3175',
          '11\'10"=3607'
        ],
      );
    });

    test('on an imperial plan, an inch mark in place of the foot mark', () {
      expect(oneWordLines(['9\'5"', '17"1"', '17"1']),
          ['9\'5"=2870', '17\'1"=5207', '17\'1"=5207']);
    });

    test('on an imperial plan, numbers that lost both marks are dropped', () {
      // "58" is 5'8", "1410" is 14'10": not millimetres, too risky to guess.
      expect(oneWordLines(['5\'8', '58', '78', '1410', '3000']), ['5\'8=1727']);
    });

    test('a metric plan keeps inches it prints', () {
      expect(oneWordLines(['3000', '96"']), ['3000=3000', '96"=2438']);
    });
  });
}
