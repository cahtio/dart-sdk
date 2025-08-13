import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/models/user.dart';

import 'dart:convert';
import 'base_db.dart';
import 'account_db.dart';

class StoredUser {
  final int? id;

  StoredUser({required this.id});
}

class UserDb {
  static const String kTableName = 'users';

  // 用于表示"无用户"的假UID
  static const String kNoUser = 'NONE';

  final String columnId = 'id';
  final String columnAccountId = 'account_id';
  final String columnUid = 'uid';
  final String columnUpdated = 'updated';
  final String columnPub = 'pub';

  final Database db;
  final BaseDb baseDb;

  UserDb(this.db, this.baseDb);

  // 销毁表
  Future<void> destroyTable() async {
    await db.execute('DROP INDEX IF EXISTS idx_account_uid ON $kTableName');
    await db.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表
  Future<void> createTable() async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnAccountId INTEGER,
        $columnUid TEXT,
        $columnUpdated DATETIME,
        $columnPub TEXT,
        FOREIGN KEY (account_id) REFERENCES ${AccountDb.kTableName}(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_account_uid ON $kTableName (account_id, uid)
    ''');
  }

  // 清空表中所有记录
  Future<void> truncateTable(DatabaseExecutor db) async {
    await db.delete(kTableName);
  }

  // 插入用户
  Future<int> insertUser(UserProto? user) async {
    if (user == null) return 0;

    final id = await insert(
      uid: user.uid,
      updated: user.updated,
      serializedPub: user.serializePub(),
    );

    if (id > 0) {
      user.payload = StoredUser(id: id);
    }
    return id;
  }

  // 插入订阅用户
  Future<int> insertSubscription(TopicSubscription? sub) async {
    if (sub == null) return -1;

    return await insert(
      uid: sub.user ?? sub.topic,
      updated: sub.updated,
      serializedPub: sub.serializePub(),
    );
  }

  // 实际插入操作
  Future<int> insert({
    required String? uid,
    required DateTime? updated,
    required String? serializedPub,
  }) async {
    var processedUid = (uid ?? '').isEmpty ? kNoUser : uid!;

    try {
      final accountId = baseDb.account?.id;

      return await db.insert(kTableName, {
        columnAccountId: accountId,
        columnUid: processedUid,
        columnUpdated:
            updated?.toIso8601String() ?? DateTime.now().toIso8601String(),
        columnPub: serializedPub,
      });
    } catch (e) {
      BaseDb.log.error('UserDb - SQL error: uid = $processedUid, error = $e');
      return -1;
    }
  }

  // 更新用户
  Future<bool> updateUser(User? user) async {
    if (user == null || user.payload == null || user.payload is! StoredUser) {
      return false;
    }

    final storedUser = user.payload as StoredUser;
    final userId = storedUser.id;

    if (userId == null || userId <= 0) return false;

    return await update(
      userId: userId,
      updated: user.updated,
      serializedPub: user.serializePub(),
    );
  }

  // 更新订阅用户
  Future<bool> updateSubscription(TopicSubscription? sub) async {
    if (sub == null ||
        sub.payload == null ||
        sub.payload is! StoredSubscription) {
      return false;
    }

    final storedSub = sub.payload as StoredSubscription;
    final userId = storedSub.userId;

    if (userId == null) return false;

    return await update(
      userId: userId,
      updated: sub.updated,
      serializedPub: sub.serializePub(),
    );
  }

  // 实际更新操作
  Future<bool> update({
    required int userId,
    DateTime? updated,
    String? serializedPub,
  }) async {
    var updates = <String, dynamic>{};

    if (updated != null) {
      updates[columnUpdated] = updated.toIso8601String();
    }
    if (serializedPub != null) {
      updates[columnPub] = serializedPub;
    }

    if (updates.isEmpty) return false;

    try {
      final rowsAffected = await db.update(
        kTableName,
        updates,
        where: '$columnId = ?',
        whereArgs: [userId],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error(
        'UserDb - update operation failed: userId = $userId, error = $e',
      );
      return false;
    }
  }

  // 根据ID删除行
  Future<bool> deleteRow(int id) async {
    try {
      final rowsAffected = await db.delete(
        kTableName,
        where: '$columnId = ?',
        whereArgs: [id],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error(
        'UserDb - deleteRow operation failed: userId = $id, error = $e',
      );
      return false;
    }
  }

  // 根据账户ID删除用户
  Future<bool> deleteForAccount(int accountId) async {
    try {
      final rowsAffected = await db.delete(
        kTableName,
        where: '$columnAccountId = ?',
        whereArgs: [accountId],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error(
        'UserDb - delete(forAccount) operation failed: accountId = $accountId, error = $e',
      );
      return false;
    }
  }

  // 根据UID获取用户ID
  Future<int> getId(String? uid) async {
    final accountId = baseDb.account?.id;
    if (accountId == null) return -1;

    final processedUid = uid ?? kNoUser;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        kTableName,
        columns: ['id'],
        where: '$columnUid = ? AND $columnAccountId = ?',
        whereArgs: [processedUid, accountId],
      );

      if (maps.isNotEmpty) {
        return maps.first[columnId] as int;
      }
      return -1;
    } catch (e) {
      BaseDb.log.error(
        'UserDb - getIdForUid error: uid = $processedUid, error = $e',
      );
      return -1;
    }
  }

  // 将数据库行转换为UserProto对象
  User? _rowToUser(Map<String, dynamic> row) {
    final id = row[columnId] as int;
    final updatedStr = row[columnUpdated] as String?;
    final pub = row[columnPub] as String?;
    final uid = row[columnUid] as String?;

    DateTime? updated;
    if (updatedStr != null) {
      updated = DateTime.parse(updatedStr);
    }

    final user = User(uid: uid, updated: updated, pub: pub);

    user.payload = StoredUser(id: id);

    return user;
  }

  // 读取单个用户
  Future<User?> readOne(String? uid) async {
    final accountId = baseDb.account?.id;
    if (accountId == null) return null;

    final processedUid = uid ?? kNoUser;

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        kTableName,
        where: '$columnUid = ? AND $columnAccountId = ?',
        whereArgs: [processedUid, accountId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return _rowToUser(maps.first);
      }
      return null;
    } catch (e) {
      BaseDb.log.error(
        'UserDb - readOne error: $columnUid = $processedUid, error = $e',
      );
      return null;
    }
  }

  // 通用读取方法
  Future<List<UserProto>?> _read({
    String? excludeUid,
    List<String> includeUids = const [],
  }) async {
    if (excludeUid == null && includeUids.isEmpty) return null;

    final accountId = baseDb.account?.id;
    if (accountId == null) return null;

    String whereClause;
    var whereArgs = <dynamic>[accountId];

    if (excludeUid != null) {
      whereClause = '$columnAccountId = ? AND $columnUid != ?';
      whereArgs.add(excludeUid);
    } else {
      whereClause =
          '$columnAccountId = ? AND uid IN (${List.filled(includeUids.length, '?').join(',')})';
      whereArgs.addAll(includeUids);
    }

    try {
      final List<Map<String, dynamic>> maps = await db.query(
        kTableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: '$columnUpdated DESC, $columnId DESC',
      );

      return maps.map((map) => _rowToUser(map)).whereType<UserProto>().toList();
    } catch (e) {
      BaseDb.log.error('UserDb - read operation failed: error = $e');
      return null;
    }
  }

  // 读取指定UID列表的用户
  Future<List<UserProto>?> readUsers(List<String> uids) async {
    return _read(includeUids: uids);
  }

  // 读取除指定用户外的所有用户
  Future<List<UserProto>?> readAllExcept(String? uid) async {
    return _read(excludeUid: uid);
  }
}

// 以下是所需的辅助类和协议的简化实现
class UserProto {
  final String? uid;
  final DateTime? updated;
  dynamic payload;

  UserProto({this.uid, this.updated, this.payload});

  String? serializePub() {
    // 实现序列化逻辑
    return json.encode({/* 公共数据 */});
  }
}

class StoredSubscription {
  final int? userId;

  StoredSubscription({this.userId});
}

class DefaultUser {
  static UserProto? createFromPublicData({
    String? uid,
    DateTime? updated,
    String? data,
  }) {
    // 实现创建逻辑
    return UserProto(uid: uid, updated: updated);
  }
}
