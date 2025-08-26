import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import 'package:tinode/src/db/repository.dart';
import 'package:tinode/src/db/topic_repository.dart';
import 'package:tinode/src/db/user_repository.dart';
import 'package:tinode/src/models/topic-subscription.dart';
import 'package:tinode/src/models/access-mode.dart';

class SubscriptionStored {
  int? id;
  int? topicId;
  int? userId;
  RepositoryStatus? status;

  SubscriptionStored(this.id, this.topicId, this.userId, this.status);
}

class SubscriberRepositoryError implements Exception {
  final String message;

  SubscriberRepositoryError(this.message);

  @override
  String toString() {
    return 'SubscriberDb Error: $message';
  }
}

class SubscriberRepository extends Repository {
  static const String kTableName = 'subscriptions';

  // 表字段定义（对应原SQLite.Expression）
  static const String kColumnId = 'id';
  static const String kColumnTopicId = 'topic_id';
  static const String kColumnUserId = 'user_id';
  static const String kColumnStatus = 'status';
  static const String kColumnMode = 'mode';
  static const String kColumnUpdated = 'updated';
  static const String kColumnRead = 'read';
  static const String kColumnRecv = 'recv';
  static const String kColumnClear = 'clear';
  static const String kColumnPriv = 'priv';
  static const String kColumnLastSeen = 'last_seen';
  static const String kColumnUserAgent = 'user_agent';
  static const String kColumnSubscriptionClass = 'subscription_class';

  late UserRepository _userRepository;

  SubscriberRepository() {
    _userRepository = GetIt.I.get<UserRepository>();
  }

