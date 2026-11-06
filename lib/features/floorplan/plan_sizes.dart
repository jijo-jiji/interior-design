import 'dart:ui' show Rect, Size;

// Sizes as they are printed on floor plans, in millimetres.
//
// Developer plans print wall lengths in millimetres ("3000", "3,000"),
// metres ("3.0m") or feet and inches ("9'8\"", "9' - 8\"", "9ft 8in").
// Reading those numbers is exact; measuring the drawing is not, because a
// brochure plan is usually not to scale and a fingertip covers more of the
// plan than the sizes it is trying to find.

const double _mmPerFoot = 304.8;
const double _mmPerInch = 25.4;

const _number = r'(\d+(?:\.\d+)?)';
const _inches = r'(\d+(?:\.\d+)?)(?:\s+(\d+)\s*/\s*(\d+))?';

final _feetInches = RegExp(
  '^$_number\\s*(?:\'|ft|feet|foot)\\s*-?\\s*'
  '(?:$_inches\\s*(?:"|in|inch|inches)?)?\$',
);
final _inchesOnly = RegExp('^$_inches\\s*(?:"|in|inch|inches)\$');
final _metric = RegExp('^$_number\\s*(mm|cm|m)\$');
final _bare = RegExp(r'^\d+(?:\.\d+)?$');
final _thousands = RegExp(r'^\d{1,3}(?:,\d{3})+(?:\.\d+)?$');

/// Straightens typographic quotes and primes, which plans and phone
/// keyboards both produce, so "9’8”" reads like "9'8\"".
String _normalise(String input) => input
    .toLowerCase()
    .replaceAll(RegExp('[‘’′´`]'), "'")
    .replaceAll(RegExp('[“”″]'), '"')
    .replaceAll("''", '"')
    .trim();

double? _parseTerm(String raw) {
  var term = raw.trim();
  if (term.isEmpty) return null;
  if (_thousands.hasMatch(term)) term = term.replaceAll(',', '');

  if (_bare.hasMatch(term)) return double.parse(term);

  final metric = _metric.firstMatch(term);
  if (metric != null) {
    final value = double.parse(metric[1]!);
    return switch (metric[2]) {
      'm' => value * 1000,
      'cm' => value * 10,
      _ => value,
    };
  }

  double inchesFrom(String? whole, String? num, String? den) {
    var inches = whole == null ? 0.0 : double.parse(whole);
    if (num != null && den != null && double.parse(den) != 0) {
      inches += double.parse(num) / double.parse(den);
    }
    return inches;
  }

  final ft = _feetInches.firstMatch(term);
  if (ft != null) {
    return double.parse(ft[1]!) * _mmPerFoot +
        inchesFrom(ft[2], ft[3], ft[4]) * _mmPerInch;
  }

  final inch = _inchesOnly.firstMatch(term);
  if (inch != null) return inchesFrom(inch[1], inch[2], inch[3]) * _mmPerInch;

  return null;
}

/// Converts a typed or printed length to millimetres, or null if it isn't
/// one. A plain number is millimetres. A wall that spans two printed
/// segments can be entered as a sum: "9'5\" + 5'8\"".
double? parseLengthMm(String input) {
  final text = _normalise(input);
  if (text.isEmpty) return null;
  var total = 0.0;
  for (final term in text.split('+')) {
    final mm = _parseTerm(term);
    if (mm == null) return null;
    total += mm;
  }
  return total > 0 ? total : null;
}

/// Whether [input] says its own unit. Plain numbers are millimetres, so
/// "3.6" is 3.6 mm: worth asking about rather than silently scaling.
bool hasExplicitUnit(String input) => RegExp(
      r"""['"]|\d\s*(mm|cm|m|ft|feet|foot|in|inch|inches)\b""",
    ).hasMatch(_normalise(input));

/// "2946" → "2,946 mm".
String formatMm(double mm) {
  final whole = mm.round().toString();
  return '${whole.replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',')} mm';
}

// ── Reading sizes off the text found on a plan ─────────────────────────────

/// Plan sizes outside this range are not walls (room areas, scale bars, door
/// numbers), so they are not offered.
const double kMinPlanSizeMm = 300, kMaxPlanSizeMm = 20000;

/// One word read off the plan, with its box as fractions of the plan.
class PlanWord {
  const PlanWord(this.text, this.box);
  final String text;
  final Rect box;
}

