import 'dart:async';
import 'package:rxdart/rxdart.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tinode/src/sql_store.dart';
import 'package:tinode/src/subscriber_db.dart';
import 'package:tinode/src/topic_db.dart';
import 'account_db.dart';
import 'log.dart';
import 'message_db.dart';
import 'user_db.dart';

enum BaseDbStatus {
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

  const BaseDbStatus(this.value);

  static BaseDbStatus fromValue(int value) {
    return BaseDbStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => BaseDbStatus.undefined,
    );
  }

  // 比较当前枚举值是否小于另一个
  bool isLessThan(BaseDbStatus other) {
    return value < other.value;
  }

  // 比较当前枚举值是否大于另一个
  bool isGreaterThan(BaseDbStatus other) {
    return value > other.value;
  }
}

class BaseDb {
  // 当前数据库模式版本，模式更改时递增
  static const int kSchemaVersion = 111;

  // 对象状态，值以10递增以便添加新状态

  // 元状态：对象应在UI中可见
  static const BaseDbStatus kStatusVisible = BaseDbStatus.synced;

  static const String kBundleId = 'co.tinode.tinodios.db';
  static const String kAppGroupId = 'group.$kBundleId';

  // 单例实例
  static BaseDb? _instance;
  static final _accessQueue = Completer.sync().future;

  static final Log log = Log(subsystem: 'co.tinode.tinodedb');

  Database? _db;
  String _pathToDatabase;

  SqlStore? sqlStore;
  TopicDb? topicDb;
  AccountDb? accountDb;
  SubscriberDb? subscriberDb;
  UserDb? userDb;
  MessageDb? messageDb;

  StoredAccount? account;

  bool get isCredValidationRequired => !(account?.credMethods?.isEmpty ?? true);

  bool get isReady => account != null && !isCredValidationRequired;

  Database? get DB => _db;

  final onDatabaseReady = PublishSubject<void>();

  // 私有构造函数确保单例
  BaseDb._private() : _pathToDatabase = '' {
    // 初始化路径将在init中完成
  }

