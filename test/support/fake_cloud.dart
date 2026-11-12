import 'package:bayar/sync/cloud_backend.dart';
import 'package:bayar/sync/remote_store.dart';

import 'in_memory_remote.dart';

/// A pretend cloud with a pretend account system, for testing sign-in and the
/// sync controller. Data is held by [remote], which several phones can share.
class FakeCloud implements CloudBackend {
  FakeCloud({InMemoryRemote? remote, this.configured = true, this._signedIn = false})
    : remote = remote ?? InMemoryRemote();

  final InMemoryRemote remote;
  final bool configured;

  /// email -> password
  final Map<String, String> accounts = {'me@example.com': 'secret1'};

  /// If true, new accounts must confirm their email before they are signed in.
  bool requireConfirmation = false;

  bool _signedIn;
  String? _email;
  int signInCalls = 0;

  @override
  bool get isConfigured => configured;

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get email => _signedIn ? _email : null;

  @override
  Future<void> signIn(String email, String password) async {
    signInCalls++;
    if (accounts[email.trim()] != password) throw Exception('Invalid login credentials');
    _signedIn = true;
    _email = email.trim();
  }

  @override
  Future<bool> signUp(String email, String password) async {
    if (accounts.containsKey(email.trim())) throw Exception('User already registered');
    if (password.length < 6) throw Exception('Password should be at least 6 characters');
    accounts[email.trim()] = password;
    if (requireConfirmation) return false;
    _signedIn = true;
    _email = email.trim();
    return true;
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
  }

  @override
  Future<List<RemoteRow>> pullChanges(String table, {DateTime? since}) => remote.pullChanges(table, since: since);

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) => remote.push(table, rows);
}
