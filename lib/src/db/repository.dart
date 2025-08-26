import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/services/logger.dart';

enum RepositoryStatus implements Comparable<RepositoryStatus> {
  undefined(0),
  draft(10),
  queued(20),
  sending(30),
  failed(40),
  synced(50),
  deletedHard(60),
  deletedSoft(70),
  deletedSynced(80);

  final int value;

  const RepositoryStatus(this.value);

  static RepositoryStatus fromValue(int value) {
    return RepositoryStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => RepositoryStatus.undefined,
    );
  }

  @override
  int compareTo(RepositoryStatus other) {
    return value.compareTo(other.value);
  }
}

class Repository {
  late LoggerService loggerService;

  Repository() {
    loggerService = GetIt.I.get<LoggerService>();
  }

  void logInfo(String message) {
    loggerService.log(message, prefix: LogPrefix.db);
  }

  void logWarn(String message) {
    loggerService.warn(message, prefix: LogPrefix.db);
  }

  void logError(String message) {
    loggerService.error(message, prefix: LogPrefix.db);
  }

  Future<T> transaction<T>(
    DatabaseExecutor databaseExecutor,
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) {
    if (databaseExecutor is Database) {
      return databaseExecutor.transaction(action, exclusive: exclusive);
    }
    final txn = databaseExecutor as Transaction;
    return action(txn);
  }
}
