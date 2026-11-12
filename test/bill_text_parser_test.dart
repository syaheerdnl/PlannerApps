import 'package:bayar/domain/bill_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime.utc(2026, 11, 12);
  ScannedBill parse(String text) => parseBillText(text, today: today);

  group('amount', () {
    test('takes the money on the "amount due" line, not the biggest number', () {
      final b = parse('''
Previous balance RM 900.00
Current charges RM 120.40
Amount Due RM 68.50
''');
      expect(b.amountSen, 6850);
    });

    test('reads thousands separators', () {
      expect(parse('Total Amount Due: RM 1,234.50').amountSen, 123450);
    });

    test('reads an amount that sits on the line AFTER its label (common in OCR of tables)', () {
      expect(parse('Jumlah Perlu Dibayar\nRM 88.90').amountSen, 8890);
    });

    test('with no label, falls back to the largest amount', () {
      expect(parse('Item A 12.00\nItem B 250.00\nItem C 9.90').amountSen, 25000);
    });

    test('ignores account numbers and phone numbers: money always has two decimals', () {
      expect(parse('Account 1234567890\nCall 03-12345678\nTotal 45.00').amountSen, 4500);
    });

    test('null when there is no money at all', () {
      expect(parse('Hello world').amountSen, isNull);
    });

    test('a zero amount is not an amount', () {
      expect(parse('Amount due RM 0.00').amountSen, isNull);
    });
  });

  group('due date', () {
    test('numeric day/month/year', () {
      expect(parse('Due Date: 25/11/2026').dueDate, DateTime.utc(2026, 11, 25));
    });

    test('dashes and dots, and a two-digit year', () {
      expect(parse('Pay by 5-12-2026').dueDate, DateTime.utc(2026, 12, 5));
      expect(parse('Pay by 05.12.26').dueDate, DateTime.utc(2026, 12, 5));
    });

    test('month names, English and Malay', () {
      expect(parse('Due on 25 November 2026').dueDate, DateTime.utc(2026, 11, 25));
      expect(parse('Tarikh Akhir Bayaran: 3 Dis 2026').dueDate, DateTime.utc(2026, 12, 3));
    });

    test('picks the date next to "due", not the statement date', () {
      final b = parse('''
Statement date 01/11/2026
Billing period 01/10/2026 - 31/10/2026
Due date 21/11/2026
''');
      expect(b.dueDate, DateTime.utc(2026, 11, 21));
    });

    test('a date on the line after the label', () {
      expect(parse('Tarikh Akhir Bayaran\n21/11/2026').dueDate, DateTime.utc(2026, 11, 21));
    });

    test('with no "due" label it does not guess a date', () {
      expect(parse('Statement date 01/11/2026').dueDate, isNull);
    });

    test('rejects impossible dates (31 Feb) and absurd years', () {
      expect(parse('Due 31/02/2026').dueDate, isNull);
      expect(parse('Due 15/12/2051').dueDate, isNull);
      expect(parse('Due 15/12/1999').dueDate, isNull);
    });

    test('a smudged OCR month does not crash', () {
      expect(parse('Due 15 Xyz 2026').dueDate, isNull);
    });
  });

  group('name', () {
    test('recognises a known provider anywhere on the bill', () {
      expect(parse('Invoice\nTenaga Nasional Berhad\nAmount RM 10.00').name, 'TNB');
      expect(parse('Your Unifi bill').name, 'Unifi');
    });

    test('matches whole words only: "digital" is not Digi', () {
      expect(parse('Digital Concepts Sdn Bhd\nTotal 10.00').name, 'Digital Concepts Sdn Bhd');
    });

    test('unknown company: the first company-looking line, skipping labels', () {
      expect(parse('INVOICE\nBright Gym Sdn Bhd\nTotal RM 99.00').name, 'Bright Gym Sdn Bhd');
    });

    test('lines that are mostly digits are not names', () {
      expect(parse('0123456789\n12/11/2026\nTotal 5.00').name, isNull);
    });
  });

  test('a full realistic electricity bill', () {
    final b = parse('''
Tenaga Nasional Berhad
Penyata Bil / Bill Statement
No. Akaun 2201-3344-5566
Tarikh Bil 01/11/2026
Caj Semasa RM 150.20
Jumlah Perlu Dibayar
RM 162.35
Tarikh Akhir Bayaran 21/11/2026
''');
    expect(b.name, 'TNB');
    expect(b.amountSen, 16235);
    expect(b.dueDate, DateTime.utc(2026, 11, 21));
  });

  test('empty or junk text gives an empty result', () {
    expect(parse('').isEmpty, isTrue);
    expect(parse('   \n  \n').isEmpty, isTrue);
    expect(parse('~~~ ### !!!').isEmpty, isTrue);
  });
}
