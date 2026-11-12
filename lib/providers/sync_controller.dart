import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/obligation_repository.dart' show Clock, systemClock;
import '../sync/cloud_backend.dart';
import '../sync/sync_engine.dart';

enum SyncState {
  /// This build has no cloud address, so sync is not available.
  notConfigured,

  /// Not signed in.
  signedOut,

  /// Signed in and up to date (or waiting for the next change).
  idle,

  syncing,

  /// The last attempt failed. Local data is untouched and the next change retries.
  error,
}

/// Signs in, and keeps the phone in step with the cloud.
///
/// Edits anywhere in the app call [requestSync]. A burst of edits (tapping "+"
/// ten times) becomes ONE sync a couple of seconds after the last tap.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.cloud,
    required Database db,
    Clock clock = systemClock,
    this.onSynced,
    this.debounce = const Duration(seconds: 2),
  }) : _db = db,
       _engine = SyncEngine(db: db, remote: cloud, clock: clock);

  final CloudBackend cloud;
  final Database _db;
  final SyncEngine _engine;

  /// Called after a sync brought changes in from the cloud, so screens reload.
  final Future<void> Function()? onSynced;

  /// How long to wait after the last edit before syncing.
  final Duration debounce;

  Timer? _timer;
  bool _running = false;
  bool _again = false;

  /// True while we reload screens after a sync, so that reload does not trigger another sync.
  bool _applying = false;

  bool _error = false;
  String? _message;
  DateTime? _lastSynced;

  SyncState get state {
    if (!cloud.isConfigured) return SyncState.notConfigured;
    if (!cloud.isSignedIn) return SyncState.signedOut;
    if (_running) return SyncState.syncing;
    if (_error) return SyncState.error;
    return SyncState.idle;
  }

  String? get email => cloud.email;

  /// The last problem, in plain words (a failed sign-in or sync).
  String? get message => _message;

  DateTime? get lastSynced => _lastSynced;

  /// Start-up: remember when we last synced, and catch up if signed in.
  Future<void> init() async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: ['sync_last_success'], limit: 1);
    if (rows.isNotEmpty) _lastSynced = DateTime.tryParse(rows.first['value'] as String);
    notifyListeners();
    if (cloud.isConfigured && cloud.isSignedIn) requestSync(immediately: true);
  }

  /// Returns true if signed in.
  Future<bool> signIn(String email, String password) async {
    return _auth(() async {
      await cloud.signIn(email, password);
      return true;
    });
  }

  /// Returns true if signed in straight away. False with a [message] if the email must be confirmed first.
  Future<bool> signUp(String email, String password) async {
    final signedIn = await _auth(() => cloud.signUp(email, password));
    if (!signedIn && _message == null) {
      _message = 'Check your email to confirm the account, then sign in.';
      notifyListeners();
    }
    return signedIn;
  }

  Future<bool> _auth(Future<bool> Function() action) async {
    _message = null;
    notifyListeners();
    try {
      final signedIn = await action();
      if (signedIn) {
        _error = false;
        notifyListeners();
        requestSync(immediately: true);
      }
      return signedIn;
    } catch (e) {
      _message = _friendly(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _timer?.cancel();
    await cloud.signOut();
    _error = false;
    _message = null;
    notifyListeners();
  }

  /// Something changed: sync soon. Safe to call as often as you like.
  void requestSync({bool immediately = false}) {
    if (_applying || !cloud.isConfigured || !cloud.isSignedIn) return;
    _timer?.cancel();
    if (immediately) {
      unawaited(syncNow());
    } else {
      _timer = Timer(debounce, () => unawaited(syncNow()));
    }
  }

  /// Syncs now. If one is already running, runs once more right after it.
  Future<void> syncNow() async {
    if (!cloud.isConfigured || !cloud.isSignedIn) return;
    if (_running) {
      _again = true;
      return;
    }

    _running = true;
    notifyListeners();
    try {
      do {
        _again = false;
        final result = await _engine.sync();
        if (result.ok) {
          _error = false;
          _message = null;
          _lastSynced = DateTime.now();
          if (result.pulled > 0) await _reloadScreens();
        } else {
          _error = true;
          _message = 'Could not sync. Your data is safe on this phone; it will try again.';
        }
      } while (_again);
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _reloadScreens() async {
    _applying = true;
    try {
      await onSynced?.call();
    } finally {
      _applying = false;
    }
  }

  String _friendly(Object e) {
    final text = '$e'.toLowerCase();
    const messages = {
      'invalid login': 'Wrong email or password.',
      'invalid_credentials': 'Wrong email or password.',
      'already registered': 'That email already has an account. Try signing in.',
      'already exists': 'That email already has an account. Try signing in.',
      'at least 6': 'Use a password of at least 6 characters.',
      'socket': 'No connection. Try again when you are online.',
      'network': 'No connection. Try again when you are online.',
      'connection': 'No connection. Try again when you are online.',
      'not configured': 'Sync is not set up in this build.',
    };
    for (final entry in messages.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'Could not sign in. Please try again.';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
