import 'package:bayar/core/dates.dart';
import 'package:bayar/data/budget_repository.dart';
import 'package:bayar/data/db.dart';
import 'package:bayar/data/obligation_repository.dart';
import 'package:bayar/data/payment_repository.dart';
import 'package:bayar/data/settings_repository.dart';
import 'package:bayar/domain/obligation.dart';
import 'package:bayar/sync/remote_store.dart';
import 'package:bayar/sync/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A pretend phone: its own database, its own clock, and a sync engine pointing
/// at a shared pretend cloud.
class Phone {
  Phone._(this.name);

  final String name;
  late final AppDatabase appDb;
  late final ObligationRepository bills;
  late final PaymentRepository payments;
  late final SettingsRepository settings;
  late final BudgetRepository budget;
  late final SyncEngine engine;

  /// This phone's clock. Tests move it to decide who edited last.
  DateTime now = DateTime.utc(2026, 11, 12, 9);

  static Future<Phone> create(String name, RemoteStore remote, {bool firstLaunch = true}) async {
    sqfliteFfiInit();
    final p = Phone._(name);
    p.appDb = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    DateTime clock() => p.now;
    p.bills = ObligationRepository(p.appDb.db, clock: clock);
    p.payments = PaymentRepository(p.appDb.db, clock: clock);
    p.settings = SettingsRepository(p.appDb.db, clock: clock);
    p.budget = BudgetRepository(p.appDb.db, p.settings, clock: clock);
    p.engine = SyncEngine(db: p.appDb.db, remote: remote, clock: clock);
    // What the app does on its very first launch.
    if (firstLaunch) await p.budget.createDefaultEnvelopesOnce();
    return p;
  }

  void at(int day, [int hour = 9]) => now = DateTime.utc(2026, 11, day, hour);

  Future<SyncResult> sync() => engine.sync();

  Future<Obligation> addBill(String name, {int sen = 10000, DateTime? start}) =>
      bills.create(name: name, amountSen: sen, frequency: Frequency.monthly, startDate: start ?? dateOf(2026, 11, 17));

  Future<int?> amountOf(String billName) async {
    final all = await bills.all();
    final match = all.where((b) => b.name == billName);
    return match.isEmpty ? null : match.first.amountSen;
  }

  Future<List<String>> billNames() async => (await bills.all()).map((b) => b.name).toList();

  Future<int> activeRows(String table) async =>
      (await appDb.db.query(table, where: table == 'settings' ? null : 'deleted_at IS NULL')).length;

  Future<void> close() => appDb.close();
}
