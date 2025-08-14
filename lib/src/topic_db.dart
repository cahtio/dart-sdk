import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/account_db.dart';
import 'package:tinode/src/models/def-acs.dart';
import 'package:tinode/src/subscriber_db.dart';
import 'message_db.dart';
import 'topic.dart';
import 'topic-me.dart';
import 'models/access-mode.dart';
import 'base_db.dart';

class TopicDb {
  static const String kTableName = 'topics';
  static const int kUnsentIdStart = 2000000000;

  final Database _db;
  final BaseDb _baseDb;

  // 表字段名
  final String columnId = 'id';
  final String columnAccountId = 'account_id';
  final String columnStatus = 'status';
  final String columnTopic = 'topic';
  final String columnType = 'type';
  final String columnVisible = 'visible';
  final String columnCreated = 'created';
  final String columnUpdated = 'updated';
  final String columnRead = 'read';
  final String columnRecv = 'recv';
  final String columnSeq = 'seq';
  final String columnClear = 'clear';
  final String columnMaxDel = 'max_del';
  final String columnAccessMode = 'mode';
  final String columnDefacs = 'defacs';
  final String columnLastUsed = 'last_used';
  final String columnMinLocalSeq = 'min_local_seq';
  final String columnMaxLocalSeq = 'max_local_seq';
  final String columnNextUnsentSeq = 'next_unsent_seq';
  final String columnTags = 'tags';
  final String columnCreds = 'creds';
  final String columnPub = 'pub';
  final String columnPriv = 'priv';
  final String columnTrusted = 'trusted';

  TopicDb(this._db, this._baseDb);

