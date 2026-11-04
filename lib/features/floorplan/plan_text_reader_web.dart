import 'plan_sizes.dart';
import 'plan_text_reader.dart';

/// No text reader in the browser: the plan's sizes are typed in there.
class DevicePlanTextReader implements PlanTextReader {
  const DevicePlanTextReader();

  @override
  Future<PlanText> read(String imagePath) async => const PlanText();
}
