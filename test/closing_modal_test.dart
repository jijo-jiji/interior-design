import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:static_trace/features/viewer/widgets/closing_modal.dart';

class _Call {
  _Call(this.name, this.deposit, this.signature);
  final String name;
  final double deposit;
  final String? signature;
}

void main() {
  late List<_Call> calls;

  Future<void> pumpSheet(WidgetTester tester, {String clientName = ''}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    calls = [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ClosingModal(
          placedCabinets: const [
            {'cabinet_type': 'base_600', 'kind': 'base'},
            {'cabinet_type': 'filler_base', 'kind': 'filler'},
          ],
          styleName: 'Japandi Natural',
          totalPrice: 18450,
          clientName: clientName,
          onConfirm: ({
            required clientName,
            required clientPhone,
            required clientEmail,
            required depositAmount,
            required signatureBase64,
          }) async {
            calls.add(_Call(clientName, depositAmount, signatureBase64));
          },
        ),
      ),
    ));
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets('shows the total in RM and counts cabinets without fillers',
      (tester) async {
    await pumpSheet(tester, clientName: 'Puan Aminah');
    expect(find.text('RM 18,450'), findsOneWidget);
    expect(find.text('1 cabinet'), findsOneWidget);
    expect(find.text('Puan Aminah'), findsOneWidget);
  });

  testWidgets('a quote can be saved without a signature', (tester) async {
    await pumpSheet(tester, clientName: 'Puan Aminah');
    await tapButton(tester, 'Save & send quote');

    expect(calls, hasLength(1));
    expect(calls.single.name, 'Puan Aminah');
    expect(calls.single.deposit, 0);
    expect(calls.single.signature, isNull);
  });

  testWidgets('the client name is required', (tester) async {
    await pumpSheet(tester);
    await tapButton(tester, 'Save & send quote');

    expect(calls, isEmpty);
    expect(find.text("Enter the client's name."), findsOneWidget);
  });

  testWidgets('confirming an order needs a deposit amount and a signature',
      (tester) async {
    await pumpSheet(tester, clientName: 'Puan Aminah');
    await tester.tap(find.text('Client paid a deposit'));
    await tester.pump();
    expect(find.text('Confirm order'), findsOneWidget);
    expect(find.text('Client signature *'), findsOneWidget);

    await tapButton(tester, 'Confirm order');
    expect(find.text('Enter the deposit amount.'), findsOneWidget);
    expect(calls, isEmpty);

    await tester.enterText(
        find.widgetWithText(TextField, 'Deposit amount *'), '1,500');
    await tapButton(tester, 'Confirm order');
    expect(
      find.text('The client needs to sign to confirm the order.'),
      findsOneWidget,
    );
    expect(calls, isEmpty);
  });

  testWidgets('no invented terms or financing on the sheet', (tester) async {
    await pumpSheet(tester, clientName: 'Puan Aminah');
    expect(find.textContaining('Guarantees'), findsNothing);
    expect(find.textContaining('/mo'), findsNothing);
    expect(find.textContaining('AUD'), findsNothing);
  });
}
