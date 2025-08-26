import 'package:sqflite/sqflite.dart';

import 'package:tinode/src/db/account_repository.dart';
import 'package:tinode/src/db/repository.dart';
import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/models/user.dart';
import 'package:tinode/src/services/database_manager.dart';

class UserStored {
  final int? id;

  UserStored(this.id);
}

class UserRepository extends Repository {
  static const String kTableName = 'users';

  // 用于表示"无用户"的假UID
  static const String kNoUser = 'NONE';

  static const String kColumnId = 'id';
  static const String kColumnAccountId = 'account_id';
  static const String kColumnUid = 'uid';
  static const String kColumnUpdated = 'updated';
  static const String kColumnPub = 'pub';

  UserRepository();

  // 销毁表
  Future<void> destroyTable(DatabaseExecutor dbe) async {
    await dbe.execute('DROP INDEX IF EXISTS idx_account_uid ON $kTableName');
    await dbe.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表
  Future<void> createTable(DatabaseExecutor dbe) async {
    await dbe.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $kColumnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kColumnAccountId INTEGER,
        $kColumnUid TEXT,
        $kColumnUpdated DATETIME,
        $kColumnPub TEXT,
        FOREIGN KEY ($kColumnAccountId) REFERENCES ${AccountRepository.kTableName}(${AccountRepository.kColumnId})
      )
    ''');
    await dbe.execute('''
      CREATE INDEX IF NOT EXISTS idx_account_uid ON $kTableName (account_id, uid)
    ''');
  }

  // 清空表中所有记录
  Future<void> truncateTable(DatabaseExecutor db) async {
    await db.delete(kTableName);
  }

  // 插入用户
  Future<int> insertUser(DatabaseExecutor dbe, User? user) async {
    if (user == null) return 0;

    final id = await insert(dbe, user.uid, user.updated, user.serializePub());

    if (id > 0) {
      user.payload = UserStored(id);
    }
    return id;
  }

  // 插入订阅用户
  Future<int> insertSubscription(
    DatabaseExecutor dbe,
    TopicSubscription? sub,
  ) async {
    if (sub == null) return -1;

    return await insert(
      dbe,
      sub.user ?? sub.topic,
      sub.updated,
      sub.serializePub(),
    );
  }

  // 实际插入操作
  Future<int> insert(
    DatabaseExecutor dbe,
    String? uid,
    DateTime? updated,
    String? serializedPub,
  ) async {
    var processedUid = (uid ?? '').isEmpty ? kNoUser : uid!;

    try {
      final accountId = DatabaseManager().account?.id;

      return await dbe.insert(kTableName, {
        kColumnAccountId: accountId,
        kColumnUid: processedUid,
        kColumnUpdated:
            updated?.toIso8601String() ?? DateTime.now().toIso8601String(),
        kColumnPub: serializedPub,
      });
    } catch (e) {
      logError('UserDb - SQL error: uid = $processedUid, error = $e');
      return -1;
    }
  }

  // 更新用户
  Future<bool> updateUser(DatabaseExecutor dbe, User? user) async {
    if (user == null || user.payload == null || user.payload is! UserStored) {
      return false;
    }

    final storedUser = user.payload as UserStored;
    final userId = storedUser.id;

    if (userId == null || userId <= 0) return false;

    return await update(
      dbe,
      userId,
      updated: user.updated,
      serializedPub: user.serializePub(),
    );
  }

  // 更新订阅用户
  Future<bool> updateSubscription(
    DatabaseExecutor dbe,
    TopicSubscription? sub,
  ) async {
    if (sub == null || sub.payload == null) {
      return false;
    }

    final storedSub = sub.payload;
    final userId = storedSub!.userId;

    if (userId == null) return false;

    return await update(
      dbe,
      userId,
      updated: sub.updated,
      serializedPub: sub.serializePub(),
    );
  }

  // 实际更新操作
  Future<bool> update(
    DatabaseExecutor dbe,
    int userId, {
    DateTime? updated,
    String? serializedPub,
  }) async {
    var updates = <String, dynamic>{};

    if (updated != null) {
      updates[kColumnUpdated] = updated.toIso8601String();
    }
    if (serializedPub != null) {
      updates[kColumnPub] = serializedPub;
    }

    if (updates.isEmpty) return false;

    try {
      final rowsAffected = await dbe.update(
        kTableName,
        updates,
        where: '$kColumnId = ?',
        whereArgs: [userId],
      );
      return rowsAffected > 0;
    } catch (e) {
      logError(
        'UserDb - update operation failed: userId = $userId, error = $e',
      );
      return false;
    }
  }

  // 根据ID删除行
  Future<bool> deleteRow(DatabaseExecutor dbe, int id) async {
    try {
      final rowsAffected = await dbe.delete(
        kTableName,
        where: '$kColumnId = ?',
        whereArgs: [id],
      );
      return rowsAffected > 0;
    } catch (e) {
      logError('UserDb - deleteRow operation failed: userId = $id, error = $e');
      return false;
    }
  }

  // 根据账户ID删除用户
  Future<bool> deleteForAccount(DatabaseExecutor dbe, int accountId) async {
    try {
      final rowsAffected = await dbe.delete(
        kTableName,
        where: '$kColumnAccountId = ?',
        whereArgs: [accountId],
      );
      return rowsAffected > 0;
    } catch (e) {
      logError(
        'UserDb - delete(forAccount) operation failed: accountId = $accountId, error = $e',
      );
      return false;
    }
  }

  // 根据UID获取用户ID
  Future<int> getId(DatabaseExecutor dbe, String? uid) async {
    final accountId = DatabaseManager().account?.id;
    if (accountId == null) return -1;

    final processedUid = uid ?? kNoUser;

    try {
      final List<Map<String, dynamic>> maps = await dbe.query(
        kTableName,
        columns: ['id'],
        where: '$kColumnUid = ? AND $kColumnAccountId = ?',
        whereArgs: [processedUid, accountId],
      );

      if (maps.isNotEmpty) {
        return maps.first[kColumnId] as int;
      }
      return -1;
    } catch (e) {
      logError('UserDb - getIdForUid error: uid = $processedUid, error = $e');
      return -1;
    }
  }

  // 将数据库行转换为UserProto对象
  User? _rowToUser(Map<String, dynamic> row) {
    final id = row[kColumnId] as int;
    final updatedStr = row[kColumnUpdated] as String?;
    final pub = row[kColumnPub] as String?;
    final uid = row[kColumnUid] as String?;

    DateTime? updated;
    if (updatedStr != null) {
      updated = DateTime.parse(updatedStr);
    }

    final user = User(uid: uid, updated: updated, pub: pub);

    user.payload = UserStored(id);

    return user;
  }

  // 读取单个用户
  Future<User?> readOne(DatabaseExecutor dbe, String? uid) async {
    final accountId = DatabaseManager.instance.account?.id;
    if (accountId == null) return null;

    final processedUid = uid ?? kNoUser;

    try {
      final List<Map<String, dynamic>> maps = await dbe.query(
        kTableName,
        where: '$kColumnUid = ? AND $kColumnAccountId = ?',
        whereArgs: [processedUid, accountId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return _rowToUser(maps.first);
      }
      return null;
    } catch (e) {
      logError(
        'UserDb - readOne error: $kColumnUid = $processedUid, error = $e',
      );
      return null;
    }
  }

  // 通用读取方法
  Future<List<User>?> _read(
    DatabaseExecutor dbe, {
    String? excludeUid,
    List<String> includeUids = const [],
  }) async {
    if (excludeUid == null && includeUids.isEmpty) return null;

    final accountId = DatabaseManager.instance.account?.id;
    if (accountId == null) return null;

    String whereClause;
    var whereArgs = <dynamic>[accountId];

    if (excludeUid != null) {
      whereClause = '$kColumnAccountId = ? AND $kColumnUid != ?';
      whereArgs.add(excludeUid);
    } else {
      whereClause =
          '$kColumnAccountId = ? AND uid IN (${List.filled(includeUids.length, '?').join(',')})';
      whereArgs.addAll(includeUids);
    }

    try {
      final List<Map<String, dynamic>> maps = await dbe.query(
        kTableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: '$kColumnUpdated DESC, $kColumnId DESC',
      );

      return maps.map((map) => _rowToUser(map)).whereType<User>().toList();
    } catch (e) {
      logError('UserDb - read operation failed: error = $e');
      return null;
    }
  }

  // 读取指定UID列表的用户
  Future<List<User>?> readUsers(DatabaseExecutor dbe, List<String> uids) async {
    return _read(dbe, includeUids: uids);
  }

  // 读取除指定用户外的所有用户
  Future<List<User>?> readAllExcept(DatabaseExecutor dbe, String? uid) async {
    return _read(dbe, excludeUid: uid);
  }
}
