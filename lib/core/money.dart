// Money is ALWAYS an int number of sen. RM 12.50 is 1250.
//
// Why not double? Floating point cannot store 0.1 exactly, so
// 0.1 + 0.2 == 0.30000000000000004. Integers add up exactly.

/// 106400 -> "RM 1,064.00". Set [symbol] false for "1,064.00".
String formatSen(int sen, {bool symbol = true, bool decimals = true}) {
  final negative = sen < 0;
  final abs = sen.abs();
  final whole = abs ~/ 100;
  final cents = abs % 100;

  final grouped = _groupThousands(whole);
  final body = decimals ? '$grouped.${cents.toString().padLeft(2, '0')}' : grouped;
  return '${negative ? '-' : ''}${symbol ? 'RM ' : ''}$body';
}

/// Turns what a person types into sen. Returns null if it is not valid money.
///
///   "12.5"      -> 1250
///   "1,234.50"  -> 123450
///   "RM 68"     -> 6800
///   "12.505"    -> null (more than 2 decimals)
///   ""          -> null
///
/// It reads the text digit by digit instead of using double.parse, so no
/// floating point is ever involved.
int? parseSen(String input) {
  final cleaned = input.trim().replaceFirst(RegExp(r'^RM\s*', caseSensitive: false), '').replaceAll(',', '');

  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;

  final whole = int.parse(match.group(1)!);
  final cents = int.parse((match.group(2) ?? '').padRight(2, '0'));
  return whole * 100 + cents;
}

String _groupThousands(int n) {
  final s = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
    buffer.write(s[i]);
  }
  return buffer.toString();
}
