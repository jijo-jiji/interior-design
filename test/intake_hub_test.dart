import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:static_trace/features/intake/providers/consultation_provider.dart';
import 'package:static_trace/features/intake/screens/intake_hub_screen.dart';
import 'package:static_trace/features/viewer/utils/offline_store.dart';

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
      GoRoute(
        path: '/viewer',
        builder: (_, state) => Scaffold(body: Text('3D view: ${state.extra}')),
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

  testWidgets('no Continue card without a saved draft', (tester) async {
    await pumpHome(tester);
    expect(find.textContaining('Continue'), findsNothing);
  });

  testWidgets('the newest draft can be picked up from the home screen',
      (tester) async {
    await tester.runAsync(() async {
      await OfflineStore.saveDraft({
        'quote_id': 'QT-OLDER',
        'status': 'draft',
        'client_name': 'Encik Lim',
      });
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await OfflineStore.saveDraft({
        'quote_id': 'QT-NEWEST',
        'status': 'draft',
        'client_name': 'Puan Aminah',
      });
    });
    addTearDown(() async {
      await OfflineStore.removeDraft('QT-OLDER');
      await OfflineStore.removeDraft('QT-NEWEST');
    });
    await pumpHome(tester);
    // Let the list load (the office server is unreachable in tests).
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text("Continue Puan Aminah's design"), findsOneWidget);
    expect(find.text('Draft · saved just now'), findsOneWidget);
    expect(find.text("Continue Encik Lim's design"), findsNothing);

    await tester.tap(find.text("Continue Puan Aminah's design"));
    await tester.pumpAndSettle();
    expect(find.textContaining('QT-NEWEST'), findsOneWidget);
  });
}
