import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    // ProviderScope is the Riverpod root — wraps the entire widget tree.
    const ProviderScope(
      child: StaticTraceApp(),
    ),
  );
}
