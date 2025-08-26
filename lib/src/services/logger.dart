import 'package:tinode/src/services/configuration.dart';
import 'package:get_it/get_it.dart';

enum LogPrefix { sdk, db }

enum LogType { info, warn, error }

class LoggerService {
  late ConfigService _configService;

  LoggerService() {
    _configService = GetIt.I.get<ConfigService>();
  }

  void error(String message, {LogPrefix prefix = LogPrefix.sdk}) {
    _log(prefix, LogType.error, message);
  }

  void log(String message, {LogPrefix prefix = LogPrefix.sdk}) {
    _log(prefix, LogType.info, message);
  }

  void warn(String message, {LogPrefix prefix = LogPrefix.sdk}) {
    _log(prefix, LogType.warn, message);
  }

  _log(LogPrefix prefix, LogType type, String message) {
    if (_configService.loggerEnabled == null ||
        !_configService.loggerEnabled!) {
      return;
    }
    var msg = '';
    switch (prefix) {
      case LogPrefix.sdk:
        msg += '[TINODE.SDK] ';
        break;
      case LogPrefix.db:
        msg += '[TINODE.DB] ';
        break;
    }
    switch (type) {
      case LogType.info:
        msg += '[INFO] ';
        break;
      case LogType.warn:
        msg += '[WARN] ';
        break;
      case LogType.error:
        msg += '[ERROR] ';
        break;
    }
    print(msg + message);
  }
}
