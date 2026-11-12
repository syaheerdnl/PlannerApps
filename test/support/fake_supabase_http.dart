import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A stand-in for a Supabase project's web API, so the REAL supabase_flutter
/// client (and our SupabaseBackend on top of it) can be tested without a network.
///
/// It imitates the parts of Supabase that matter to sync:
///  * sign-in / sign-up that hand out a token;
///  * row-level security: a user only sees and writes THEIR OWN rows;
///  * upsert with `on_conflict`, and the server stamping `server_updated_at`;
///  * the `gt.` filter, ordering and paging of PostgREST;
///  * REJECTING any column that is not in supabase/migrations/001_bayar_sync.sql,
///    like Postgres would, so a mismatch between the app and the SQL file shows up.
class FakeSupabaseServer {
  /// table -> composite key -> row
  final Map<String, Map<String, Map<String, Object?>>> tables = {};

  /// Every request the client made, in order.
  final List<http.Request> requests = [];

  /// email -> password
  final Map<String, String> users = {'me@example.com': 'secret1'};

  /// If true, sign-up creates the account but returns no session (email must be confirmed).
  bool requireConfirmation = false;

  /// While true every request fails like a lost connection.
  bool offline = false;

  int _tick = 0;

  /// The request being answered. The Supabase client reads `response.request`, so every response carries it.
  http.BaseRequest? _current;

  http.Client get client => MockClient(handle);

  /// The columns each table has, as created by the SQL file (including user_id and server_updated_at).
  static const _columns = {
    'obligations': {
      'user_id', 'id', 'name', 'amount_sen', 'is_estimate', 'frequency', 'interval_count', 'start_date', //
      'end_date', 'pay_by_buffer_days', 'note', 'created_at', 'updated_at', 'deleted_at', 'server_updated_at',
    },
    'payments': {
      'user_id', 'id', 'obligation_id', 'due_date', 'amount_sen', 'paid_at', 'created_at', 'updated_at', //
      'deleted_at', 'server_updated_at',
    },
    'envelopes': {'user_id', 'id', 'name', 'sort_order', 'created_at', 'updated_at', 'deleted_at', 'server_updated_at'},
    'allocations': {
      'user_id', 'id', 'envelope_id', 'cycle_start', 'amount_sen', 'created_at', 'updated_at', //
      'deleted_at', 'server_updated_at',
    },
    'spendings': {
      'user_id', 'id', 'envelope_id', 'amount_sen', 'note', 'spent_on', 'created_at', 'updated_at', //
      'deleted_at', 'server_updated_at',
    },
    'settings': {'user_id', 'key', 'value', 'updated_at', 'server_updated_at'},
  };

  /// Puts rows straight into a table for [userId], as if another phone had uploaded them.
  void seed(String table, String userId, List<Map<String, Object?>> rows, {String keyColumn = 'id'}) {
    for (final row in rows) {
      _store(table, {...row, 'user_id': userId}, keyColumn);
    }
  }

  int count(String table, String userId) => (tables[table] ?? {}).values.where((r) => r['user_id'] == userId).length;

  List<http.Request> requestsTo(String pathPart, {String? method}) =>
      requests.where((r) => r.url.path.contains(pathPart) && (method == null || r.method == method)).toList();

  // ── request handling ──────────────────────────────────────────────────────

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    _current = request;
    if (offline) throw http.ClientException('Connection failed');

