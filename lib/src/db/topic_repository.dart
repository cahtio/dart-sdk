import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:tinode/src/db/account_repository.dart';
import 'package:tinode/src/db/repository.dart';
import 'package:tinode/src/models/access-mode.dart';
import 'package:tinode/src/services/database_manager.dart';
import 'package:tinode/src/models/topic-names.dart' as topic_names;
import 'package:tinode/src/topic.dart';
import 'package:tinode/src/topic-me.dart';
import 'package:tinode/src/topic-fnd.dart';
import 'package:tinode/src/models/def-acs.dart';

class TopicStored {
  int? id;
  DateTime? lastUsed;
  int? minLocalSeq;
  int? maxLocalSeq;
  RepositoryStatus status = RepositoryStatus.undefined;
  int? nextUnsentId;

  static bool isAllDataLoaded(Topic? topic) {
    if (topic == null) return false;
    if ((topic.seq ?? -1) == 0) return true;
    if (topic.payload is! TopicStored) return false;
    var topicStored = topic.payload as TopicStored;
    return (topicStored.minLocalSeq ?? -1) == 1;
  }
}

class TopicRepository extends Repository {
  static const String kTableName = 'topics';
  static const int kUnsentIdStart = 2000000000;

  // 表字段名
  static const String kColumnId = 'id';
  static const String kColumnAccountId = 'account_id';
  static const String kColumnStatus = 'status';
  static const String kColumnTopic = 'topic';
  static const String kColumnType = 'type';
  static const String kColumnVisible = 'visible';
  static const String kColumnCreated = 'created';
  static const String kColumnUpdated = 'updated';
  static const String kColumnRead = 'read';
  static const String kColumnRecv = 'recv';
  static const String kColumnSeq = 'seq';
  static const String kColumnClear = 'clear';
  static const String kColumnMaxDel = 'max_del';
  static const String kColumnAccessMode = 'mode';
  static const String kColumnDefacs = 'defacs';
  static const String kColumnLastUsed = 'last_used';
  static const String kColumnMinLocalSeq = 'min_local_seq';
  static const String kColumnMaxLocalSeq = 'max_local_seq';
  static const String kColumnNextUnsentSeq = 'next_unsent_seq';
  static const String kColumnTags = 'tags';
  static const String kColumnCreds = 'creds';
  static const String kColumnPub = 'pub';
  static const String kColumnPriv = 'priv';
  static const String kColumnTrusted = 'trusted';

  TopicRepository();

