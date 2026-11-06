/// How the design is dressed in the 3D view and in its pictures: the style of
/// the doors, the backsplash, the decor and the light. Presentation only:
/// none of it changes the price.
class SceneLook {
  const SceneLook({
    this.doors = 'slab',
    this.backsplash = 'subway',
    this.decor = true,
    this.mood = 'day',
  });

  /// `slab` (flat), `shaker` (framed, recessed panel) or `raised`.
  final String doors;

  /// `none`, `subway` or `hex`.
  final String backsplash;

  /// Plates, jars, plants and the like on the worktop. Never part of the quote.
  final bool decor;

  /// `day` or `evening` (warm, with the under-cabinet lights on).
  final String mood;

  static const doorOptions = {
    'slab': 'Flat',
    'shaker': 'Shaker',
    'raised': 'Raised panel',
  };
  static const backsplashOptions = {
    'none': 'None',
    'subway': 'Subway tile',
    'hex': 'Hexagon tile',
  };
  static const moodOptions = {'day': 'Day', 'evening': 'Evening'};

  /// Reads a saved design's `scene`, using the defaults for anything missing
  /// or not recognised (an older design, or a newer app's value).
  factory SceneLook.fromJson(Object? json) {
    if (json is! Map) return const SceneLook();
    String pick(String key, Map<String, String> options, String fallback) {
      final value = json[key];
      return value is String && options.containsKey(value) ? value : fallback;
    }

    return SceneLook(
      doors: pick('doors', doorOptions, 'slab'),
      backsplash: pick('backsplash', backsplashOptions, 'subway'),
      decor: json['decor'] is bool ? json['decor'] as bool : true,
      mood: pick('mood', moodOptions, 'day'),
    );
  }

  Map<String, dynamic> toJson() => {
        'doors': doors,
        'backsplash': backsplash,
        'decor': decor,
        'mood': mood,
      };

  SceneLook copyWith(
          {String? doors, String? backsplash, bool? decor, String? mood}) =>
      SceneLook(
        doors: doors ?? this.doors,
        backsplash: backsplash ?? this.backsplash,
        decor: decor ?? this.decor,
        mood: mood ?? this.mood,
      );

  /// The calls that put this look on the 3D page, in the order it needs
  /// (the doors first: they rebuild every cabinet).
  List<String> get javaScript => [
        "setDoorStyle('$doors')",
        "setBacksplash('$backsplash')",
        'setDecor($decor)',
        "setMood('$mood')",
      ];

  @override
  bool operator ==(Object other) =>
      other is SceneLook &&
      other.doors == doors &&
      other.backsplash == backsplash &&
      other.decor == decor &&
      other.mood == mood;

  @override
  int get hashCode => Object.hash(doors, backsplash, decor, mood);
}
