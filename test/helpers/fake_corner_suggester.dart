import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:static_trace/features/trace/providers/wall_provider.dart';
import 'package:static_trace/features/trace/utils/corner_suggestion.dart';
import 'package:static_trace/features/trace/utils/opening_finder.dart';
import 'package:static_trace/features/trace/utils/wall_segmenter.dart';

/// Stands in for the wall-corner model: answers with [result], or waits for
/// [gate] first. By default there is no model, as in the browser.
class FakeCornerSuggester implements CornerSuggester {
  FakeCornerSuggester(
      [this.result = const CornerSuggestion.unavailable(), this.gate]);

  final CornerSuggestion result;
  final Completer<void>? gate;
  final asked = <String>[];

  /// Whether each ask came with a way to fetch the segmentation labels.
  final offeredLabels = <bool>[];

  @override
  Future<CornerSuggestion> suggest(String imagePath,
      {Future<WallLabels?> Function()? labels}) async {
    asked.add(imagePath);
    offeredLabels.add(labels != null);
    await gate?.future;
    return result;
  }
}

/// No wall-corner model: for tests about something else. A fresh fake each
/// time, so what one test asked doesn't carry into the next.
Override get noCornerModel =>
    cornerSuggesterProvider.overrideWithValue(FakeCornerSuggester());

/// Stands in for the wall segmentation model: answers with [labels] (null:
/// no model, as in the browser).
class FakeWallSegmenter implements WallSegmenter {
  FakeWallSegmenter([this.result]);

  final WallLabels? result;

  @override
  Future<WallLabels?> labels(String imagePath) async => result;
}

/// No segmentation model: for tests about something else.
Override get noWallSegmenter =>
    wallSegmenterProvider.overrideWithValue(FakeWallSegmenter());