    final path = request.url.path;
    if (path == '/auth/v1/token') return _signIn(request);
    if (path == '/auth/v1/signup') return _signUp(request);
    if (path == '/auth/v1/logout') return http.Response('', 204, request: _current);
    if (path.startsWith('/rest/v1/')) return _rest(request, path.substring('/rest/v1/'.length));
    return _json({'message': 'Not found: $path'}, 404);
  }

  http.Response _signIn(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final email = body['email'] as String;
    if (users[email] != body['password']) {
      return _json({'code': 400, 'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'}, 400);
    }
    return _json(_session(email));
  }

  http.Response _signUp(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final email = body['email'] as String;
    if (users.containsKey(email)) {
      return _json({'code': 422, 'error_code': 'user_already_exists', 'msg': 'User already registered'}, 422);
    }
    users[email] = body['password'] as String;
    if (requireConfirmation) return _json(_user(email));
    return _json(_session(email));
  }

  http.Response _rest(http.Request request, String table) {
    final columns = _columns[table];
    if (columns == null) return _json({'message': 'relation "$table" does not exist'}, 404);

    // Row-level security: no signed-in user means no rows, and no writes.
    final userId = _userIdFrom(request);
    if (userId == null) {
      return request.method == 'GET'
          ? _json(<Object?>[])
          : _json({'code': '42501', 'message': 'new row violates row-level security policy'}, 401);
    }
    final keyColumn = table == 'settings' ? 'key' : 'id';

    if (request.method == 'GET') return _select(request, table, userId, keyColumn);
    if (request.method == 'POST') return _upsert(request, table, userId, columns);
    return _json({'message': 'Unsupported'}, 405);
  }

  http.Response _select(http.Request request, String table, String userId, String keyColumn) {
    var rows = (tables[table] ?? {}).values.where((r) => r['user_id'] == userId).toList();

    for (final filter in request.url.queryParametersAll.entries) {
      if (filter.key != 'server_updated_at') continue;
      for (final value in filter.value) {
        if (value.startsWith('gt.')) {
          final after = DateTime.parse(value.substring(3));
          rows = rows.where((r) => DateTime.parse(r['server_updated_at'] as String).isAfter(after)).toList();
        }
      }
    }

    final order = (request.url.queryParametersAll['order'] ?? []).expand((o) => o.split(',')).toList();
    rows.sort((a, b) {
      for (final o in order) {
        final column = o.split('.').first;
        final descending = o.endsWith('.desc');
        final c = '${a[column]}'.compareTo('${b[column]}');
        if (c != 0) return descending ? -c : c;
      }
      return 0;
    });

    final offset = int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '');
    rows = rows.skip(offset).toList();
    if (limit != null) rows = rows.take(limit).toList();

    return _json(rows);
  }

  http.Response _upsert(http.Request request, String table, String userId, Set<String> columns) {
    final rows = (jsonDecode(request.body) as List).cast<Map<String, dynamic>>();
    final conflict = request.url.queryParameters['on_conflict'];
    final prefer = request.headers['Prefer'] ?? request.headers['prefer'] ?? '';
    if (conflict == null || !prefer.contains('resolution=merge-duplicates')) {
      return _json({'message': 'Upsert without on_conflict / merge-duplicates would fail on a duplicate key'}, 409);
    }

    for (final row in rows) {
      final unknown = row.keys.where((c) => !columns.contains(c)).toList();
      if (unknown.isNotEmpty) {
        return _json({'code': 'PGRST204', 'message': "Could not find the '${unknown.first}' column of '$table'"}, 400);
      }
      if (row['user_id'] != userId) {
        return _json({
          'code': '42501',
          'message': 'new row violates row-level security policy for table "$table"',
        }, 403);
      }
    }
    for (final row in rows) {
      _store(table, Map<String, Object?>.from(row), conflict);
    }
    return http.Response('', 201, request: _current);
  }

  void _store(String table, Map<String, Object?> row, String conflictColumns) {
    final key = conflictColumns.split(',').map((c) => '${row[c]}').join('|');
    _tick++;
    // Postgres returns timestamptz as "...+00:00", not "...Z".
    row['server_updated_at'] = DateTime.utc(
      2030,
      1,
      1,
    ).add(Duration(seconds: _tick)).toIso8601String().replaceFirst('Z', '+00:00');
    (tables.putIfAbsent(table, () => {}))[key] = row;
  }

  // ── tokens ────────────────────────────────────────────────────────────────

  String userIdFor(String email) => 'user-${email.hashCode.abs()}';

  Map<String, Object?> _user(String email) => {
    'id': userIdFor(email),
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': email,
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-01-01T00:00:00Z',
  };

  Map<String, Object?> _session(String email) => {
    'access_token': _jwt(userIdFor(email)),
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    'refresh_token': 'refresh-token',
    'user': _user(email),
  };

  String _jwt(String userId) {
    String part(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': userId, 'role': 'authenticated', 'exp': 9999999999})}.signature';
  }

  /// The user a request is made as, from its "Authorization: Bearer" header. Null for the anonymous key.
  String? _userIdFrom(http.Request request) {
    final header = request.headers['Authorization'] ?? request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    final parts = header.substring(7).split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      return payload['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    request: _current,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
