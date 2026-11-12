import 'package:bayar/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSen', () {
    test('formats ringgit and sen', () {
      expect(formatSen(1250), 'RM 12.50');
      expect(formatSen(5), 'RM 0.05');
      expect(formatSen(0), 'RM 0.00');
    });

    test('groups thousands', () {
      expect(formatSen(106400), 'RM 1,064.00');
      expect(formatSen(380000), 'RM 3,800.00');
      expect(formatSen(123456789), 'RM 1,234,567.89');
    });

    test('negative amounts keep the minus sign in front', () {
      expect(formatSen(-5), '-RM 0.05');
      expect(formatSen(-150000), '-RM 1,500.00');
    });

    test('can drop the symbol and decimals', () {
      expect(formatSen(106400, symbol: false), '1,064.00');
      expect(formatSen(106400, decimals: false), 'RM 1,064');
    });
  });

  group('parseSen', () {
    test('parses whole and decimal amounts', () {
      expect(parseSen('12'), 1200);
      expect(parseSen('12.5'), 1250);
      expect(parseSen('12.50'), 1250);
      expect(parseSen('0.1'), 10);
      expect(parseSen('0.05'), 5);
    });

    test('ignores commas, spaces and an RM prefix', () {
      expect(parseSen('1,234.50'), 123450);
      expect(parseSen(' RM 68 '), 6800);
      expect(parseSen('rm68.00'), 6800);
    });

    test('rejects anything that is not valid money', () {
      expect(parseSen(''), isNull);
      expect(parseSen('abc'), isNull);
      expect(parseSen('12.505'), isNull);
      expect(parseSen('-5'), isNull);
      expect(parseSen('1.2.3'), isNull);
    });

    test('is exact where doubles are not', () {
      // 0.1 + 0.2 in doubles is 0.30000000000000004. In sen it is exact.
      expect(parseSen('0.1')! + parseSen('0.2')!, parseSen('0.3'));
    });

    test('round-trips with formatSen', () {
      for (final sen in [0, 1, 99, 100, 1250, 106400, 99999999]) {
        expect(parseSen(formatSen(sen)), sen);
      }
    });
  });
}
