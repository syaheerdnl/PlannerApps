/// One row as the cloud sends it.
class RemoteRow {
  const RemoteRow(this.data, this.serverUpdatedAt);

  /// The row's columns, using the same names as the local table.
  final Map<String, Object?> data;

  /// When the CLOUD last saved this row, on the cloud's own clock.
  ///
  /// Used as the pull cursor instead of the row's `updated_at`, which comes from
  /// a phone's clock. A phone with a wrong clock could otherwise write a row
  /// "in the past" and other phones, having already passed that moment, would
  /// never see it.
  final DateTime serverUpdatedAt;
}

/// Where the data is kept in the cloud. The sync engine only knows this interface,
/// so it can be tested against an in-memory fake and run against Supabase.
abstract class RemoteStore {
  /// Every row of [table] saved since [since] (everything if null), oldest first.
  Future<List<RemoteRow>> pullChanges(String table, {DateTime? since});

  /// Inserts or updates [rows] by their key.
  Future<void> push(String table, List<Map<String, Object?>> rows);
}
