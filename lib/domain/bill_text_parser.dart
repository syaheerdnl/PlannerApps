// Reads the text of a photographed bill and guesses the name, the amount and
// the due date. It only GUESSES: the person always reviews the form before saving.
//
// Pure Dart (text in, values out), so it is easy to test without a camera.

/// What could be read from a bill. Any field can be null when nothing sensible was found.
class ScannedBill {
  const ScannedBill({this.name, this.amountSen, this.dueDate});

  final String? name;
  final int? amountSen;

  /// Date-only, UTC (like every date in this app).
  final DateTime? dueDate;

  bool get isEmpty => name == null && amountSen == null && dueDate == null;

  @override
  String toString() => 'ScannedBill($name, $amountSen, $dueDate)';
}

/// Words that mark the line with the amount to pay (English and Malay).
const _amountWords = [
  // "Jumlah Perlu Dibayar" is often misread ("Junl ah ..."), but "Perlu Dibayar" survives.
  'perlu dibayar',
  'amount due',
  'total due',
  'amount payable',
  'total payable',
  'total amount',
  'please pay',
  'pay this amount',
  'balance due',
  'current charges',
  'jumlah perlu dibayar',
  'jumlah bayaran',
  'jumlah bil',
  'amaun perlu dibayar',
  'jumlah',
  'amount',
  'total',
];

/// Words that mark the due date.
const _dueWords = [
  'due date',
  'due on',
  'pay by',
  'pay before',
  'payment due',
  'tarikh akhir',
  'tarikh bayaran',
  'bayar sebelum',
  'due',
];

/// Providers worth recognising by name. The key is matched inside the text, lower-cased.
const _knownProviders = {
  'tenaga nasional': 'TNB',
  'tnb': 'TNB',
  'air selangor': 'Air Selangor',
  'syabas': 'Syabas',
  'indah water': 'Indah Water',
  'unifi': 'Unifi',
  'telekom malaysia': 'TM',
  'maxis': 'Maxis',
  'celcom': 'CelcomDigi',
  'digi': 'CelcomDigi',
  'u mobile': 'U Mobile',
  'yes 4g': 'YES',
  'astro': 'Astro',
  'tm net': 'TM Net',
};

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'mei': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'ogos': 8, //
  'sep': 9, 'oct': 10, 'okt': 10, 'nov': 11, 'dec': 12, 'dis': 12,
};

// 1,234.50 or 68.00 (always two decimals: that is what makes it money and not a account number).
final _money = RegExp(r'(?<![\d.,])(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?![\d])');

// 15/12/2026, 15-12-2026, 15.12.2026 (and 2-digit years: 15/12/26)
final _numericDate = RegExp(r'(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?!\d)');

// 15 Dec 2026, 15 December 2026, 15-Dec-2026
final _wordDate = RegExp(r'(?<!\d)(\d{1,2})[\s\-]*([A-Za-z]{3,9})[\s,\-]*(\d{4})(?!\d)');

/// Reads [text]. [today] decides what counts as a sensible year, e.g. it rejects a date 20 years away.
ScannedBill parseBillText(String text, {required DateTime today}) {
  final lines = _normalise(text).split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return const ScannedBill();

  return ScannedBill(name: _findName(lines), amountSen: _findAmount(lines), dueDate: _findDate(lines, today));
}

/// OCR often puts a space after a decimal point or a date dot: "296. 15", "02.05. 2025".
/// Close those gaps so the number and date patterns can see them.
String _normalise(String text) => text.replaceAllMapped(RegExp(r'(\d)\.[ \t]+(\d)'), (m) => '${m[1]}.${m[2]}');

// ── amount ──────────────────────────────────────────────────────────────────

int? _findAmount(List<String> lines) {
  // 1. A line that names the amount, with the money on it or on the line after.
  //    Earlier words in [_amountWords] are more specific, so they win.
  for (final word in _amountWords) {
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].toLowerCase().contains(word)) continue;
      final here = _moneyIn(lines[i]);
      if (here.isNotEmpty) return here.last;
      if (i + 1 < lines.length) {
        final next = _moneyIn(lines[i + 1]);
        if (next.isNotEmpty) return next.first;
      }
    }
  }
  // 2. No usable label (OCR can garble it). The total to pay is printed more than once on a bill
  //    (summary, stub, barcode strip) while a deposit or an old balance appears once, so take the
  //    amount that repeats; if nothing repeats, the biggest.
  final all = lines.expand(_moneyIn).toList();
  if (all.isEmpty) return null;
  final counts = <int, int>{};
  for (final a in all) {
    counts[a] = (counts[a] ?? 0) + 1;
  }
  final repeated = counts.entries.where((e) => e.value >= 2).toList()
    ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : b.key.compareTo(a.key));
  if (repeated.isNotEmpty) return repeated.first.key;
  all.sort();
  return all.last;
}

List<int> _moneyIn(String line) {
  return [
    for (final m in _money.allMatches(line))
      if (_toSen(m) case final sen? when sen > 0) sen,
  ];
}

int? _toSen(RegExpMatch m) {
  final whole = int.tryParse(m.group(1)!.replaceAll(',', ''));
  final cents = int.tryParse(m.group(2)!);
  if (whole == null || cents == null) return null;
  return whole * 100 + cents;
}

// ── date ────────────────────────────────────────────────────────────────────

DateTime? _findDate(List<String> lines, DateTime today) {
  bool sensible(DateTime d) => d.year >= today.year - 1 && d.year <= today.year + 2;

  // A date on (or just after) a line that says "due".
  for (final word in _dueWords) {
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].toLowerCase().contains(word)) continue;
      for (final candidate in [lines[i], if (i + 1 < lines.length) lines[i + 1]]) {
        final dates = _datesIn(candidate).where(sensible).toList();
        if (dates.isNotEmpty) return dates.last;
      }
    }
  }
  // No "due" label: do not guess. A bill also has a statement date and a period, and a wrong due date is worse than none.
  return null;
}

List<DateTime> _datesIn(String line) {
  final found = <DateTime>[];

  for (final m in _numericDate.allMatches(line)) {
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    final d = _valid(year, month, day);
    if (d != null) found.add(d);
  }
  for (final m in _wordDate.allMatches(line)) {
    final month = _months[m.group(2)!.toLowerCase().substring(0, 3)];
    if (month == null) continue;
    final d = _valid(int.parse(m.group(3)!), month, int.parse(m.group(1)!));
    if (d != null) found.add(d);
  }
  return found;
}

/// Rejects 31 Feb and the like (DateTime.utc would quietly roll it into March).
DateTime? _valid(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final d = DateTime.utc(year, month, day);
  return d.month == month ? d : null;
}

// ── name ────────────────────────────────────────────────────────────────────

String? _findName(List<String> lines) {
  final whole = lines.join('\n').toLowerCase();
  // Longest key first, so "tenaga nasional" is tried before "tnb"; whole-word match, so "digital" is not "Digi".
  final keys = _knownProviders.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (RegExp('(?<![a-z])${RegExp.escape(key)}(?![a-z])').hasMatch(whole)) return _knownProviders[key];
  }

  // Otherwise the first line that looks like a company name: mostly letters, not a label.
  for (final line in lines.take(6)) {
    final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
    if (line.length < 3 || line.length > 40) continue;
    if (letters < line.length * 0.7) continue;
    final lower = line.toLowerCase();
    if (const ['invoice', 'bill', 'statement', 'tax', 'receipt', 'bil', 'penyata'].any(lower.startsWith)) continue;
    return line;
  }
  return null;
}
