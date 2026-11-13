import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The wall-corner model ships inside the app (Apache 2.0): its licence goes
  // with it, alongside the packages' in the app's licence list.
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Depth Anything V2 Small', 'LICENSE-depth-anything-v2.txt'),
      ('DeepLabV3+ (MLCommons, ADE20K)', 'LICENSE-deeplab-ade20k.txt'),
    ]) {
      try {
        final text = await rootBundle.loadString('assets/models/$file');
        yield LicenseEntryWithLineBreaks([name], text);
      } catch (_) {
        // Not in this build.
      }
    }
  });
  runApp(
    // ProviderScope is the Riverpod root — wraps the entire widget tree.
    const ProviderScope(
      child: StaticTraceApp(),
    ),
  );
}
