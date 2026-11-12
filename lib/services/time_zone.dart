import 'package:timezone/timezone.dart' as tz;

/// Turns the phone's time zone name ("Asia/Kuala_Lumpur") into a location the
/// notification plugin can schedule in.
///
/// The timezone database must be loaded first, with `latest_all.dart`. The
/// smaller `latest.dart` leaves out alias zones such as Asia/Kuala_Lumpur (a
/// link to Asia/Singapore), which is exactly how reminders once ended up
/// scheduled in UTC, 8 hours off.
///
/// If the name is missing or unknown, falls back to any location whose current
/// UTC offset equals the phone's [deviceOffset], and as a last resort UTC.
tz.Location resolveLocation({String? identifier, required Duration deviceOffset}) {
  if (identifier != null) {
    try {
      return tz.getLocation(identifier);
    } catch (_) {
      // Unknown name: fall through to the offset match below.
    }
  }

  for (final location in tz.timeZoneDatabase.locations.values) {
    if (location.currentTimeZone.offset == deviceOffset) return location;
  }
  return tz.UTC;
}