  // 删除表
  Future<void> destroyTable() async {
    await _db.execute('DROP INDEX IF EXISTS idx_account_topic ON $kTableName');
    await _db.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表
  Future<void> createTable() async {
    // var accountDb = _baseDb.accountDb!;
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnAccountId INTEGER REFERENCES ${AccountDb.kTableName}(${AccountDb.columnId}),
        $columnStatus INTEGER,
        $columnTopic TEXT,
        $columnType INTEGER,
        $columnVisible INTEGER,
        $columnCreated DATETIME,
        $columnUpdated DATETIME,
        $columnRead INTEGER,
        $columnRecv INTEGER,
        $columnSeq INTEGER,
        $columnClear INTEGER,
        $columnMaxDel INTEGER,
        $columnAccessMode TEXT,
        $columnDefacs TEXT,
        $columnLastUsed DATETIME,
        $columnMinLocalSeq INTEGER,
        $columnMaxLocalSeq INTEGER,
        $columnNextUnsentSeq INTEGER,
        $columnTags TEXT,
        $columnCreds TEXT,
        $columnPub TEXT,
        $columnPriv TEXT,
        $columnTrusted TEXT
      )
    ''');
    // 创建唯一索引
    await _db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_account_topic 
      ON $kTableName($columnAccountId, $columnTopic)
    ''');
  }

  // 清空表数据
  Future<void> truncateTable(DatabaseExecutor db) async {
    await db.delete(kTableName);
  }

  // 检查是否为未发送序列
  static bool isUnsentSeq(int seq) {
    return seq >= kUnsentIdStart;
  }

  // 从数据库行数据反序列化为TopicProto
  void deserializeTopic(Topic topic, Map<String, dynamic> row) {
    BaseDb.log.info('TopicDb.insert: deserializeTopic.');
    var st = StoredTopic()
      ..id = row[columnId]
      ..status = BaseDbStatus.values.firstWhere(
        (e) => e.value == row[columnStatus],
        orElse: () => BaseDbStatus.undefined,
      )
      ..lastUsed = row[columnLastUsed] != null
          ? DateTime.parse(row[columnLastUsed])
          : DateTime.now()
      ..minLocalSeq = row[columnMinLocalSeq]
      ..maxLocalSeq = row[columnMaxLocalSeq]
      ..nextUnsentId = row[columnNextUnsentSeq];

    BaseDb.log.info('TopicDb.insert: StoredTopic.');

    topic.updated = row[columnUpdated] != null
        ? DateTime.parse(row[columnUpdated])
        : DateTime.now();
    topic.touched = st.lastUsed;
    topic.deleted =
        st.status == BaseDbStatus.deletedHard ||
        st.status == BaseDbStatus.deletedSoft;
    topic.read = row[columnRead];
    topic.recv = row[columnRecv];
    topic.seq = row[columnSeq];
    topic.clear = row[columnClear];
    topic.maxDel = row[columnMaxDel] ?? 0;

    BaseDb.log.info('TopicDb.insert: topic.');

    if (topic is TopicMe) {
      topic.deserializeCreds(row[columnCreds]);
    }

    BaseDb.log.info('TopicDb.insert: TopicMe.');
    BaseDb.log.info('${row[columnTags]}');
    if (row[columnTags]) {
      topic.tags = row[columnTags]!.toString().split(',');
    }
    BaseDb.log.info('TopicDb.insert: decodeAcs.');
    final decodeAcs = AccessMode.deserialize(row[columnAccessMode]);
    if (decodeAcs != null) {
      topic.acs = decodeAcs;
    }

    BaseDb.log.info('TopicDb.insert: defacs.');

    topic.defacs = DefAcs.deserialize(row[columnDefacs]);
    topic.public = json.decode(row[columnPub]);
    topic.private = json.decode(row[columnPriv]);
    topic.trusted = json.decode(row[columnTrusted]);
    topic.payload = st;
  }

  // 根据话题名获取ID
  Future<int> getId(String? topicName) async {
    if (topicName == null) return -1;
    var accountIdVal = _baseDb.account?.id;
    if (accountIdVal == null) return -1;

    var result = await _db.query(
      kTableName,
      columns: [columnId],
      where: '$columnAccountId = ? AND $columnTopic = ?',
      whereArgs: [accountIdVal, topicName],
    );
    return result.isNotEmpty ? result.first[columnId] as int : -1;
  }

  // 获取下一个未使用的序列
  Future<int> getNextUnusedSeq(Topic topic) async {
    var st = topic.payload as StoredTopic?;
    if (st == null || st.id == null) return -1;

    st.nextUnsentId = (st.nextUnsentId ?? 0) + 1;
    var rowsAffected = await _db.update(
      kTableName,
      {columnNextUnsentSeq: st.nextUnsentId},
      where: '$columnId = ?',
      whereArgs: [st.id],
    );

    return rowsAffected > 0 ? st.nextUnsentId! : -1;
  }

  // 查询所有话题
  Future<List<Map<String, dynamic>>?> query() async {
    var accountIdVal = _baseDb.account?.id;
    if (accountIdVal == null) return null;

    return _db.query(
      kTableName,
      where: '$columnAccountId = ?',
      whereArgs: [accountIdVal],
    );
  }

  // 根据话题名查询单个话题
  Future<Topic?> readOne(String? topicName) async {
    var accountIdVal = _baseDb.account?.id;
    if (accountIdVal == null || topicName == null) return null;

    var result = await _db.query(
      kTableName,
      where: '$columnAccountId = ? AND $columnTopic = ?',
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
    BaseDb.log.info('TopicDb.insert: readOneFromRow.');
    var topicName = row[columnTopic] as String?;
    if (topicName == null) return null;

    var t = Topic(topicName);
    deserializeTopic(t, row);
    return t;
  }

  // 插入新话题
  Future<int> insert(Topic _topic) async {
    var accountIdVal = _baseDb.account?.id;
    if (accountIdVal == null) {
      BaseDb.log.error('TopicDb.insert: account id is not defined.');
      return -1;
    }

    try {
      BaseDb.log.info('TopicDb.insert: readOne.');
      var res = await readOne(_topic.name);
      if (res != null) {
        BaseDb.log.info('TopicDb.insert: read for cache.');
        _topic.payload = res.payload;
        return (res.payload as StoredTopic).id!;
      }
      var _lastUsed =
          _topic.touched ?? DateTime.fromMillisecondsSinceEpoch(1414213562000);
      var tp = _topic.topicType;
      var _status = _topic.isNew ? BaseDbStatus.queued : BaseDbStatus.synced;

      String? _creds;
      if (_topic is TopicMe) {
        _creds = _topic.serializeCreds();
      }

      var rowId = await _db.insert(kTableName, {
        columnAccountId: accountIdVal,
        columnStatus: _status.value,
        columnTopic: _topic.name,
        columnType: tp.rawValue,
        columnVisible: [TopicType.grp, TopicType.p2p].contains(tp) ? 1 : 0,
        columnCreated: _lastUsed.toIso8601String(),
        columnUpdated: _topic.updated?.toIso8601String(),
        columnRead: _topic.read,
        columnRecv: _topic.recv,
        columnSeq: _topic.seq,
        columnClear: _topic.clear,
        columnMaxDel: _topic.maxDel,
        columnAccessMode: _topic.acs.serialize(),
        columnDefacs: _topic.defacs?.serialize(),
        columnLastUsed: _lastUsed.toIso8601String(),
        columnMinLocalSeq: 0,
        columnMaxLocalSeq: 0,
        columnNextUnsentSeq: kUnsentIdStart,
        columnTags: _topic.tags.join(','),
        columnCreds: _creds,
        columnPub: _topic.serializePub(),
        columnPriv: _topic.serializePriv(),
        columnTrusted: _topic.serializeTrusted(),
      });

      if (rowId > 0) {
        var st = StoredTopic()
          ..id = rowId
          ..lastUsed = _lastUsed
          ..minLocalSeq = null
          ..maxLocalSeq = null
          ..status = _status
          ..nextUnsentId = kUnsentIdStart;
        _topic.payload = st;
      }
      return rowId;
    } catch (e) {
      BaseDb.log.error('TopicDb - insert operation failed: error = $e');
      return -1;
    }
  }

  // 更新话题
  Future<bool> update(Topic _topic) async {
    var st = _topic.payload as StoredTopic?;
    if (st == null || st.id == null) return false;

    var setters = <String, dynamic>{};
    var _status = st.status;

    if (_status == BaseDbStatus.queued && !_topic.isNew) {
      _status = BaseDbStatus.synced;
      setters[columnStatus] = _status.value;
      setters[columnTopic] = _topic.name;
    }

    setters[columnUpdated] = _topic.updated?.toIso8601String();
    setters[columnRead] = _topic.read;
    setters[columnRecv] = _topic.recv;
    setters[columnSeq] = _topic.seq;
    setters[columnClear] = _topic.clear;
    setters[columnAccessMode] = _topic.acs.serialize();
    setters[columnDefacs] = _topic.defacs?.serialize();
    setters[columnTags] = _topic.tags.join(',');

    if (_topic is TopicMe) {
      setters[columnCreds] = _topic.serializeCreds();
    }
    setters[columnPub] = _topic.serializePub();
    setters[columnPriv] = _topic.serializePriv();
    setters[columnTrusted] = _topic.serializeTrusted();

    if (_topic.touched != null) {
      setters[columnLastUsed] = _topic.touched!.toIso8601String();
    }

    try {
      var rowsAffected = await _db.update(
        kTableName,
        setters,
        where: '$columnId = ?',
        whereArgs: [st.id],
      );

      if (rowsAffected > 0) {
        if (_topic.touched != null) st.lastUsed = _topic.touched;
        st.status = _status;
        return true;
      }
    } catch (e) {
      BaseDb.log.error(
        'TopicDb - update failed: topicId = ${st.id}, error = $e',
      );
    }
    return false;
  }

  // 处理消息接收
  Future<bool> msgReceived(Topic topic, DateTime ts, int seq) async {
    var st = topic.payload as StoredTopic?;
    if (st == null || st.id == null) return false;

    var setters = <String, dynamic>{};
    var updateMaxLocalSeq = false;
    if (seq > (st.maxLocalSeq ?? -1)) {
      setters[columnMaxLocalSeq] = seq;
      setters[columnRecv] = seq;
      updateMaxLocalSeq = true;
    }

    var updateMinLocalSeq = false;
    if (seq > 0 &&
        (st.minLocalSeq == 0 || seq < (st.minLocalSeq ?? ((1 << 63) - 1)))) {
      setters[columnMinLocalSeq] = seq;
      updateMinLocalSeq = true;
    }

    if (seq > (topic.seq ?? -1)) {
      setters[columnSeq] = seq;
    }

    var updateLastUsed = false;
    if (st.lastUsed != null && st.lastUsed!.isBefore(ts)) {
      setters[columnLastUsed] = ts.toIso8601String();
      updateLastUsed = true;
    }

    if (setters.isNotEmpty) {
      try {
        var rowsAffected = await _db.update(
          kTableName,
          setters,
          where: '$columnId = ?',
          whereArgs: [st.id],
        );

        if (rowsAffected > 0) {
          if (updateLastUsed) st.lastUsed = ts;
          if (updateMinLocalSeq) st.minLocalSeq = seq;
          if (updateMaxLocalSeq) st.maxLocalSeq = seq;
        }
      } catch (e) {
        BaseDb.log.error(
          'TopicDb - msgReceived failed: topicId = ${st.id}, error = $e',
        );
        return false;
      }
    }
    return true;
  }

  // 处理消息删除
  Future<bool> msgDeleted(Topic topic, int delId, int loId, int hiId) async {
    var st = topic.payload as StoredTopic?;
    if (st == null || st.id == null) return false;

    var setters = <String, dynamic>{};
    if (delId > topic.maxDel) {
      setters[columnMaxDel] = delId;
    }

    var adjustedLoId = loId > 0 ? loId : 1;
    var adjustedHiId = hiId > 1 ? hiId - 1 : (topic.seq ?? 0);

    var updateLo = false;
    if (adjustedLoId < (st.minLocalSeq ?? 0) &&
        adjustedHiId >= (st.minLocalSeq ?? 0)) {
      setters[columnMinLocalSeq] = adjustedLoId;
      updateLo = true;
    } else {
      adjustedLoId = -1;
    }

    var updateHi = false;
    if (adjustedHiId > (st.maxLocalSeq ?? 0) &&
        adjustedLoId <= (st.maxLocalSeq ?? 0)) {
      setters[columnMaxLocalSeq] = adjustedHiId;
      updateHi = true;
    } else {
      adjustedHiId = -1;
    }

    if (setters.isEmpty) return true;

    try {
      var rowsAffected = await _db.update(
        kTableName,
        setters,
        where: '$columnId = ?',
        whereArgs: [st.id],
      );

      if (rowsAffected > 0) {
        if (updateLo) st.minLocalSeq = adjustedLoId;
        if (updateHi) st.maxLocalSeq = adjustedHiId;
        return true;
      }
    } catch (e) {
      BaseDb.log.error(
        'TopicDb - msgDeleted failed: topicId = ${st.id}, error = $e',
      );
    }
    return false;
  }

  // 删除记录
  Future<bool> delete(int recordId) async {
    try {
      var rowsAffected = await _db.delete(
        kTableName,
        where: '$columnId = ?',
        whereArgs: [recordId],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error(
        'TopicDb - delete failed: topicId = $recordId, error = $e',
      );
      return false;
    }
  }

  // 标记为删除
  Future<bool> markDeleted(int recordId) async {
    try {
      var rowsAffected = await _db.update(
        kTableName,
        {columnStatus: BaseDbStatus.deletedHard.value},
        where: '$columnId = ?',
        whereArgs: [recordId],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error(
        'TopicDb - markDeleted failed: topicId = $recordId, error = $e',
      );
      return false;
    }
  }

  // 删除指定账户的所有话题
  Future<bool> deleteAll(int accountIdVal) async {
    var messageDb = _baseDb.messageDb;
    var subscriberDb = _baseDb.subscriberDb;
    if (messageDb == null || subscriberDb == null) return false;

    try {
      // 删除关联的消息
      await _db.execute(
        '''
        DELETE FROM ${MessageDb.kTableName} 
        WHERE ${MessageDb.colTopicId} IN (
          SELECT $columnId FROM $kTableName WHERE $columnAccountId = ?
        )
      ''',
        [accountIdVal],
      );

      // 删除关联的订阅者
      await _db.execute(
        '''
        DELETE FROM ${SubscriberDb.kTableName} 
        WHERE ${subscriberDb.columnTopicId} IN (
          SELECT $columnId FROM $kTableName WHERE $columnAccountId = ?
        )
      ''',
        [accountIdVal],
      );

      // 删除话题
      await _db.delete(
        kTableName,
        where: '$columnAccountId = ?',
        whereArgs: [accountIdVal],
      );
      return true;
    } catch (e) {
      BaseDb.log.error(
        'TopicDb - deleteAll failed: accountId = $accountIdVal, error = $e',
      );
      return false;
    }
  }

  // 更新已读计数
  Future<bool> updateRead(int topicId, int value) async {
    return _updateCounter(topicId, columnRead, value);
  }

  // 更新接收计数
  Future<bool> updateRecv(int topicId, int value) async {
    return _updateCounter(topicId, columnRecv, value);
  }

  // 通用计数器更新
  Future<bool> _updateCounter(int topicId, String column, int value) async {
    try {
      var rowsAffected = await _db.update(
        kTableName,
        {column: value},
        where: '$columnId = ?',
        whereArgs: [topicId],
      );
      return rowsAffected > 0;
    } catch (e) {
      BaseDb.log.error(
        'TopicDb - updateCounter failed: topicId = $topicId, error = $e',
      );
      return false;
    }
  }
}

class StoredTopic {
  int? id;
  DateTime? lastUsed;
  int? minLocalSeq;
  int? maxLocalSeq;
  BaseDbStatus status = BaseDbStatus.undefined;
  int? nextUnsentId;

  static bool isAllDataLoaded(Topic? topic) {
    if (topic == null) return false;
    if ((topic.seq ?? -1) == 0) return true;
    if (topic.payload is! StoredTopic) return false;
    var st = topic.payload as StoredTopic;
    return (st.minLocalSeq ?? -1) == 1;
  }
}