/// A size printed on the plan.
class PlanSize {
  const PlanSize({
    required this.text,
    required this.mm,
    required this.box,
    this.line = '',
  });

  /// As printed (or as repaired, see [findPlanText]), so the salesperson can
  /// check it against the plan.
  final String text;
  final double mm;

  /// As fractions of the plan.
  final Rect box;

  /// The whole printed line it came from, e.g. "KITCHEN 3000 x 2400".
  final String line;
}

/// Any other text on the plan: room names, areas, notes.
class PlanLabel {
  const PlanLabel(this.text, this.box);
  final String text;
  final Rect box;
}

/// What could be read off a plan.
class PlanText {
  const PlanText({
    this.sizes = const [],
    this.labels = const [],
    this.planSize,
  });
  final List<PlanSize> sizes;
  final List<PlanLabel> labels;

  /// The plan image's own size in pixels, when the reader got that far: a
  /// small plan explains why its sizes couldn't be read.
  final Size? planSize;

  bool get isEmpty => sizes.isEmpty && labels.isEmpty;

  PlanText withPlanSize(Size size) =>
      PlanText(sizes: sizes, labels: labels, planSize: size);
}

/// Words after a number that make it an area, not a length.
const _areaUnits = {'sq', 'sqft', 'sf', 'sq.ft', 'sq.ft.', 'm2', 'm²', 'ft2'};

/// A whole number of feet with its foot mark, as on any imperial plan.
final _footMark = RegExp(r"^\d+\s*'");

/// One side of a room size: "3000", "3.0m", "18'", "10'6\"".
const _side =
    r"""\d[\d.,]*(?:\s*'\s*-?\s*(?:\d{1,2}\s*"?)?|\s*(?:mm|cm|m)\b)?""";

/// A room size printed as one pair: "3000 x 2400", "3.0 x 2.4m", "18' x 10'".
final _roomSize = RegExp('($_side)\\s*[x×]\\s*($_side)');

/// Picks the sizes and labels out of the words read from a plan, one list
/// of words per printed line. Feet and inches the reader split into two
/// words ("9'" "8\"") are joined back together, and a room size ("3000 x
/// 2400") gives two sizes.
///
/// On a plan in feet and inches, the reader's slips are repaired rather than
/// trusted: it loses the small foot mark ("15'1\"" read as "151\"", which
/// would be 151 inches) or reads it as an inch mark ("17\"1\""). Each size
/// keeps the text as repaired, which matches what is printed on the plan,
/// so a wrong repair shows up before it's used.
PlanText findPlanText(List<List<PlanWord>> lines) {
  final imperial = lines.any(
    (words) => words.any((w) => _footMark.hasMatch(_clean(w.text))),
  );
  final sizes = <PlanSize>[];
  final labels = <PlanLabel>[];

  for (final words in lines) {
    if (words.isEmpty) continue;
    final lineText = words.map((w) => w.text).join(' ');
    final lineBox =
        words.map((w) => w.box).reduce((a, b) => a.expandToInclude(b));
    final found = <PlanSize>[];

    // A room size: both numbers, with the unit of one side applied to a
    // bare other side ("3.0 x 2.4m" is metres on both).
    final pairWords = <String>{};
    for (final m in _roomSize.allMatches(_normalise(lineText))) {
      var a = m[1]!.trim(), b = m[2]!.trim();
      final unit = RegExp(r'(mm|cm|m)$');
      if (unit.firstMatch(b) case final u? when !hasExplicitUnit(a)) {
        a = '$a${u[1]}';
      } else if (unit.firstMatch(a) case final u? when !hasExplicitUnit(b)) {
        b = '$b${u[1]}';
      }
      final pair = [
        for (final side in [a, b]) _readSize(side, null, imperial)
      ];
      if (pair.every((s) => s != null)) {
        for (final s in pair) {
          found.add(
              PlanSize(text: s!.text, mm: s.mm, box: lineBox, line: lineText));
        }
        pairWords.addAll(m[0]!.split(RegExp(r'\s+')));
      }
    }

    var i = 0;
    while (i < words.length) {
      final word = words[i];
      final next = i + 1 < words.length ? words[i + 1] : null;
      if (pairWords.isNotEmpty &&
          (pairWords.contains(_normalise(word.text)) ||
              RegExp(r'[x×]', caseSensitive: false).hasMatch(word.text))) {
        i++;
        continue;
      }

      // A size the reader split in two, like "9'" + "8\"" (it often
      // drops the inch mark, so a bare 0–11 counts as inches too).
      if (next != null &&
          _normalise(word.text).endsWith("'") &&
          _looksLikeInches(next.text)) {
        final size = _readSize('${word.text} ${next.text}', null, imperial);
        if (size != null) {
          found.add(PlanSize(
            text: size.text,
            mm: size.mm,
            box: word.box.expandToInclude(next.box),
            line: lineText,
          ));
          i += 2;
          continue;
        }
      }

      final size = _readSize(word.text, next?.text, imperial);
      if (size != null) {
        found.add(PlanSize(
            text: size.text, mm: size.mm, box: word.box, line: lineText));
      }
      i++;
    }

    sizes.addAll(found);
    // "KITCHEN 3000 x 2400" is a room name as well as its sizes.
    if (found.isEmpty || RegExp(r'[A-Za-z]{3,}').hasMatch(lineText)) {
      labels.add(PlanLabel(lineText, lineBox));
    }
  }
  return PlanText(sizes: sizes, labels: labels);
}

