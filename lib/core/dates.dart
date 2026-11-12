/// Calendar dates ("12 Nov") with no time of day.
///
/// We store them as DateTime.utc(year, month, day). Using UTC midnight means
/// no daylight-saving shift can ever turn "12 Nov" into "11 Nov 23:00".
DateTime dateOf(int year, int month, int day) => DateTime.utc(year, month, day);

/// Drops the time part (and the time zone) of any DateTime.
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// 28, 29, 30 or 31. Day 0 of next month is the last day of this month, and
/// DateTime rolls month 13 over into January of the next year for us.
int lastDayOfMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// "Due on the 31st" in a 30-day month means the 30th (28th/29th in Feb).
DateTime clampedDate(int year, int month, int day) {
  final last = lastDayOfMonth(year, month);
  return DateTime.utc(year, month, day > last ? last : day);
}

/// [days] after [d] (or before, if negative). DateTime rolls day 33 of
/// November over to 3 December for us, so no Duration or time zone is involved.
DateTime addDays(DateTime d, int days) => DateTime.utc(d.year, d.month, d.day + days);

/// Whole days from [from] to [to]. Negative if [to] is earlier.
int daysBetween(DateTime from, DateTime to) => dateOnly(to).difference(dateOnly(from)).inDays;

/// "2026-11-12". Sorts correctly as plain text, so SQLite can ORDER BY it.
String toIsoDate(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime fromIsoDate(String s) {
  final parts = s.split('-');
  return DateTime.utc(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Thu 12 Nov"
String formatShortDate(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// "Thu 12 Nov 2026"
String formatDateWithYear(DateTime d) => '${formatShortDate(d)} ${d.year}';

/// "Nov"
String monthAbbr(DateTime d) => _months[d.month - 1];
