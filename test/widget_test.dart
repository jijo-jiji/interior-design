import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App smoke test — camera screen renders',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: StaticTraceApp()),
    );
    // Camera won't initialise in test env, but the scaffold should render
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
