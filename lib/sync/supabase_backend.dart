import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_backend.dart';
import 'remote_store.dart';

/// Where to find the cloud. Pass both when building:
///
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=your-anon-key
///
/// The anon (or publishable) key is designed to be public: what protects your data is the
/// row-level security in supabase/migrations/001_bayar_sync.sql, which lets each
/// signed-in user read and write only their own rows.
class CloudConfig {
  const CloudConfig._();

  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

/// Supabase as the cloud: email and password sign-in, and Postgres tables for the data.
///
/// NOT yet tested against a live Supabase project. The sync logic itself is
/// tested against an in-memory cloud; this class only translates it to Supabase calls.
class SupabaseBackend implements CloudBackend {
  SupabaseBackend(this._client);

  /// Call once at start-up, only if [CloudConfig.isConfigured].
  static Future<SupabaseBackend> connect() async {
    await Supabase.initialize(url: CloudConfig.url, publishableKey: CloudConfig.anonKey);
    return SupabaseBackend(Supabase.instance.client);
  }

  final SupabaseClient _client;

  /// Rows per request when downloading.
  static const _pageSize = 1000;

  @override
  bool get isConfigured => true;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  String? get email => _client.auth.currentUser?.email;

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    final response = await _client.auth.signUp(email: email.trim(), password: password);
    return response.session != null;
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<List<RemoteRow>> pullChanges(String table, {DateTime? since}) async {
    final keyColumn = table == 'settings' ? 'key' : 'id';
    final out = <RemoteRow>[];

    for (var from = 0; ; from += _pageSize) {
      final query = _client.from(table).select();
      final filtered = since == null ? query : query.gt('server_updated_at', since.toUtc().toIso8601String());
      final page = await filtered
          .order('server_updated_at', ascending: true)
          .order(keyColumn, ascending: true)
          .range(from, from + _pageSize - 1);

      for (final row in page) {
        final data = Map<String, Object?>.from(row);
        out.add(RemoteRow(data, DateTime.parse(data['server_updated_at'] as String).toUtc()));
      }
      if (page.length < _pageSize) return out;
    }
  }

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final userId = _client.auth.currentUser!.id;
    await _client.from(table).upsert([
      for (final r in rows) {...r, 'user_id': userId},
    ], onConflict: table == 'settings' ? 'user_id,key' : 'user_id,id');
  }
}
