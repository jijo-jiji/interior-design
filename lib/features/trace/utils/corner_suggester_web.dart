import 'corner_suggestion.dart';

/// In the browser the model would be a 27 MB download on every visit, so
/// corners are placed by hand there.
class DeviceCornerSuggester implements CornerSuggester {
  const DeviceCornerSuggester();

  @override
  Future<CornerSuggestion> suggest(String imagePath) async =>
      const CornerSuggestion.unavailable();
}
