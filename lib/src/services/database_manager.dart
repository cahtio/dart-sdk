import 'package:get_it/get_it.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/db/account_repository.dart';
import 'package:tinode/src/db/message_repository.dart';
import 'package:tinode/src/db/subscriber_repository.dart';
import 'package:tinode/src/db/topic_repository.dart';
import 'package:tinode/src/db/user_repository.dart';
import 'package:tinode/src/models/message_stored.dart';

import 'package:tinode/src/services/logger.dart';
import 'package:tinode/src/topic.dart';

class DatabaseManager {
  static const int kSchemaVersion = 1;
  static final _instance = DatabaseManager._internal();

  static DatabaseManager get instance => _instance;

  late AccountRepository accountRepository;
  late UserRepository userRepository;
  late TopicRepository topicRepository;
  late SubscriberRepository subscriberRepository;
  late MessageRepository messageRepository;

  late LoggerService _loggerService;

  Database? _database;

  Account? account;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  DatabaseManager._internal() {
    _loggerService = GetIt.I.get<LoggerService>();

    accountRepository = GetIt.I.registerSingleton<AccountRepository>(
      AccountRepository(),
    );
    userRepository = GetIt.I.registerSingleton<UserRepository>(
      UserRepository(),
    );
    topicRepository = GetIt.I.registerSingleton<TopicRepository>(
      TopicRepository(),
    );
    subscriberRepository = GetIt.I.registerSingleton<SubscriberRepository>(
      SubscriberRepository(),
    );
    messageRepository = GetIt.I.registerSingleton<MessageRepository>(
      MessageRepository(),
    );
  }

  factory DatabaseManager() {
    return _instance;
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, 'database.sqlite');

    final database = await openDatabase(
      path,
      version: kSchemaVersion,
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        _loggerService.log(
          'BaseDb - schema has changed from $oldVersion to $newVersion',
          prefix: LogPrefix.db,
        );
        // 在升级前保留活动账户
        final account = await accountRepository.getActiveAccount(db);
        final deviceToken = await accountRepository.getDeviceToken(db);

        // 删除旧表
        await _dropTables(db);
        // 创建新表
        await _createTables(db, newVersion);

        // 恢复账户信息
        if (account != null) {
          await accountRepository.addOrActivateAccount(
            db,
            account.uid,
            credMethods: account.credMethods,
          );
          await accountRepository.saveDeviceToken(db, deviceToken);
        }
      },
    );

    // 启用外键约束
    await database.execute('PRAGMA foreign_keys = ON');

    // 获取活动账户
    account = await accountRepository.getActiveAccount(database);

    _loggerService.log('Initializing finish.', prefix: LogPrefix.db);
    return database;
  }

  Future<void> _createTables(Database db, int version) async {
    _loggerService.log('Creating SQLite db tables.', prefix: LogPrefix.db);

    await accountRepository.createTable(db);
  }

  Future<void> _dropTables(Database db) async {
    _loggerService.log(
      'Dropping local store (SQLite db).',
      prefix: LogPrefix.db,
    );
    // await messageDb?.destroyTable();
    // await subscriberDb?.destroyTable();
    // await topicDb?.destroyTable();
    // await userDb?.destroyTable();
    await accountRepository.destroyTable(db);
  }

  bool isMe(String? uid) {
    final acctUid = account?.uid;
    return uid != null && acctUid != null && uid == acctUid;
  }

  Future<List<Topic>?> topicGetAll() async {
    final db = await database;
    final rows = await topicRepository.query(db);
    if (rows == null) return null;
    final results = List<Topic>.empty(growable: true);
    for (final r in rows) {
      final t = topicRepository.readOneFromRow(r);
      if (t != null) {
        results.add(t);
      }
    }
    return results;
  }

  Future<List<MessageStored>?> getLatestMessagePreviews() async {
    final db = await database;
    return await messageRepository.queryLatest(db);
  }

  Future<int> topicAdd(Topic topic) async {
    if (topic.payload is TopicStored) {
      final ts = topic.payload as TopicStored;
      return ts.id ?? 0;
    }
    final db = await database;
    return topicRepository.insert(db, topic);
  }

  // public func topicAdd(topic: TopicProto) -> Int64 {
  // if let st = topic.payload as? StoredTopic {
  // return st.id ?? 0
  // }
  // return self.dbh?.topicDb?.insert(topic: topic) ?? 0
  // }
  // public func getLatestMessagePreviews() -> [Message]? {
  // return BaseDb.sharedInstance.messageDb?.queryLatest()
  // }
}