  // 删除表
  Future<void> destroyTable(DatabaseExecutor dbe) async {
    await dbe.execute('DROP INDEX IF EXISTS idx_${kTableName}_$kColumnTopicId');
    await dbe.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表（包含外键关联用户表和主题表）
  Future<void> createTable(DatabaseExecutor dbe) async {
    await dbe.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $kColumnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kColumnTopicId INTEGER REFERENCES ${UserRepository.kTableName}(${UserRepository.kColumnId}),
        $kColumnUserId INTEGER REFERENCES ${TopicRepository.kTableName}(${TopicRepository.kColumnId}),
        $kColumnStatus INTEGER,
        $kColumnMode TEXT,
        $kColumnUpdated INTEGER, -- 存储时间戳（Dart DateTime转毫秒）
        $kColumnRead INTEGER,
        $kColumnRecv INTEGER,
        $kColumnClear INTEGER,
        $kColumnPriv TEXT,
        $kColumnLastSeen INTEGER, -- 时间戳
        $kColumnUserAgent TEXT,
        $kColumnSubscriptionClass TEXT NOT NULL
      )
    ''');
    // 创建索引
    await dbe.execute(
      'CREATE INDEX IF NOT EXISTS idx_${kTableName}_$kColumnTopicId ON $kTableName($kColumnTopicId)',
    );
  }

  // 清空表数据
  Future<void> truncateTable(DatabaseExecutor dbe) async {
    await dbe.delete(kTableName);
  }

  // 插入订阅信息
  Future<int> insert(
    DatabaseExecutor dbe,
    int topicId,
    RepositoryStatus status,
    TopicSubscription sub,
  ) async {
    final savepointName = 'SubscriberDb.insert';
    try {
      await dbe.execute('SAVEPOINT $savepointName');

      // 获取或插入用户ID
      var userId = await _userRepository.getId(dbe, sub.user);
      if (userId <= 0) {
        userId = await _userRepository.insertSubscription(dbe, sub);
      }
      if (userId <= 0) {
        throw SubscriberRepositoryError('插入用户失败: $userId');
      }

      // 准备插入数据
      final values = {
        kColumnTopicId: topicId,
        kColumnUserId: userId,
        kColumnMode: sub.acs?.serialize(),
        kColumnUpdated:
            sub.updated?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
        kColumnStatus: status.value,
        kColumnRead: sub.read,
        kColumnRecv: sub.recv,
        kColumnClear: sub.clear,
        kColumnPriv: sub.serializePriv(),
        kColumnLastSeen: sub.seen?.when?.millisecondsSinceEpoch,
        kColumnUserAgent: sub.seen?.ua,
        kColumnSubscriptionClass: sub.runtimeType.toString(),
      };

      // 执行插入并返回ID
      final rowId = await dbe.insert(kTableName, values);
      // 关联存储信息到订阅对象
      final storedSub = SubscriptionStored(rowId, topicId, userId, status);
      sub.payload = storedSub;

      await dbe.execute('RELEASE SAVEPOINT $savepointName');
      return rowId;
    } catch (e) {
      await dbe.execute('ROLLBACK TO SAVEPOINT $savepointName');
      logError('SubscriberDb.insert 失败: topicId=$topicId, 错误=$e');
      return -1;
    }
  }

  // 更新订阅信息
  Future<bool> update(DatabaseExecutor dbe, TopicSubscription sub) async {
    final storedSub = sub.payload;
    final recordId = storedSub?.id;
    if (storedSub == null || recordId == null || recordId < 0) {
      return false;
    }

    final savepointName = 'SubscriberDb.update';
    try {
      await dbe.execute('SAVEPOINT $savepointName');

      // 更新用户信息
      await _userRepository.updateSubscription(dbe, sub);

      // 准备更新数据
      var status = storedSub.status!;
      final values = <String, dynamic>{
        kColumnMode: sub.acs?.serialize(),
        kColumnUpdated: sub.updated?.millisecondsSinceEpoch,
        kColumnRead: sub.read,
        kColumnRecv: sub.recv,
        kColumnClear: sub.clear,
        kColumnPriv: sub.serializePriv(),
        kColumnLastSeen: sub.seen?.when?.millisecondsSinceEpoch,
        kColumnUserAgent: sub.seen?.ua,
      };

      // 如果状态未同步，则更新为同步状态
      if (status != RepositoryStatus.synced) {
        values[kColumnStatus] = RepositoryStatus.synced.value;
        status = RepositoryStatus.synced;
      }

      // 执行更新
      final updatedCount = await dbe.update(
        kTableName,
        values,
        where: '$kColumnId = ?',
        whereArgs: [recordId],
      );

      // 更新存储状态
      storedSub.status = status;

      await dbe.execute('RELEASE SAVEPOINT $savepointName');
      return updatedCount > 0;
    } catch (e) {
      await dbe.execute('ROLLBACK TO SAVEPOINT $savepointName');
      print('SubscriberDb.update 失败: subId=$recordId, 错误=$e');
      return false;
    }
  }

  // 删除单条订阅
  Future<bool> delete(DatabaseExecutor dbe, int recordId) async {
    try {
      final deletedCount = await dbe.delete(
        kTableName,
        where: '$kColumnId = ?',
        whereArgs: [recordId],
      );
      return deletedCount > 0;
    } catch (e) {
      logError('Subscriber.delete 失败: subId=$recordId, 错误=$e');
      return false;
    }
  }

  // 删除指定主题的所有订阅
  Future<bool> deleteForTopic(DatabaseExecutor dbe, int topicId) async {
    try {
      final deletedCount = await dbe.delete(
        kTableName,
        where: '$topicId = ?',
        whereArgs: [topicId],
      );
      return deletedCount > 0;
    } catch (e) {
      logError('Subscriber.deleteForTopic 失败: topicId=$topicId, 错误=$e');
      return false;
    }
  }

  // 从查询结果行构建SubscriptionProto
  TopicSubscription? _readOne(Map<String, dynamic> row) {
    // 根据类型创建订阅对象
    // final subType = row[columnSubscriptionClass];
    final sub = TopicSubscription();

    // 构建存储的订阅信息
    final storedSub = SubscriptionStored(
      row[kColumnId],
      row[kColumnTopicId],
      row[kColumnUserId],
      RepositoryStatus.fromValue(row[kColumnStatus] ?? 0),
    );

    // 填充订阅对象字段
    sub.acs = AccessMode.deserialize(row[kColumnMode]);
    sub.updated = row[kColumnUpdated] != null
        ? DateTime.fromMillisecondsSinceEpoch(row[kColumnUpdated])
        : null;
    sub.seq = row[TopicRepository.kColumnSeq];
    sub.read = row[kColumnRead];
    sub.recv = row[kColumnRecv];
    sub.clear = row[kColumnClear];
    sub.seen = Seen(
      when: row[kColumnLastSeen] != null
          ? DateTime.fromMillisecondsSinceEpoch(row[kColumnLastSeen])
          : null,
      ua: row[kColumnUserAgent],
    );

    sub.user = row[UserRepository.kColumnUid];
    sub.topic = row[TopicRepository.kColumnTopic];
    sub.deserializePub(row[UserRepository.kColumnPub]);
    sub.deserializePriv(row[kColumnPriv]);
    sub.payload = storedSub;

    return sub;
  }

  // 查询指定主题的所有订阅
  Future<List<TopicSubscription>?> readAll(
    DatabaseExecutor dbe,
    int topicId,
  ) async {
    // 构建联合查询SQL（左外连接用户表和主题表）
    final query =
        '''
      SELECT
        s.$kColumnId, s.$kColumnTopicId, s.$kColumnUserId, s.$kColumnStatus, s.$kColumnMode, s.$kColumnUpdated,
        s.$kColumnRead, s.$kColumnRecv, s.$kColumnClear, s.$kColumnPriv, s.$kColumnLastSeen, s.$kColumnUserAgent,
        u.${UserRepository.kColumnUid}, u.${UserRepository.kColumnPub},
        t.${TopicRepository.kColumnTopic}, t.${TopicRepository.kColumnSeq},
        s.$kColumnSubscriptionClass
      FROM $kTableName s
      LEFT OUTER JOIN ${UserRepository.kTableName} u ON s.$kColumnUserId = u.${UserRepository.kColumnId}
      LEFT OUTER JOIN ${TopicRepository.kTableName} t ON s.$kColumnTopicId = t.${TopicRepository.kColumnId}
      WHERE s.$topicId = ?
    ''';

    try {
      final rows = await dbe.rawQuery(query, [topicId]);
      final subscriptions = <TopicSubscription>[];
      for (final row in rows) {
        final sub = _readOne(row);
        if (sub != null) {
          subscriptions.add(sub);
        } else {
          logError(
            'Subscriber.readAll 失败: 无法创建订阅对象 ${row[kColumnSubscriptionClass]}',
          );
        }
      }
      return subscriptions;
    } catch (e) {
      logError('Subscriber.readAll 失败: 错误=$e');
      return null;
    }
  }

  // 更新已读计数
  Future<bool> updateRead(DatabaseExecutor dbe, int subId, int value) async {
    return await _updateCounter(dbe, kColumnRead, subId, value);
  }

  // 更新接收计数
  Future<bool> updateRecv(DatabaseExecutor dbe, int subId, int value) async {
    return await _updateCounter(dbe, kColumnRecv, subId, value);
  }

  // 通用计数器更新方法（对应原BaseDb.updateCounter）
  Future<bool> _updateCounter(
    DatabaseExecutor dbe,
    String column,
    int subId,
    int value,
  ) async {
    try {
      final updatedCount = await dbe.update(
        kTableName,
        {column: value},
        where: '$kColumnId = ?',
        whereArgs: [subId],
      );
      return updatedCount > 0;
    } catch (e) {
      print('SubscriberDb._updateCounter 失败: 列=$column, subId=$subId, 错误=$e');
      return false;
    }
  }
}
