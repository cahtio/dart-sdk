import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/models/access-mode.dart';
import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/topic_db.dart';
import 'package:tinode/src/user_db.dart';

import 'base_db.dart';

class StoredSubscription {
  int? id;
  int? topicId;
  int? userId;
  BaseDbStatus? status;

  StoredSubscription({this.id, this.topicId, this.userId, this.status});
}

class SubscriberDbError implements Exception {
  final String message;

  SubscriberDbError(this.message);

  @override
  String toString() {
    return 'SubscriberDb Error: $message';
  }
}

class SubscriberDb {
  static const String kTableName = 'subscriptions';
  final Database _db;
  final BaseDb _baseDb;

  // 表字段定义（对应原SQLite.Expression）
  final String columnId = 'id';
  final String columnTopicId = 'topic_id';
  final String columnUserId = 'user_id';
  final String columnStatus = 'status';
  final String columnMode = 'mode';
  final String columnUpdated = 'updated';
  final String columnRead = 'read';
  final String columnRecv = 'recv';
  final String columnClear = 'clear';
  final String columnPriv = 'priv';
  final String columnLastSeen = 'last_seen';
  final String columnUserAgent = 'user_agent';
  final String columnSubscriptionClass = 'subscription_class';

  SubscriberDb(this._db, this._baseDb);

