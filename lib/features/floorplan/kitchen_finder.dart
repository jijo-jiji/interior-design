import 'plan_sizes.dart';

/// The kitchen on a plan and the printed sizes its cabinet walls are made
/// of, found by [findKitchen]. Every length is one printed on the plan.
class KitchenWalls {
  const KitchenWalls({
    required this.kitchenLabel,
    required this.isLShape,
    required this.mainWall,
    this.returnWall,
  });

  /// The kitchen's name as read off the plan ("DAPUR", "WET KITCHEN").
  final PlanLabel kitchenLabel;
  final bool isLShape;
  final WallPick mainWall;
  final WallPick? returnWall;

  /// Every size picked for a wall shown here.
  Iterable<PlanSize> get pickedSizes =>
      [...mainWall.sizes, if (isLShape) ...?returnWall?.sizes];
}

/// The printed sizes a wall is made of: usually one, two when a wall spans
/// two printed segments.
class WallPick {
  const WallPick({required this.sizes, required this.where});
  final List<PlanSize> sizes;

  /// Where the wall is, in words: "Top wall of the kitchen".
  final String where;

  /// The wall as the salesperson would type it: "9'8\"" or "9'5\" + 5'8\"".
  String? get text =>
      sizes.isEmpty ? null : sizes.map((s) => s.text).join(' + ');
}

/// Names a kitchen goes by on Malaysian developer plans.
const _kitchenWords = ['KITCHEN', 'DAPUR', 'PANTRY'];

/// Finds the kitchen among the labels read off a plan, and the room size
/// printed for it ("DAPUR 3000 x 2400"). Plain rules, no guessing: a room
/// size is the kitchen's only when it's printed with the kitchen's name or
/// just under it. Null when no label names a kitchen.
///
/// A kitchen with a room size is a room with a usable corner, so it starts
/// as an L: the first number is the main wall, the second the side wall.
/// The salesperson can still switch to a single wall.
KitchenWalls? findKitchen(PlanText text) {
  PlanLabel? kitchen;
  var best = -1 << 30;
  for (final label in text.labels) {
    final score = _kitchenScore(label.text);
    if (score != null && score > best) {
      best = score;
      kitchen = label;
    }
  }
  if (kitchen == null) return null;

  final pair = roomSizeOf(kitchen, text);
  if (pair == null) {
    return KitchenWalls(
      kitchenLabel: kitchen,
      isLShape: false,
      mainWall: const WallPick(sizes: [], where: ''),
    );
  }
  return KitchenWalls(
    kitchenLabel: kitchen,
    isLShape: true,
    mainWall: WallPick(
      sizes: [pair.$1],
      where: "Main wall, from the kitchen's room size",
    ),
    returnWall: WallPick(
      sizes: [pair.$2],
      where: "Side wall, from the kitchen's room size",
    ),
  );
}

/// How strongly [labelText] names a kitchen, or null if it doesn't. A wet
/// kitchen is where the cooking (and the cabinets) are, so it wins over a
/// dry one.
int? _kitchenScore(String labelText) {
  final words = labelText.toUpperCase().split(RegExp(r'[^A-Z]+'));
  if (!words.where((w) => w.length >= 4).any(_isKitchenWord)) return null;
  var score = 0;
  if (words.contains('WET') || words.contains('BASAH')) score += 2;
  if (words.contains('DRY') || words.contains('KERING')) score -= 1;
  return score;
}

/// "KITCHEN", or what the reader makes of it: one wrong, missing or extra
/// letter in a word of five letters or more ("KITCHEM", "DAPOR").
bool _isKitchenWord(String word) => _kitchenWords.any(
      (k) => word == k || (k.length >= 5 && _withinOneEdit(word, k)),
    );

bool _withinOneEdit(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  var i = 0, j = 0, edits = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (a.length > b.length) {
      i++;
    } else if (a.length < b.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return edits + (a.length - i) + (b.length - j) <= 1;
}

/// The two sizes of a room size read off one printed line, in order.
List<(PlanSize, PlanSize)> _roomSizes(PlanText text) {
  final pairs = <(PlanSize, PlanSize)>[];
  final sizes = text.sizes;
  for (var i = 0; i + 1 < sizes.length; i++) {
    final a = sizes[i], b = sizes[i + 1];
    if (a.line == b.line &&
        a.box == b.box &&
        RegExp(r'[x×]', caseSensitive: false).hasMatch(a.line)) {
      pairs.add((a, b));
      i++;
    }
  }
  return pairs;
}

/// The room size printed with [label]: on its own line, or the nearest one
/// just under it that overlaps it sideways.
(PlanSize, PlanSize)? roomSizeOf(PlanLabel label, PlanText text) {
  final pairs = _roomSizes(text);
  for (final pair in pairs) {
    if (pair.$1.line == label.text && pair.$1.box == label.box) return pair;
  }

  final box = label.box;
  final reach = box.height * 3;
  (PlanSize, PlanSize)? nearest;
  var nearestGap = double.infinity;
  for (final pair in pairs) {
    final b = pair.$1.box;
    final gap = b.top - box.bottom;
    final overlaps = b.left < box.right && b.right > box.left;
    if (gap >= -box.height / 2 &&
        gap <= reach &&
        overlaps &&
        gap < nearestGap) {
      nearest = pair;
      nearestGap = gap;
    }
  }
  return nearest;
}

/// The sizes to offer as buttons: one per value, since a plan can print the
/// same size twice (and the reader can read one label twice). Where two
/// sizes share a value, the one picked for the kitchen's walls is kept, so
/// tapping it marks the kitchen's size on the plan, not another room's.
List<PlanSize> sizeChoices(PlanText text, KitchenWalls? walls) {
  final picked = <PlanSize>[...?walls?.pickedSizes];
  final byValue = <int, PlanSize>{};
  for (final s in [...picked, ...text.sizes]) {
    byValue.putIfAbsent(s.mm.round(), () => s);
  }
  // In reading order, as on the plan.
  return [
    for (final s in text.sizes)
      if (identical(byValue[s.mm.round()], s)) s,
  ];
}
