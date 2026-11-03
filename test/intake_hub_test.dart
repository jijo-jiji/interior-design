import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:static_trace/features/intake/providers/consultation_provider.dart';
import 'package:static_trace/features/intake/screens/intake_hub_screen.dart';

void main() {
  late ProviderContainer container;

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const IntakeHubScreen()),
      GoRoute(
        path: '/template-room',
        builder: (_, __) => const Scaffold(body: Text('Room size screen')),
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
  }

  testWidgets('home screen has no sales jargon or invented stats',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('SS Love'), findsOneWidget);
    expect(find.textContaining('Closer'), findsNothing);
    expect(find.textContaining('Avg Close'), findsNothing);
    expect(find.textContaining('Three.js'), findsNothing);
  });

  testWidgets('starting a new client asks for their name first',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Room size only'));
    await tester.pumpAndSettle();

    expect(find.text('New client'), findsWidgets);
    final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
    expect(tester.widget<ElevatedButton>(continueButton).onPressed, isNull);

    await tester.enterText(
        find.widgetWithText(TextField, 'Client name'), 'Puan Aminah');
    await tester.pump();
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    final consultation = container.read(consultationProvider);
    expect(consultation, isNotNull);
    expect(consultation!.clientName, 'Puan Aminah');
    expect(consultation.quoteId, startsWith('QT-'));
    expect(find.text('Room size screen'), findsOneWidget);
  });

  testWidgets('the name can be skipped for a quick showroom demo',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.text('Room size only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    expect(container.read(consultationProvider)?.clientName, '');
    expect(find.text('Room size screen'), findsOneWidget);
  });
}