  // 删除表
  Future<void> destroyTable() async {
    await _db.execute('DROP INDEX IF EXISTS idx_${kTableName}_$columnTopicId');
    await _db.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表（包含外键关联用户表和主题表）
  Future<void> createTable() async {
    final userDb = _baseDb.userDb;
    final topicDb = _baseDb.topicDb;
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnTopicId INTEGER REFERENCES ${UserDb.kTableName}(${userDb!.columnId}),
        $columnUserId INTEGER REFERENCES ${TopicDb.kTableName}(${topicDb!.columnId}),
        $columnStatus INTEGER,
        $columnMode TEXT,
        $columnUpdated INTEGER, -- 存储时间戳（Dart DateTime转毫秒）
        $columnRead INTEGER,
        $columnRecv INTEGER,
        $columnClear INTEGER,
        $columnPriv TEXT,
        $columnLastSeen INTEGER, -- 时间戳
        $columnUserAgent TEXT,
        $columnSubscriptionClass TEXT NOT NULL
      )
    ''');
    // 创建索引
    await _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${kTableName}_$columnTopicId ON $kTableName($columnTopicId)',
    );
  }

  // 清空表数据
  Future<void> truncateTable(DatabaseExecutor db) async {
    await db.delete(kTableName);
  }

  // 插入订阅信息
  Future<int> insert({
    required int topicId,
    required BaseDbStatus status,
    required TopicSubscription sub,
  }) async {
    final savepointName = 'SubscriberDb.insert';
    try {
      await _db.execute('SAVEPOINT $savepointName');

      final userDb = _baseDb.userDb!;
      // 获取或插入用户ID
      var userId = await userDb.getId(sub.user);
      if (userId <= 0) {
        userId = await userDb.insertSubscription(sub);
      }
      if (userId <= 0) {
        throw SubscriberDbError('插入用户失败: $userId');
      }

      // 准备插入数据
      final values = {
        columnTopicId: topicId,
        columnUserId: userId,
        columnMode: sub.acs?.serialize(),
        columnUpdated:
            sub.updated?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        columnStatus: status.value,
        columnRead: sub.read,
        columnRecv: sub.recv,
        columnClear: sub.clear,
        columnPriv: sub.serializePriv(),
        columnLastSeen: sub.seen?.when?.millisecondsSinceEpoch,
        columnUserAgent: sub.seen?.ua,
        columnSubscriptionClass: sub.runtimeType.toString(),
      };

      // 执行插入并返回ID
      final rowId = await _db.insert(kTableName, values);
      // 关联存储信息到订阅对象
      final storedSub = StoredSubscription(
        id: rowId,
        topicId: topicId,
        userId: userId,
        status: status,
      );
      sub.payload = storedSub;

      await _db.execute('RELEASE SAVEPOINT $savepointName');
      return rowId;
    } catch (e) {
      await _db.execute('ROLLBACK TO SAVEPOINT $savepointName');
      print('SubscriberDb.insert 失败: topicId=$topicId, 错误=$e');
      return -1;
    }
  }

  // 更新订阅信息
  Future<bool> update({required TopicSubscription sub}) async {
    final storedSub = sub.payload as StoredSubscription?;
    final recordId = storedSub?.id;
    if (storedSub == null || recordId == null || recordId < 0) {
      return false;
    }

    final savepointName = 'SubscriberDb.update';
    try {
      await _db.execute('SAVEPOINT $savepointName');

      // 更新用户信息
      await _baseDb.userDb!.updateSubscription(sub);

      // 准备更新数据
      var status = storedSub.status!;
      final values = <String, dynamic>{
        columnMode: sub.acs?.serialize(),
        columnUpdated: sub.updated?.millisecondsSinceEpoch,
        columnRead: sub.read,
        columnRecv: sub.recv,
        columnClear: sub.clear,
        columnPriv: sub.serializePriv(),
        columnLastSeen: sub.seen?.when?.millisecondsSinceEpoch,
        columnUserAgent: sub.seen?.ua,
      };

      // 如果状态未同步，则更新为同步状态
      if (status != BaseDbStatus.synced) {
        values[columnStatus] = BaseDbStatus.synced.value;
        status = BaseDbStatus.synced;
      }

      // 执行更新
      final updatedCount = await _db.update(
        kTableName,
        values,
        where: '$columnId = ?',
        whereArgs: [recordId],
      );

      // 更新存储状态
      storedSub.status = status;

      await _db.execute('RELEASE SAVEPOINT $savepointName');
      return updatedCount > 0;
    } catch (e) {
      await _db.execute('ROLLBACK TO SAVEPOINT $savepointName');
      print('SubscriberDb.update 失败: subId=$recordId, 错误=$e');
      return false;
    }
  }

  // 删除单条订阅
  Future<bool> delete({required int recordId}) async {
    try {
      final deletedCount = await _db.delete(
        kTableName,
        where: '$columnId = ?',
        whereArgs: [recordId],
      );
      return deletedCount > 0;
    } catch (e) {
      print('SubscriberDb.delete 失败: subId=$recordId, 错误=$e');
      return false;
    }
  }

  // 删除指定主题的所有订阅
  Future<bool> deleteForTopic({required int topicId}) async {
    try {
      final deletedCount = await _db.delete(
        kTableName,
        where: '$topicId = ?',
        whereArgs: [topicId],
      );
      return deletedCount > 0;
    } catch (e) {
      print('SubscriberDb.deleteForTopic 失败: topicId=$topicId, 错误=$e');
      return false;
    }
  }

  // 从查询结果行构建SubscriptionProto
  TopicSubscription? _readOne(Map<String, dynamic> row) {
    final userDb = _baseDb.userDb!;
    final topicDb = _baseDb.topicDb!;

    // 根据类型创建订阅对象
    // final subType = row[columnSubscriptionClass];
    final sub = TopicSubscription();

    // 构建存储的订阅信息
    final storedSub = StoredSubscription(
      id: row[columnId],
      topicId: row[columnTopicId],
      userId: row[columnUserId],
      status: BaseDbStatus.fromValue(row[columnStatus] ?? 0),
    );

    // 填充订阅对象字段
    sub.acs = AccessMode.deserialize(row[columnMode]);
    sub.updated = row[columnUpdated] != null
        ? DateTime.fromMillisecondsSinceEpoch(row[columnUpdated])
        : null;
    sub.seq = row[topicDb.columnSeq];
    sub.read = row[columnRead];
    sub.recv = row[columnRecv];
    sub.clear = row[columnClear];
    sub.seen = Seen(
      when: row[columnLastSeen] != null
          ? DateTime.fromMillisecondsSinceEpoch(row[columnLastSeen])
          : null,
      ua: row[columnUserAgent],
    );

    sub.user = row[userDb.columnUid];
    sub.topic = row[topicDb.columnTopic];
    sub.deserializePub(row[userDb.columnPub]);
    sub.deserializePriv(row[columnPriv]);
    sub.payload = storedSub;

    return sub;
  }

  // 查询指定主题的所有订阅
  Future<List<TopicSubscription>?> readAll({required int topicId}) async {
    final userDb = _baseDb.userDb!;
    final topicDb = _baseDb.topicDb!;

    // 构建联合查询SQL（左外连接用户表和主题表）
    final query =
        '''
      SELECT 
        s.$columnId, s.$columnTopicId, s.$columnUserId, s.$columnStatus, s.$columnMode, s.$columnUpdated,
        s.$columnRead, s.$columnRecv, s.$columnClear, s.$columnPriv, s.$columnLastSeen, s.$columnUserAgent,
        u.${userDb.columnUid}, u.${userDb.columnPub},
        t.${topicDb.columnTopic}, t.${topicDb.columnSeq},
        s.$columnSubscriptionClass
      FROM $kTableName s
      LEFT OUTER JOIN ${UserDb.kTableName} u ON s.$columnUserId = u.${userDb.columnId}
      LEFT OUTER JOIN ${TopicDb.kTableName} t ON s.$columnTopicId = t.${topicDb.columnId}
      WHERE s.$topicId = ?
    ''';

    try {
      final rows = await _db.rawQuery(query, [topicId]);
      final subscriptions = <TopicSubscription>[];
      for (final row in rows) {
        final sub = _readOne(row);
        if (sub != null) {
          subscriptions.add(sub);
        } else {
          print(
            'SubscriberDb.readAll 失败: 无法创建订阅对象 ${row[columnSubscriptionClass]}',
          );
        }
      }
      return subscriptions;
    } catch (e) {
      print('SubscriberDb.readAll 失败: 错误=$e');
      return null;
    }
  }

  // 更新已读计数
  Future<bool> updateRead({required int subId, required int value}) async {
    return await _updateCounter(column: columnRead, subId: subId, value: value);
  }

  // 更新接收计数
  Future<bool> updateRecv({required int subId, required int value}) async {
    return await _updateCounter(column: columnRecv, subId: subId, value: value);
  }

  // 通用计数器更新方法（对应原BaseDb.updateCounter）
  Future<bool> _updateCounter({
    required String column,
    required int subId,
    required int value,
  }) async {
    try {
      final updatedCount = await _db.update(
        kTableName,
        {column: value},
        where: '$columnId = ?',
        whereArgs: [subId],
      );
      return updatedCount > 0;
    } catch (e) {
      print('SubscriberDb._updateCounter 失败: 列=$column, subId=$subId, 错误=$e');
      return false;
    }
  }
}
