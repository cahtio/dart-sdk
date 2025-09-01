import 'dart:ffi';

import 'package:get_it/get_it.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/db/account_repository.dart';
import 'package:tinode/src/db/message_repository.dart';
import 'package:tinode/src/db/repository.dart';
import 'package:tinode/src/db/subscriber_repository.dart';
import 'package:tinode/src/db/topic_repository.dart';
import 'package:tinode/src/db/user_repository.dart';
import 'package:tinode/src/models/message_stored.dart';
import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/models/user.dart';

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
    await userRepository.createTable(db);
    await topicRepository.createTable(db);
    await subscriberRepository.createTable(db);
    await messageRepository.createTable(db);
  }

  Future<void> _dropTables(Database db) async {
    _loggerService.log(
      'Dropping local store (SQLite db).',
      prefix: LogPrefix.db,
    );
    await messageRepository.destroyTable(db);
    await subscriberRepository.destroyTable(db);
    await topicRepository.destroyTable(db);
    await userRepository.destroyTable(db);
    await accountRepository.destroyTable(db);
  }

  bool isMe(String? uid) {
    final acctUid = account?.uid;
    return uid != null && acctUid != null && uid == acctUid;
  }

  Future<void> setUid(String? uid) async {
    if (uid == null) {
      account = null;
      return;
    }
    final db = await database;
    if (account != null) {
      await accountRepository.deactivateAll(db);
    }
    account = await accountRepository.addOrActivateAccount(db, uid);
  }

  Future<List<Topic>?> topicGetAll() async {
    _logInfo('topicGetAll');
    final db = await database;
    final rows = await topicRepository.query(db);
    if (rows == null) {
      _logError('topicGetAll rows is null');
      return null;
    }
    final results = List<Topic>.empty(growable: true);
    for (final r in rows) {
      final t = topicRepository.readOneFromRow(r);
      if (t != null) {
        results.add(t);
      }
    }
    _logInfo('topicGetAll results length: ${results.length}');
    return results;
  }

  Future<List<MessageStored>?> getLatestMessagePreviews() async {
    _logInfo('getLatestMessagePreviews');
    final db = await database;
    return await messageRepository.queryLatest(db);
  }

  Future<int> topicAdd(Topic topic) async {
    _logInfo('topicAdd name: ${topic.name}');
    if (topic.payload is TopicStored) {
      final ts = topic.payload as TopicStored;
      _logInfo('topicAdd did saved id: ${ts.id}');
      return ts.id ?? 0;
    }
    final db = await database;
    return topicRepository.insert(db, topic);
  }

  Future<bool> subDelete(Topic topic, TopicSubscription sub) async {
    _logInfo('subDelete name: ${topic.name}');
    if (sub.payload != null &&
        sub.payload!.id != null &&
        sub.payload!.id! > 0) {
      final db = await database;
      return subscriberRepository.delete(db, sub.payload!.id!);
    } else {
      return false;
    }
  }

  Future<List<TopicSubscription>?> getSubscriptions(Topic topic) async {
    _logInfo('getSubscriptions');
    if (topic.payload is TopicStored) {
      final ts = topic.payload as TopicStored;
      if (ts.id == null) return null;
      final db = await database;
      return subscriberRepository.readAll(db, ts.id!);
    } else {
      return null;
    }
  }

  Future<int> subAdd(Topic topic, TopicSubscription sub) async {
    _logInfo('subAdd');
    if (topic.payload is TopicStored) {
      final ts = topic.payload as TopicStored;
      if (ts.id == null) return 0;
      final db = await database;
      return subscriberRepository.insert(
        db,
        ts.id!,
        RepositoryStatus.synced,
        sub,
      );
    } else {
      return 0;
    }
  }

  Future<bool> subUpdate(Topic topic, TopicSubscription sub) async {
    _logInfo('subUpdate');
    if (sub.payload?.id == null || sub.payload!.id! > 0) {
      _logError('subUpdate sub payload id is null or zero');
      return false;
    }
    final db = await database;
    return subscriberRepository.update(db, sub);
  }

  Future<bool> topicDelete(Topic topic, bool hard) async {
    _logInfo('topicDelete');
    if (topic.payload is! TopicStored ||
        (topic.payload as TopicStored).id == null) {
      _logError('topicDelete topic payload error');
      return false;
    }
    ;
    final topicId = (topic.payload as TopicStored).id!;
    final db = await database;
    if (hard) {
      await db.transaction((txn) async {
        await messageRepository.deleteAll(txn, topicId);
        await subscriberRepository.deleteForTopic(txn, topicId);
        await topicRepository.delete(txn, topicId);
      });
    } else {
      await topicRepository.markDeleted(db, topicId);
    }
    return true;
  }

  Future<bool> updateUser(String uid, User user) async {
    final db = await database;
    return userRepository.updateUser(db, user);
  }

  void _logInfo(String msg) {
    _loggerService.log(msg, prefix: LogPrefix.db);
  }

  void _logError(String msg) {
    _loggerService.error(msg, prefix: LogPrefix.db);
  }
}
