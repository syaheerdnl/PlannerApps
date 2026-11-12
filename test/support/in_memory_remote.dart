import 'package:bayar/sync/remote_store.dart';

/// A pretend cloud, shared by two or more pretend phones in a test.
///
/// Like the real one, it stamps every saved row with ITS OWN clock
/// ([serverUpdatedAt]), which only ever moves forward.
class InMemoryRemote implements RemoteStore {
  final Map<String, Map<Object, _Stored>> _tables = {};
  int _tick = 0;

  /// While true, every call fails, like a phone with no signal.
  bool offline = false;

  /// If set, the Nth push call (counting from now) throws, to test a failure half way.
  int? failOnPushNumber;
  int _pushes = 0;

  int pushCalls = 0;
  int pullCalls = 0;

  Map<String, Object?>? row(String table, Object key) => _tables[table]?[key]?.data;

  List<Map<String, Object?>> rows(String table) => [for (final s in (_tables[table] ?? {}).values) s.data];

  @override
  Future<List<RemoteRow>> pullChanges(String table, {DateTime? since}) async {
    pullCalls++;
    if (offline) throw Exception('No connection');
    final stored =
        (_tables[table] ?? {}).values.where((s) => since == null || s.serverUpdatedAt.isAfter(since)).toList()
          ..sort((a, b) => a.serverUpdatedAt.compareTo(b.serverUpdatedAt));
    return [
      for (final s in stored) RemoteRow({...s.data}, s.serverUpdatedAt),
    ];
  }

  /// Pretends this row was STAMPED [ago] before the newest stamp in the cloud, as when its
  /// transaction started early but committed late.
  void restampBehindNewest(String table, Object key, Duration ago) {
    final newest = _tables.values
        .expand((t) => t.values)
        .map((s) => s.serverUpdatedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final stored = _tables[table]![key]!;
    _tables[table]![key] = _Stored(stored.data, newest.subtract(ago));
  }

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) async {
    pushCalls++;
    _pushes++;
    if (offline) throw Exception('No connection');
    if (failOnPushNumber != null && _pushes == failOnPushNumber) throw Exception('Upload failed');

    final keyColumn = table == 'settings' ? 'key' : 'id';
    final map = _tables.putIfAbsent(table, () => {});
    for (final r in rows) {
      _tick++;
      map[r[keyColumn]!] = _Stored({...r}, DateTime.utc(2030, 1, 1).add(Duration(seconds: _tick)));
    }
  }
}

class _Stored {
  _Stored(this.data, this.serverUpdatedAt);

  final Map<String, Object?> data;
  final DateTime serverUpdatedAt;
}
