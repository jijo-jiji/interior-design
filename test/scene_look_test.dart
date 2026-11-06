import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/models/scene_look.dart';

void main() {
  test('a new design has flat doors, subway tile, decor and day light', () {
    const look = SceneLook();
    expect(look.toJson(), {
      'doors': 'slab',
      'backsplash': 'subway',
      'decor': true,
      'mood': 'day',
    });
  });

  test('a saved look reads back as it was saved', () {
    const look = SceneLook(
        doors: 'raised', backsplash: 'hex', decor: false, mood: 'evening');
    expect(SceneLook.fromJson(look.toJson()), look);
  });

  test('anything missing or unrecognised falls back on the defaults', () {
    expect(SceneLook.fromJson(null), const SceneLook());
    expect(SceneLook.fromJson('nonsense'), const SceneLook());
    expect(SceneLook.fromJson(<String, dynamic>{}), const SceneLook());
    expect(
      SceneLook.fromJson({
        'doors': 'glass-fronted',
        'backsplash': 42,
        'decor': 'yes',
        'mood': 'noon',
      }),
      const SceneLook(),
    );
    // One good field is kept next to a bad one.
    expect(SceneLook.fromJson({'doors': 'shaker', 'mood': '??'}),
        const SceneLook(doors: 'shaker'));
  });

  test('copyWith changes only what is named', () {
    const look = SceneLook();
    expect(look.copyWith(mood: 'evening').mood, 'evening');
    expect(look.copyWith(mood: 'evening').doors, 'slab');
    expect(look.copyWith(decor: false).decor, isFalse);
  });

  test('it tells the page to change the doors first (they rebuild cabinets)',
      () {
    const look = SceneLook(
        doors: 'shaker', backsplash: 'hex', decor: false, mood: 'evening');
    expect(look.javaScript, [
      "setDoorStyle('shaker')",
      "setBacksplash('hex')",
      'setDecor(false)',
      "setMood('evening')",
    ]);
  });

  test('every option the page is told about is one the page knows', () {
    // The page's names (assets/3d/index.html): setDoorStyle, BACKSPLASHES, MOODS.
    expect(SceneLook.doorOptions.keys, ['slab', 'shaker', 'raised']);
    expect(SceneLook.backsplashOptions.keys, ['none', 'subway', 'hex']);
    expect(SceneLook.moodOptions.keys, ['day', 'evening']);
  });
}
