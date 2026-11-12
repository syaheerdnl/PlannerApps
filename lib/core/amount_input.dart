import 'money.dart';

/// Keypad logic for typing an amount of money, one key at a time.
///
/// The amount is kept as text ("12.5") while typing, because "12." and "12.50"
/// are different things to a person but not to a number. Turn it into sen with
/// [amountSenFromKeys] only when saving.
class AmountKeys {
  const AmountKeys._();

  static const maxLength = 9;

  /// [key] is a digit, '.', or 'del'. Returns the new text; ignores keys that make no sense.
  static String press(String current, String key) {
    if (key == 'del') return current.isEmpty ? current : current.substring(0, current.length - 1);

    if (key == '.') {
      if (current.contains('.')) return current;
      return current.isEmpty ? '0.' : '$current.';
    }

    if (current.length >= maxLength) return current;
    final dot = current.indexOf('.');
    if (dot >= 0 && current.length - dot > 2) return current; // already 2 decimals
    if (current == '0') return key; // no leading zeros ("05")
    return '$current$key';
  }

  /// "12.5" -> 1250. Empty, "0" or "." -> 0. A trailing dot ("12.") counts as whole ringgit.
  static int amountSenFromKeys(String text) {
    if (text.isEmpty) return 0;
    final cleaned = text.endsWith('.') ? text.substring(0, text.length - 1) : text;
    return parseSen(cleaned) ?? 0;
  }

  /// What to show on screen: "0" when nothing is typed yet.
  static String display(String text) => text.isEmpty ? '0' : text;
}
