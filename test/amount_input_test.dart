import 'package:bayar/core/amount_input.dart';
import 'package:flutter_test/flutter_test.dart';

String type(String keys) {
  var text = '';
  for (final key in keys.split(' ')) {
    text = AmountKeys.press(text, key);
  }
  return text;
}

void main() {
  group('typing', () {
    test('digits build up', () => expect(type('1 2 5'), '125'));

    test('a decimal point starts decimals', () => expect(type('1 2 . 5'), '12.5'));

    test('a point first becomes 0.', () => expect(type('.'), '0.'));

    test('only one point is accepted', () => expect(type('1 . 5 . 2'), '1.52'));

    test('at most two decimals', () => expect(type('1 . 2 5 9'), '1.25'));

    test('no leading zeros', () {
      expect(type('0 5'), '5');
      expect(type('0 0 0'), '0');
      expect(type('0 . 5'), '0.5');
    });

    test('delete removes the last key, and is safe when empty', () {
      expect(type('1 2 del'), '1');
      expect(type('1 del del del'), '');
      expect(type('del'), '');
    });

    test('delete can take back a decimal point', () => expect(type('1 2 . del'), '12'));

    test('length is capped', () {
      final text = type('1 2 3 4 5 6 7 8 9 0 1 2');
      expect(text.length, AmountKeys.maxLength);
    });
  });

  group('amountSenFromKeys', () {
    test('whole ringgit', () => expect(AmountKeys.amountSenFromKeys('12'), 1200));
    test('decimals', () {
      expect(AmountKeys.amountSenFromKeys('12.5'), 1250);
      expect(AmountKeys.amountSenFromKeys('12.50'), 1250);
      expect(AmountKeys.amountSenFromKeys('0.05'), 5);
    });
    test('a trailing point is whole ringgit', () => expect(AmountKeys.amountSenFromKeys('12.'), 1200));
    test('nothing typed is zero', () {
      expect(AmountKeys.amountSenFromKeys(''), 0);
      expect(AmountKeys.amountSenFromKeys('0'), 0);
      expect(AmountKeys.amountSenFromKeys('0.'), 0);
    });
  });

  test('display shows 0 before anything is typed', () {
    expect(AmountKeys.display(''), '0');
    expect(AmountKeys.display('12.5'), '12.5');
  });
}
