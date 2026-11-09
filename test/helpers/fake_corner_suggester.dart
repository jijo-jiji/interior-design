import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:static_trace/features/trace/providers/wall_provider.dart';
import 'package:static_trace/features/trace/utils/corner_suggestion.dart';

/// Stands in for the wall-corner model: answers with [result], or waits for
/// [gate] first. By default there is no model, as in the browser.
class FakeCornerSuggester implements CornerSuggester {
  FakeCornerSuggester(
      [this.result = const CornerSuggestion.unavailable(), this.gate]);

  final CornerSuggestion result;
  final Completer<void>? gate;
  final asked = <String>[];

  @override
  Future<CornerSuggestion> suggest(String imagePath) async {
    asked.add(imagePath);
    await gate?.future;
    return result;
  }
}

/// No wall-corner model: for tests about something else. A fresh fake each
/// time, so what one test asked doesn't carry into the next.
Override get noCornerModel =>
    cornerSuggesterProvider.overrideWithValue(FakeCornerSuggester());
