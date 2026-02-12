import 'package:get_it/get_it.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:tinode/src/services/logger.dart';
import 'package:tinode/src/stores/message-store.dart';
import 'package:tinode/src/stores/voice-listened-store.dart';

class DatabaseManager {
  static const int kSchemaVersion = 2;
  static final _instance = DatabaseManager._internal();

  static DatabaseManager get instance => _instance;

  late MessageStore message;
  late VoiceListenedStore voiceListened;

  late LoggerService _loggerService;

  Database? _database;

  var _isInitialized = false;

  Database get database => _database!;

  DatabaseManager._internal() {
    _loggerService = GetIt.I.get<LoggerService>();

    message = GetIt.I.registerSingleton<MessageStore>(
      MessageStore(),
    );

    voiceListened = GetIt.I.registerSingleton<VoiceListenedStore>(
      VoiceListenedStore(),
    );

    _initDatabase();
  }

  factory DatabaseManager() => _instance;

  void _initDatabase() async {
    if (_isInitialized) return;
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'tinode.sqlite');

    _database = await openDatabase(
      path,
      version: kSchemaVersion,
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        _log('schema has changed from $oldVersion to $newVersion');
        await _dropTables(db);
        await _createTables(db, newVersion);
      },
    );

    _isInitialized = true;

    _log('Initializing finish.');
  }

  Future<void> _createTables(Database db, int version) async {
    _log('Creating SQLite db tables.');
    await message.createTable(db);
    await voiceListened.createTable(db);
  }

  Future<void> _dropTables(Database db) async {
    _log('Dropping local store (SQLite db).');
    await message.destoryTable(db);
    await voiceListened.destoryTable(db);
  }

  void _log(String msg) {
    _loggerService.log('Database - $msg');
  }

  Future<void> reset() async {
    await message.clearTable();
    await voiceListened.clearTable();
  }
}
