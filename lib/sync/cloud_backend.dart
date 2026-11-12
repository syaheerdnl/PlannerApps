import 'remote_store.dart';

/// The cloud as the app sees it: somewhere to sign in, plus the data store.
///
/// The app talks only to this interface. [SupabaseBackend] is the real one, and
/// [NoCloud] stands in when the build has no cloud configured, so the app works
/// fully offline without it.
abstract class CloudBackend implements RemoteStore {
  /// False when this build has no cloud address, so sync cannot be used at all.
  bool get isConfigured;

  bool get isSignedIn;

  String? get email;

  Future<void> signIn(String email, String password);

  /// Returns true if the new account is signed in straight away, false if the
  /// cloud first needs the email address confirmed.
  Future<bool> signUp(String email, String password);

  Future<void> signOut();
}

/// Used when no cloud is configured. Every sync action is a no-op.
class NoCloud implements CloudBackend {
  const NoCloud();

  @override
  bool get isConfigured => false;

  @override
  bool get isSignedIn => false;

  @override
  String? get email => null;

  @override
  Future<void> signIn(String email, String password) => Future.error(StateError('Sync is not configured'));

  @override
  Future<bool> signUp(String email, String password) => Future.error(StateError('Sync is not configured'));

  @override
  Future<void> signOut() async {}

  @override
  Future<List<RemoteRow>> pullChanges(String table, {DateTime? since}) async => const [];

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) async {}
}