  // 删除表
  Future<void> destroyTable(DatabaseExecutor dbe) async {
    await dbe.execute('DROP INDEX IF EXISTS idx_account_topic ON $kTableName');
    await dbe.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表
  Future<void> createTable(DatabaseExecutor dbe) async {
    await dbe.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $kColumnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kColumnAccountId INTEGER REFERENCES ${AccountRepository.kTableName}(${AccountRepository.kColumnId}),
        $kColumnStatus INTEGER,
        $kColumnTopic TEXT,
        $kColumnType INTEGER,
        $kColumnVisible INTEGER,
        $kColumnCreated DATETIME,
        $kColumnUpdated DATETIME,
        $kColumnRead INTEGER,
        $kColumnRecv INTEGER,
        $kColumnSeq INTEGER,
        $kColumnClear INTEGER,
        $kColumnMaxDel INTEGER,
        $kColumnAccessMode TEXT,
        $kColumnDefacs TEXT,
        $kColumnLastUsed DATETIME,
        $kColumnMinLocalSeq INTEGER,
        $kColumnMaxLocalSeq INTEGER,
        $kColumnNextUnsentSeq INTEGER,
        $kColumnTags TEXT,
        $kColumnCreds TEXT,
        $kColumnPub TEXT,
        $kColumnPriv TEXT,
        $kColumnTrusted TEXT
      )
    ''');
    // 创建唯一索引
    await dbe.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_account_topic 
      ON $kTableName($kColumnAccountId, $kColumnTopic)
    ''');
  }

  // 清空表数据
  Future<void> truncateTable(DatabaseExecutor dbe) async {
    await dbe.delete(kTableName);
  }

  // 检查是否为未发送序列
  static bool isUnsentSeq(int seq) {
    return seq >= kUnsentIdStart;
  }

  // 从数据库行数据反序列化为TopicProto
  void deserializeTopic(Topic topic, Map<String, dynamic> row) {
    var st = TopicStored()
      ..id = row[kColumnId]
      ..status = RepositoryStatus.values.firstWhere(
        (e) => e.value == row[kColumnStatus],
        orElse: () => RepositoryStatus.undefined,
      )
      ..lastUsed = row[kColumnLastUsed] != null
          ? DateTime.parse(row[kColumnLastUsed])
          : DateTime.now()
      ..minLocalSeq = row[kColumnMinLocalSeq]
      ..maxLocalSeq = row[kColumnMaxLocalSeq]
      ..nextUnsentId = row[kColumnNextUnsentSeq];

    topic.updated = row[kColumnUpdated] != null
        ? DateTime.parse(row[kColumnUpdated])
        : DateTime.now();
    topic.touched = st.lastUsed;
    topic.deleted =
        st.status == RepositoryStatus.deletedHard ||
        st.status == RepositoryStatus.deletedSoft;
    topic.read = row[kColumnRead];
    topic.recv = row[kColumnRecv];
    topic.seq = row[kColumnSeq];
    topic.clear = row[kColumnClear];
    topic.maxDel = row[kColumnMaxDel] ?? 0;

    if (topic is TopicMe) {
      topic.deserializeCreds(row[kColumnCreds]);
    }

    if (row[kColumnTags] != null) {
      topic.tags = row[kColumnTags]!.toString().split(',');
    }

    final decodeAcs = AccessMode.deserialize(row[kColumnAccessMode]);
    if (decodeAcs != null) {
      topic.acs = decodeAcs;
    }

    topic.defacs = DefAcs.deserialize(row[kColumnDefacs]);
    topic.public = json.decode(row[kColumnPub]);
    topic.private = json.decode(row[kColumnPriv]);
    topic.trusted = json.decode(row[kColumnTrusted]);
    topic.payload = st;
  }

  // 根据话题名获取ID
  Future<int> getId(DatabaseExecutor dbe, String? topicName) async {
    if (topicName == null) return -1;
    var accountIdVal = DatabaseManager().account?.id;
    if (accountIdVal == null) return -1;

    var result = await dbe.query(
      kTableName,
      columns: [kColumnId],
      where: '$kColumnAccountId = ? AND $kColumnTopic = ?',
      whereArgs: [accountIdVal, topicName],
    );
    return result.isNotEmpty ? result.first[kColumnId] as int : -1;
  }

  // 获取下一个未使用的序列
  Future<int> getNextUnusedSeq(DatabaseExecutor dbe, Topic topic) async {
    var st = topic.payload as TopicStored?;
    if (st == null || st.id == null) return -1;

    st.nextUnsentId = (st.nextUnsentId ?? 0) + 1;
    var rowsAffected = await dbe.update(
      kTableName,
      {kColumnNextUnsentSeq: st.nextUnsentId},
      where: '$kColumnId = ?',
      whereArgs: [st.id],
    );

    return rowsAffected > 0 ? st.nextUnsentId! : -1;
  }

  // 查询所有话题
  Future<List<Map<String, dynamic>>?> query(DatabaseExecutor dbe) async {
    var accountIdVal = DatabaseManager().account?.id;
    if (accountIdVal == null) return null;

    return dbe.query(
      kTableName,
      where: '$kColumnAccountId = ?',
      whereArgs: [accountIdVal],
    );
  }

  // 根据话题名查询单个话题
  Future<Topic?> readOne(DatabaseExecutor dbe, String? topicName) async {
    var accountIdVal = DatabaseManager().account?.id;
    if (accountIdVal == null || topicName == null) return null;

    var result = await dbe.query(
      kTableName,
      where: '$kColumnAccountId = ? AND $kColumnTopic = ?',
      whereArgs: [accountIdVal, topicName],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return readOneFromRow(result.first);
    }
    return null;
  }

  // 从行数据读取话题
  Topic? readOneFromRow(Map<String, dynamic> row) {
    var topicName = row[kColumnTopic] as String?;
    if (topicName == null) return null;

    Topic t;
    if (topicName == topic_names.TOPIC_ME) {
      t = TopicMe();
    } else if (topicName == topic_names.TOPIC_FND) {
      t = TopicFnd();
    } else {
      t = Topic(topicName);
    }

    deserializeTopic(t, row);
    return t;
  }

  // 插入新话题
  Future<int> insert(DatabaseExecutor dbe, Topic topic) async {
    logInfo('TopicDb - insert insert');
    var accountIdVal = DatabaseManager().account?.id;
    if (accountIdVal == null) {
      return -1;
    }

    try {
      // var res = await readOne(_topic.name);
      // if (res != null) {
      //   _topic.payload = res.payload;
      //   return (res.payload as StoredTopic).id!;
      // }
      var _lastUsed =
          topic.touched ?? DateTime.fromMillisecondsSinceEpoch(1414213562000);
      var tp = topic.topicType;
      var _status = topic.isNew
          ? RepositoryStatus.queued
          : RepositoryStatus.synced;

      String? creds;
      if (topic is TopicMe) {
        creds = topic.serializeCreds();
      }

      var rowId = await dbe.insert(kTableName, {
        kColumnAccountId: accountIdVal,
        kColumnStatus: _status.value,
        kColumnTopic: topic.name,
        kColumnType: tp.rawValue,
        kColumnVisible: [TopicType.grp, TopicType.p2p].contains(tp) ? 1 : 0,
        kColumnCreated: _lastUsed.toIso8601String(),
        kColumnUpdated: topic.updated?.toIso8601String(),
        kColumnRead: topic.read,
        kColumnRecv: topic.recv,
        kColumnSeq: topic.seq,
        kColumnClear: topic.clear,
        kColumnMaxDel: topic.maxDel,
        kColumnAccessMode: topic.acs.serialize(),
        kColumnDefacs: topic.defacs?.serialize(),
        kColumnLastUsed: _lastUsed.toIso8601String(),
        kColumnMinLocalSeq: 0,
        kColumnMaxLocalSeq: 0,
        kColumnNextUnsentSeq: kUnsentIdStart,
        kColumnTags: topic.tags.join(','),
        kColumnCreds: creds,
        kColumnPub: topic.serializePub(),
        kColumnPriv: topic.serializePriv(),
        kColumnTrusted: topic.serializeTrusted(),
      });

      if (rowId > 0) {
        var st = TopicStored()
          ..id = rowId
          ..lastUsed = _lastUsed
          ..minLocalSeq = null
          ..maxLocalSeq = null
          ..status = _status
          ..nextUnsentId = kUnsentIdStart;
        topic.payload = st;
      }
      return rowId;
    } catch (e) {
      logError('TopicDb - insert operation failed: error = $e');
      return -1;
    }
  }

  // 更新话题
  Future<bool> update(DatabaseExecutor dbe, Topic topic) async {
    var st = topic.payload as TopicStored?;
    if (st == null || st.id == null) return false;

    var setters = <String, dynamic>{};
    var _status = st.status;

    if (_status == RepositoryStatus.queued && !topic.isNew) {
      _status = RepositoryStatus.synced;
      setters[kColumnStatus] = _status.value;
      setters[kColumnTopic] = topic.name;
    }

    setters[kColumnUpdated] = topic.updated?.toIso8601String();
    setters[kColumnRead] = topic.read;
    setters[kColumnRecv] = topic.recv;
    setters[kColumnSeq] = topic.seq;
    setters[kColumnClear] = topic.clear;
    setters[kColumnAccessMode] = topic.acs.serialize();
    setters[kColumnDefacs] = topic.defacs?.serialize();
    setters[kColumnTags] = topic.tags.join(',');

    if (topic is TopicMe) {
      setters[kColumnCreds] = topic.serializeCreds();
    }
    setters[kColumnPub] = topic.serializePub();
    setters[kColumnPriv] = topic.serializePriv();
    setters[kColumnTrusted] = topic.serializeTrusted();

    if (topic.touched != null) {
      setters[kColumnLastUsed] = topic.touched!.toIso8601String();
    }

    try {
      var rowsAffected = await dbe.update(
        kTableName,
        setters,
        where: '$kColumnId = ?',
        whereArgs: [st.id],
      );

      if (rowsAffected > 0) {
        if (topic.touched != null) st.lastUsed = topic.touched;
        st.status = _status;
        return true;
      }
    } catch (e) {
      logError('TopicDb - update failed: topicId = ${st.id}, error = $e');
    }
    return false;
  }

  // 处理消息接收
  Future<bool> msgReceived(
    DatabaseExecutor dbe,
    Topic topic,
    DateTime ts,
    int seq,
  ) async {
    var st = topic.payload as TopicStored?;
    if (st == null || st.id == null) return false;

    var setters = <String, dynamic>{};
    var updateMaxLocalSeq = false;
    if (seq > (st.maxLocalSeq ?? -1)) {
      setters[kColumnMaxLocalSeq] = seq;
      setters[kColumnRecv] = seq;
      updateMaxLocalSeq = true;
    }

    var updateMinLocalSeq = false;
    if (seq > 0 &&
        (st.minLocalSeq == 0 || seq < (st.minLocalSeq ?? ((1 << 63) - 1)))) {
      setters[kColumnMinLocalSeq] = seq;
      updateMinLocalSeq = true;
    }

    if (seq > (topic.seq ?? -1)) {
      setters[kColumnSeq] = seq;
    }

    var updateLastUsed = false;
    if (st.lastUsed != null && st.lastUsed!.isBefore(ts)) {
      setters[kColumnLastUsed] = ts.toIso8601String();
      updateLastUsed = true;
    }

    if (setters.isNotEmpty) {
      try {
        var rowsAffected = await dbe.update(
          kTableName,
          setters,
          where: '$kColumnId = ?',
          whereArgs: [st.id],
        );

        if (rowsAffected > 0) {
          if (updateLastUsed) st.lastUsed = ts;
          if (updateMinLocalSeq) st.minLocalSeq = seq;
          if (updateMaxLocalSeq) st.maxLocalSeq = seq;
        }
      } catch (e) {
        logError(
          'TopicDb - msgReceived failed: topicId = ${st.id}, error = $e',
        );
        return false;
      }
    }
    return true;
  }

  // 处理消息删除
  Future<bool> msgDeleted(
    DatabaseExecutor dbe,
    Topic topic,
    int delId,
    int loId,
    int hiId,
  ) async {
    var st = topic.payload as TopicStored?;
    if (st == null || st.id == null) return false;

    var setters = <String, dynamic>{};
    if (delId > topic.maxDel) {
      setters[kColumnMaxDel] = delId;
    }

    var adjustedLoId = loId > 0 ? loId : 1;
    var adjustedHiId = hiId > 1 ? hiId - 1 : (topic.seq ?? 0);

    var updateLo = false;
    if (adjustedLoId < (st.minLocalSeq ?? 0) &&
        adjustedHiId >= (st.minLocalSeq ?? 0)) {
      setters[kColumnMinLocalSeq] = adjustedLoId;
      updateLo = true;
    } else {
      adjustedLoId = -1;
    }

    var updateHi = false;
    if (adjustedHiId > (st.maxLocalSeq ?? 0) &&
        adjustedLoId <= (st.maxLocalSeq ?? 0)) {
      setters[kColumnMaxLocalSeq] = adjustedHiId;
      updateHi = true;
    } else {
      adjustedHiId = -1;
    }

    if (setters.isEmpty) return true;

    try {
      var rowsAffected = await dbe.update(
        kTableName,
        setters,
        where: '$kColumnId = ?',
        whereArgs: [st.id],
      );

      if (rowsAffected > 0) {
        if (updateLo) st.minLocalSeq = adjustedLoId;
        if (updateHi) st.maxLocalSeq = adjustedHiId;
        return true;
      }
    } catch (e) {
      logError('TopicDb - msgDeleted failed: topicId = ${st.id}, error = $e');
    }
    return false;
  }

  // 删除记录
  Future<bool> delete(DatabaseExecutor dbe, int recordId) async {
    try {
      var rowsAffected = await dbe.delete(
        kTableName,
        where: '$kColumnId = ?',
        whereArgs: [recordId],
      );
      return rowsAffected > 0;
    } catch (e) {
      logError('TopicDb - delete failed: topicId = $recordId, error = $e');
      return false;
    }
  }

  // 标记为删除
  Future<bool> markDeleted(DatabaseExecutor dbe, int recordId) async {
    try {
      var rowsAffected = await dbe.update(
        kTableName,
        {kColumnStatus: RepositoryStatus.deletedHard.value},
        where: '$kColumnId = ?',
        whereArgs: [recordId],
      );
      return rowsAffected > 0;
    } catch (e) {
      logError('TopicDb - markDeleted failed: topicId = $recordId, error = $e');
      return false;
    }
  }

  // // 删除指定账户的所有话题
  // Future<bool> deleteAll(int accountIdVal) async {
  //   var messageDb = _baseDb.messageDb;
  //   var subscriberDb = _baseDb.subscriberDb;
  //   if (messageDb == null || subscriberDb == null) return false;

  //   try {
  //     // 删除关联的消息
  //     await _db.execute(
  //       '''
  //       DELETE FROM ${MessageDb.kTableName}
  //       WHERE ${MessageDb.colTopicId} IN (
  //         SELECT $columnId FROM $kTableName WHERE $columnAccountId = ?
  //       )
  //     ''',
  //       [accountIdVal],
  //     );

  //     // 删除关联的订阅者
  //     await _db.execute(
  //       '''
  //       DELETE FROM ${SubscriberDb.kTableName}
  //       WHERE ${subscriberDb.columnTopicId} IN (
  //         SELECT $columnId FROM $kTableName WHERE $columnAccountId = ?
  //       )
  //     ''',
  //       [accountIdVal],
  //     );

  //     // 删除话题
  //     await _db.delete(
  //       kTableName,
  //       where: '$columnAccountId = ?',
  //       whereArgs: [accountIdVal],
  //     );
  //     return true;
  //   } catch (e) {
  //     BaseDb.log.error(
  //       'TopicDb - deleteAll failed: accountId = $accountIdVal, error = $e',
  //     );
  //     return false;
  //   }
  // }

  // // 更新已读计数
  // Future<bool> updateRead(int topicId, int value) async {
  //   return _updateCounter(topicId, columnRead, value);
  // }

  // // 更新接收计数
  // Future<bool> updateRecv(int topicId, int value) async {
  //   return _updateCounter(topicId, columnRecv, value);
  // }

  // // 通用计数器更新
  // Future<bool> _updateCounter(int topicId, String column, int value) async {
  //   try {
  //     var rowsAffected = await _db.update(
  //       kTableName,
  //       {column: value},
  //       where: '$columnId = ?',
  //       whereArgs: [topicId],
  //     );
  //     return rowsAffected > 0;
  //   } catch (e) {
  //     BaseDb.log.error(
  //       'TopicDb - updateCounter failed: topicId = $topicId, error = $e',
  //     );
  //     return false;
  //   }
  // }
}
