import 'package:bayar/core/theme.dart';
import 'package:bayar/screens/bills_screen.dart';
import 'package:bayar/services/bill_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_bill_scanner.dart';
import 'support/test_env.dart';

void main() {
  late TestEnv env;

  const tnbBill = '''
Tenaga Nasional Berhad
Jumlah Perlu Dibayar
RM 162.35
Tarikh Akhir Bayaran 21/11/2026
''';

  Future<void> boot(WidgetTester tester, FakeBillScanner scanner) async {
    await tester.runAsync(() async => env = await TestEnv.create());
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      env.providers(
        Provider<BillScanner>.value(
          value: scanner,
          child: MaterialApp(
            theme: buildTheme(),
            home: const Scaffold(body: BillsScreen()),
          ),
        ),
      ),
    );
  }

  Future<void> scanFromGallery(WidgetTester tester) async {
    await tester.tap(find.text('Add bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan a bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();
  }

  testWidgets('a scanned bill fills the name, amount and due date, and says so', (tester) async {
    final scanner = FakeBillScanner(tnbBill);
    await boot(tester, scanner);
    await scanFromGallery(tester);

    expect(scanner.asked, [ScanSource.gallery]);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(0)).controller!.text, 'TNB');
    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(1)).controller!.text, '162.35');
    expect(find.text('Sat 21 Nov 2026'), findsOneWidget); // the first due date
    expect(find.text('Filled in the name, amount, due date. Please check before saving.'), findsOneWidget);
    // Nothing is saved until the person taps "Add bill".
    final saved = await tester.runAsync(() => env.obligations.all());
    expect(saved!.where((o) => o.name == 'TNB'), isEmpty);
  });

  testWidgets('a scanned bill can then be saved like any other', (tester) async {
    await boot(tester, FakeBillScanner(tnbBill));
    await scanFromGallery(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add bill'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => env.obligations.all());
    final tnb = saved!.where((o) => o.name == 'TNB').toList();
    expect(tnb, hasLength(1));
    expect(tnb.first.amountSen, 16235);
    expect(tnb.first.startDate, DateTime.utc(2026, 11, 21));
  });

  testWidgets('only what was found is filled; the rest stays as it was', (tester) async {
    await boot(tester, FakeBillScanner('Total 45.00'));
    await scanFromGallery(tester);

    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(0)).controller!.text, '');
    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(1)).controller!.text, '45.00');
    expect(find.text('Thu 12 Nov 2026'), findsOneWidget); // still today
    expect(find.text('Filled in the amount. Please check before saving.'), findsOneWidget);
  });

  testWidgets('a photo with nothing readable says so and changes nothing', (tester) async {
    await boot(tester, FakeBillScanner('~~~'));
    await scanFromGallery(tester);

    expect(find.textContaining('Could not read a bill from that photo'), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).at(1)).controller!.text, '');
  });

  testWidgets('backing out of the camera or gallery shows no message', (tester) async {
    await boot(tester, FakeBillScanner(null));
    await scanFromGallery(tester);

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a camera or permission failure is explained, not a crash', (tester) async {
    await boot(tester, FakeBillScanner(null, fails: true));
    await scanFromGallery(tester);

    expect(find.textContaining('Check that Bayar may use the camera or photos'), findsOneWidget);
  });

  testWidgets('"Take a photo" asks the camera', (tester) async {
    final scanner = FakeBillScanner('Total 45.00');
    await boot(tester, scanner);
    await tester.tap(find.text('Add bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan a bill'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();

    expect(scanner.asked, [ScanSource.camera]);
  });

  testWidgets('editing an existing bill has no scan button', (tester) async {
    await boot(tester, FakeBillScanner(tnbBill));
    await tester.tap(find.text('Streaming'));
    await tester.pumpAndSettle();

    expect(find.text('Edit bill'), findsOneWidget);
    expect(find.text('Scan a bill'), findsNothing);
  });
}