bool _looksLikeInches(String word) {
  final m =
      RegExp(r'^(\d{1,2})(?:\s+\d+\s*/\s*\d+)?\s*("|in|inch|inches)?[,;]?$')
          .firstMatch(_normalise(word));
  return m != null && int.parse(m[1]!) < 12;
}

/// The reader often keeps the punctuation around a size: "(3000)", "9'8\",".
String _clean(String word) =>
    _normalise(word.replaceAll(RegExp(r'^[(\[]+|[)\],;:]+$'), ''));

/// Undoes the reader's slips on an imperial plan: null if [text] doesn't
/// need it, an empty string if it can't be repaired.
String? _repairImperial(String text) {
  // An inch mark where the foot mark was: 17"1" is 17'1".
  final swapped = RegExp(r'^(\d+)"\s*(\d{1,2})"?$').firstMatch(text);
  if (swapped != null) {
    return int.parse(swapped[2]!) < 12 ? "${swapped[1]}'${swapped[2]}\"" : '';
  }

  // Twelve inches or more on its own is a lost foot mark: 151" is 15'1",
  // 80" is 8'0", 1110" is 11'10".
  final inchesOnly = RegExp(r'^(\d+)"$').firstMatch(text);
  if (inchesOnly == null || int.parse(inchesOnly[1]!) < 12) return null;
  final digits = inchesOnly[1]!;
  for (final inchDigits in [1, 2]) {
    if (digits.length <= inchDigits) continue;
    final inches = int.parse(digits.substring(digits.length - inchDigits));
    // 10 and 11 are the only two-digit inches; "1'05\"" is printed 1'5".
    if (inches >= 12 || (inchDigits == 2 && inches < 10)) continue;
    final repaired =
        "${digits.substring(0, digits.length - inchDigits)}'$inches\"";
    final mm = parseLengthMm(repaired)!;
    if (mm >= kMinPlanSizeMm && mm <= kMaxPlanSizeMm) return repaired;
  }
  return '';
}

({String text, double mm})? _readSize(
  String word,
  String? followedBy,
  bool imperial,
) {
  // A pair ("3000x2400") is read as a room size, not here.
  if (RegExp(r'[x×]', caseSensitive: false).hasMatch(word)) return null;
  var text = _clean(word);
  if (text.contains('+')) return null;
  var shown = word.trim();

  if (imperial) {
    // A bare number on an imperial plan is a size that lost both its marks
    // ("5'8" read as "58"), not millimetres. Too ambiguous to repair.
    if (!hasExplicitUnit(text)) return null;
    final repaired = _repairImperial(text);
    if (repaired == '') return null;
    if (repaired != null) text = shown = repaired;
  }

  final mm = parseLengthMm(text);
  if (mm == null || mm < kMinPlanSizeMm || mm > kMaxPlanSizeMm) return null;

  // "1500 sq ft" is an area. A bare number must also look like millimetres
  // on a metric plan (three or more digits), not a room or page number.
  if (!hasExplicitUnit(text)) {
    final after = followedBy == null ? '' : _normalise(followedBy);
    if (_areaUnits.contains(after)) return null;
    if (!RegExp(r'^\d{3,5}$').hasMatch(text.replaceAll(',', ''))) return null;
  }
  return (text: shown, mm: mm);
}