  // 获取数据库路径
  Future<String> _getDatabasePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return join(directory.path, 'database.sqlite');
  }

  // 初始化数据库
  Future<void> _initDb() async {
    BaseDb.log.info('Initializing local store.');

    _pathToDatabase = await _getDatabasePath();
    _db = await openDatabase(
      _pathToDatabase,
      version: kSchemaVersion,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        BaseDb.log.info(
          'BaseDb - schema has changed from $oldVersion to $newVersion',
        );

        // 在升级前保留活动账户
        final account = await accountDb?.getActiveAccount();
        final deviceToken = await accountDb?.getDeviceToken();

        // 删除旧表
        await _dropTables(db);
        // 创建新表
        await _createTables(db);

        // 恢复账户信息
        if (account != null) {
          await accountDb?.addOrActivateAccount(
            uid: account.uid,
            credMethods: account.credMethods,
          );
          await accountDb?.saveDeviceToken(deviceToken);
        }
      },
    );

    // 初始化数据库操作类
    accountDb ??= AccountDb(_db!);
    userDb ??= UserDb(_db!, this);
    topicDb ??= TopicDb(_db!, this);
    subscriberDb ??= SubscriberDb(_db!, this);
    messageDb ??= MessageDb(_db!, this);

    sqlStore = SqlStore(this);

    // 启用外键约束
    await _db!.execute('PRAGMA foreign_keys = ON');

    // 获取活动账户
    account = await accountDb?.getActiveAccount();

    BaseDb.log.info('Initializing finish.');
    onDatabaseReady.add(null);
  }

  // 创建所有表
  Future<void> _createTables(Database db) async {
    BaseDb.log.info('Creating SQLite db tables.');

    accountDb = AccountDb(db);
    userDb = UserDb(db, this);
    topicDb = TopicDb(db, this);
    subscriberDb = SubscriberDb(db, this);
    messageDb = MessageDb(db, this);

    await accountDb!.createTable();
    await userDb!.createTable();
    await topicDb!.createTable();
    await subscriberDb!.createTable();
    await messageDb!.createTable();

    BaseDb.log.info('Creating SQLite db tables finish.');
  }

  // 删除所有表
  Future<void> _dropTables(Database db) async {
    BaseDb.log.info('Dropping local store (SQLite db).');
    await messageDb?.destroyTable();
    await subscriberDb?.destroyTable();
    await topicDb?.destroyTable();
    await userDb?.destroyTable();
    await accountDb?.destroyTable();
  }

  // 清除序列
  Future<void> _clearSequences() async {
    await _db?.execute('DELETE FROM sqlite_sequence');
  }

  // 清除数据库
  Future<void> clearDb() async {
    BaseDb.log.info('Clearing local store (SQLite db).');
    await _db?.transaction((txn) async {
      await messageDb?.truncateTable(txn);
      await subscriberDb?.truncateTable(txn);
      await topicDb?.truncateTable(txn);
      await userDb?.truncateTable(txn);
      await accountDb?.truncateTable(txn);
      await _clearSequences();
    });
  }

  // 单例访问
  static BaseDb get sharedInstance {
    if (_instance == null) {
      _instance = BaseDb._private();
      _instance!._initDb();
    }
    return _instance!;
  }

  // 检查是否为当前用户
  bool isMe(String? uid) {
    final acctUid = this.uid;
    return uid != null && acctUid != null && uid == acctUid;
  }

  String? get uid => account?.uid;

  // 设置用户ID
  Future<void> setUid({String? uid, List<String>? credMethods}) async {
    if (uid == null) {
      account = null;
      return;
    }

    try {
      if (account != null) {
        await accountDb?.deactivateAll();
      }
      account = await accountDb?.addOrActivateAccount(
        uid: uid,
        credMethods: credMethods,
      );
    } catch (e) {
      BaseDb.log.error('BaseDb - setUid failed: $e');
      account = null;
    }
  }

  // 登出
  Future<void> logout() async {
    BaseDb.log.info('logout');
    await _accessQueue;
    await setUid(uid: null, credMethods: null);
    await clearDb();
    // _instance = null;
  }

  // 删除用户
  Future<bool> deleteUid(String uid) async {
    StoredAccount? acc;
    if (this.uid == uid) {
      acc = account;
      account = null;
    } else {
      acc = await accountDb?.getByUid(uid);
    }

    if (acc == null) {
      BaseDb.log.error('Could not find account for uid [$uid]');
      return false;
    }

    const savepointName = 'BaseDb.deleteUid';
    try {
      await _db?.transaction((txn) async {
        // 创建保存点
        await txn.execute('SAVEPOINT $savepointName');

        final topicsDeleted = await topicDb?.deleteAll(acc!.id) ?? true;
        if (!topicsDeleted) {
          BaseDb.log.error(
            'Failed to clear topics/messages/subscribers for account id [${acc!.id}]',
          );
        }

        final usersDeleted = await userDb?.deleteForAccount(acc!.id) ?? true;
        if (!usersDeleted) {
          BaseDb.log.error('Failed to clear users for account id [${acc!.id}]');
        }

        final accountDeleted = await accountDb?.delete(txn, acc!.id) ?? true;
        if (!accountDeleted) {
          BaseDb.log.error('Failed to delete account for id [${acc!.id}]');
        }
      });
      return true;
    } catch (e) {
      // 释放保存点
      await _db?.execute('RELEASE $savepointName');
      BaseDb.log.error(
        'BaseDb - deleteUid operation failed: uid = $uid, error = $e',
      );
      return false;
    }
  }

  // 更新计数器
  static Future<bool> updateCounter({
    required Database db,
    required String table,
    required String idColumn,
    required int id,
    required String column,
    required int value,
  }) async {
    try {
      final result = await db.rawUpdate(
        '''
        UPDATE $table 
        SET $column = ? 
        WHERE $idColumn = ? AND $column < ?
      ''',
        [value, id, value],
      );
      return result > 0;
    } catch (e) {
      BaseDb.log.error('BaseDb - updateCounter failed: $e');
      return false;
    }
  }
}
