import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:tinode/src/topic_db.dart';
import 'package:tinode/tinode.dart';
import 'base_db.dart';
import 'models/drafty.dart';
import 'models/msg_range.dart';
import 'models/stored_message.dart';

class MessageDbError implements Exception {
  final String message;

  MessageDbError.data(String msg) : message = 'data error: $msg';

  MessageDbError.db(String msg) : message = 'db error: $msg';

  @override
  String toString() {
    return 'MessageDb $message';
  }
}

class MessageDb {
  static const String kTableName = 'messages';
  static const int kMessagePreviewLength = 80;

  final Database _db;
  final BaseDb _baseDb;

  // 表字段名
  static const String colId = 'id';
  static const String colTopicId = 'topic_id';
  static const String colUserId = 'user_id';
  static const String colStatus = 'status';
  static const String colSender = 'sender';
  static const String colTs = 'ts';
  static const String colSeq = 'seq';
  static const String colHigh = 'high';
  static const String colDelId = 'del_id';
  static const String colReplSeq = 'repl_seq';
  static const String colEffectiveSeq = 'effective_seq';
  static const String colEffectiveTs = 'effective_ts';
  static const String colHead = 'head';
  static const String colContent = 'content';

  MessageDb(this._db, this._baseDb);

  // 删除表
  Future<void> destroyTable() async {
    await _db.execute('DROP INDEX IF EXISTS idx_topic_effective_seq_desc');
    await _db.execute('DROP INDEX IF EXISTS idx_topic_seq_desc');
    await _db.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表
  Future<void> createTable() async {
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colTopicId INTEGER REFERENCES topics(id),
        $colUserId INTEGER REFERENCES users(id),
        $colStatus INTEGER,
        $colSender TEXT,
        $colTs INTEGER,
        $colSeq INTEGER,
        $colHigh INTEGER,
        $colDelId INTEGER,
        $colReplSeq INTEGER,
        $colEffectiveSeq INTEGER,
        $colEffectiveTs INTEGER,
        $colHead TEXT,
        $colContent TEXT
      )
    ''');
    // 创建索引
    await _db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_topic_seq_desc 
      ON $kTableName ($colTopicId, $colSeq DESC)
    ''');
    await _db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_topic_effective_seq_desc 
      ON $kTableName ($colTopicId, $colEffectiveSeq DESC)
      WHERE $colEffectiveSeq IS NOT NULL
    ''');
  }

  // 清空表
  Future<void> truncateTable(DatabaseExecutor db) async {
    await db.delete(kTableName);
  }

  // 插入原始数据（内部方法）
  Future<int> _insertRaw({
    required Topic topic,
    required StoredMessage msg,
    int? effectiveSeqId,
    DateTime? effectiveTs,
  }) async {
    final topicDb = _baseDb.topicDb;
    final userDb = _baseDb.userDb;
    if (topicDb == null || userDb == null) {
      throw MessageDbError.db('topicDb或userDb未初始化');
    }

    // 补全用户ID
    if (msg.userId == null || msg.userId! <= 0) {
      msg.userId = await userDb.getId(msg.from);
    }

    // 校验必要参数
    if (msg.topicId == null ||
        msg.userId == null ||
        msg.topicId! <= 0 ||
        msg.userId! <= 0) {
      throw MessageDbError.data('无效的topicId或userId');
    }

    // 处理状态和序号
    var status = BaseDbStatus.undefined;
    if (msg.seq != null && msg.seq! > 0) {
      status = BaseDbStatus.synced;
    } else {
      msg.seq = await topicDb.getNextUnusedSeq(topic);
      status = (msg.dbStatus == null || msg.dbStatus == BaseDbStatus.undefined)
          ? BaseDbStatus.queued
          : msg.dbStatus!;
      effectiveSeqId ??= msg.seq;
    }

    // 构建插入数据
    final values = {
      colTopicId: msg.topicId,
      colUserId: msg.userId,
      colStatus: status.value,
      colSender: msg.from,
      colTs: msg.ts?.millisecondsSinceEpoch,
      colSeq: msg.seq,
      colReplSeq: msg.seq, // 简化处理，实际需关联原replSeq
      colEffectiveSeq: effectiveSeqId,
      colEffectiveTs: effectiveTs?.millisecondsSinceEpoch,
      colHead: msg.head != null ? jsonEncode(msg.head) : null,
      colContent: msg.serializeContent(),
    };

    // 执行插入
    final msgId = await _db.insert(kTableName, values);
    msg.msgId = msgId;
    return msgId;
  }

  // 获取有效版本消息
  Future<Map<String, dynamic>?> _getActiveVersion({
    required int effSeq,
    required int topicId,
  }) async {
    final result = await _db.query(
      kTableName,
      where: '$colTopicId = ? AND $colEffectiveSeq = ?',
      whereArgs: [topicId, effSeq],
    );
    return result.isNotEmpty ? result.first : null;
  }

  // 停用消息版本
  Future<void> _deactivateMessageVersion({
    required int seqId,
    required int topicId,
  }) async {
    await _db.update(
      kTableName,
      {colEffectiveSeq: null},
      where: '$colTopicId = ? AND $colEffectiveSeq = ?',
      whereArgs: [topicId, seqId],
    );
  }

  // 激活消息版本
  Future<bool> _activateMessageVersion({
    required int seqId,
    DateTime? effectiveTs,
    required int topicId,
    String? originalAuthor,
  }) async {
    final result = await _db.query(
      kTableName,
      columns: [colId],
      where: '$colTopicId = ? AND $colReplSeq = ? AND $colSender = ?',
      whereArgs: [topicId, seqId, originalAuthor],
      orderBy: '$colSeq DESC',
      limit: 1,
    );
    if (result.isEmpty) return false;

    final recId = result.first[colId] as int;
    final rowsAffected = await _db.update(
      kTableName,
      {
        colEffectiveSeq: seqId,
        colEffectiveTs: effectiveTs?.millisecondsSinceEpoch,
      },
      where: '$colId = ?',
      whereArgs: [recId],
    );
    return rowsAffected > 0;
  }

  // 插入消息（核心方法）
  Future<int> insert({required Topic topic, required StoredMessage msg}) async {
    if (msg.msgId > 0) return msg.msgId; // 已保存

    // 获取topicId
    final topicId = msg.topicId ?? await _baseDb.topicDb?.getId(msg.topic);
    if (topicId == null || topicId <= 0) return -1;
    msg.topicId = topicId;

    // 使用事务处理
    try {
      return await _db.transaction((txn) async {
        int? effSeq;
        DateTime? effTs;

        // 处理消息替换逻辑
        if (msg.seq != null) {
          final replaceSeq = msg.seq;
          if (replaceSeq != null) {
            final orig = await _getActiveVersion(
              effSeq: replaceSeq,
              topicId: topicId,
            );
            if (orig != null && msg.from == orig[colSender] as String?) {
              await _deactivateMessageVersion(
                seqId: replaceSeq,
                topicId: topicId,
              );
              effSeq = replaceSeq;
              effTs = orig[colEffectiveTs] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      orig[colEffectiveTs] as int,
                    )
                  : null;
            }
          }
        } else {
          // 非替换消息逻辑
          effSeq = msg.seq;
          effTs = msg.ts;
          if (effSeq != null) {
            final activated = await _activateMessageVersion(
              seqId: effSeq,
              effectiveTs: effTs,
              topicId: topicId,
              originalAuthor: msg.from,
            );
            if (activated) effSeq = null;
          }
        }

        // 执行插入
        return await _insertRaw(
          topic: topic,
          msg: msg,
          effectiveSeqId: effSeq,
          effectiveTs: effTs,
        );
      });
    } catch (e) {
      BaseDb.log.error('插入消息失败: $e');
      return -1;
    }
  }

  // 更新消息状态和内容
  Future<bool> updateStatusAndContent({
    required int msgId,
    BaseDbStatus? status,
    Drafty? content,
  }) async {
    final values = <String, dynamic>{};
    if (status != null && status != BaseDbStatus.undefined) {
      values[colStatus] = status.value;
    }
    if (content != null) {
      values[colContent] = json.encode(content);
    }
    if (values.isEmpty) return false;

    final rowsAffected = await _db.update(
      kTableName,
      values,
      where: '$colId = ?',
      whereArgs: [msgId],
    );
    return rowsAffected > 0;
  }

  // 标记消息已送达
  Future<bool> delivered({
    required int msgId,
    required DateTime ts,
    required int seq,
  }) async {
    final rowsAffected = await _db.update(
      kTableName,
      {
        colStatus: BaseDbStatus.synced.value,
        colTs: ts.millisecondsSinceEpoch,
        colSeq: seq,
        colEffectiveSeq: seq, // 简化处理，实际需关联replSeq
        colEffectiveTs: ts.millisecondsSinceEpoch,
      },
      where: '$colId = ?',
      whereArgs: [msgId],
    );
    return rowsAffected > 0;
  }

  // 删除指定主题的所有消息
  Future<bool> deleteAll({required int topicId}) async {
    final rowsAffected = await _db.delete(
      kTableName,
      where: '$colTopicId = ?',
      whereArgs: [topicId],
    );
    return rowsAffected > 0;
  }

  Future<bool> deleteFailed(int topicId) async {
    try {
      final deleted = await _db.delete(
        kTableName,
        where: '$colTopicId = ? AND $colStatus = ?',
        whereArgs: [topicId, BaseDbStatus.failed.value],
      );
      return deleted > 0;
    } catch (e) {
      BaseDb.log.error(
        'MessageDb[topicId = $topicId] - deleteFailed failed: $e',
      );
      return false;
    }
  }

  Future<bool> deleteByMsgId(int msgId) async {
    try {
      var deletedRows = await _db.delete(
        kTableName,
        where: '$colId = ?',
        whereArgs: [msgId],
      );
      return deletedRows > 0;
    } catch (e) {
      if (e is DatabaseException) {
        BaseDb.log.error(
          'MessageDb[msgId = $msgId] - delete SQLite error: code = ${e.hashCode}, error = ${e.toString()}',
        );
      } else {
        BaseDb.log.error(
          'MessageDb - delete operation failed: msgId = $msgId, error = ${e.toString()}',
        );
      }
      return false;
    }
  }

  Future<bool> deleteInTopic({required int topicId, required int seqId}) async {
    try {
      var deletedRows = await _db.delete(
        kTableName,
        where: '$colTopicId = ? AND $colSeq = ?',
        whereArgs: [topicId, seqId],
      );
      return deletedRows > 0;
    } catch (e) {
      if (e is DatabaseException) {
        print(
          'MessageDb[topicId = $topicId, seq = $seqId] - delete SQLite error: code = ${e.hashCode}, error = $e',
        );
      } else {
        print(
          'MessageDb - delete operation failed: topicId = $topicId, seq = $seqId, error = ${e.toString()}',
        );
      }
      return false;
    }
  }

  Future<bool> delete({
    required int topicId,
    int? delId,
    required int loId,
    int? hiId,
  }) async {
    return deleteOrMarkDeleted(
      topicId: topicId,
      delId: delId,
      from: loId,
      to: hiId,
      hard: false,
    );
  }

  Future<bool> deleteOrMarkDeletedWithRanges({
    required int topicId,
    int? delId,
    required List<MsgRange> ranges,
    required bool hard,
  }) async {
    const savepointName = 'MessageDb.deleteOrMarkDeleted-ranges';
    try {
      await _db.transaction((txn) async {
        await txn.execute('SAVEPOINT $savepointName');
        try {
          for (final range in ranges) {
            final result = await deleteOrMarkDeleted(
              topicId: topicId,
              delId: delId,
              from: range.lower,
              to: range.upper,
              hard: hard,
            );

            if (!result) {
              throw MessageDbError.db(
                'Failed to process: delId ${delId ?? -1} range: $range',
              );
            }
          }
          await txn.execute('RELEASE SAVEPOINT $savepointName');
          return true;
        } catch (e) {
          await txn.execute('ROLLBACK TO SAVEPOINT $savepointName');
          return false;
        }
      });
    } on DatabaseException catch (e) {
      BaseDb.log.error(
        'MessageDb[topicId = $topicId] - deleteOrMarkDeleted SQLite error: code = ${e.hashCode}, error = ${e.toString()}',
      );
    } catch (e) {
      BaseDb.log.error(
        'MessageDb - deleteOrMarkDeleted2 with ranges failed: topicId = $topicId, error = ${e.toString()}',
      );
    }

    return true;
  }

  Future<bool> deleteOrMarkDeleted({
    required int topicId,
    int? delId,
    required int from,
    int? to,
    required bool hard,
  }) async {
    // 参数处理
    final actualDelId = delId ?? 0;
    var startId = from;
    var endId = to ?? ((1 << 63) - 1);
    if (endId == 0) {
      endId = startId + 1;
    }
    const savepointName = 'MessageDb.deleteOrMarkDeleted-plain';

    try {
      var updateResult = false;

      // 开启事务并创建保存点
      await _db.transaction((txn) async {
        // 创建保存点
        await txn.execute('SAVEPOINT $savepointName');

        try {
          // 1. 构建各种查询条件
          // 消息选择器：指定主题中seq在[startId, endId)范围内且状态<=synced的消息
          final messageSelectorWhere =
              '''
            $colTopicId = ? AND ? <= $colSeq AND $colSeq < ? AND $colStatus <= ?
          ''';
          final messageSelectorArgs = [
            topicId,
            startId,
            endId,
            BaseDbStatus.synced.value,
          ];

          // 范围删除选择器：状态>=deletedHard的记录
          final rangeDeleteWhere =
              '''
            $colTopicId = ? AND ? <= $colSeq AND $colSeq < ? AND $colStatus >= ?
          ''';
          final rangeDeleteArgs = [
            topicId,
            startId,
            endId,
            BaseDbStatus.deletedHard.value,
          ];

          // 有效序列选择器：effectiveSeq在[startId, endId)范围内的记录
          final effectiveSeqWhere =
              '''
            $colTopicId = ? AND ? <= $colEffectiveSeq AND $colEffectiveSeq < ?
          ''';
          final effectiveSeqArgs = [topicId, startId, endId];

          // 确定状态类型
          final BaseDbStatus statusToConsume;
          if (actualDelId > 0) {
            statusToConsume = BaseDbStatus.deletedSynced;
          } else {
            statusToConsume = hard
                ? BaseDbStatus.deletedHard
                : BaseDbStatus.deletedSoft;
          }

          // 部分重叠删除范围选择器
          var rangeConsumeWhere =
              '''
            $colTopicId = ? AND $colStatus = ?
          ''';
          var rangeConsumeArgs = [topicId, statusToConsume.value];

          if (actualDelId > 0) {
            rangeConsumeWhere += ' AND $colDelId < ?';
            rangeConsumeArgs.add(actualDelId);
          }

          // 重叠选择器：与当前范围有部分重叠的记录
          final overlapWhere =
              '''
            $rangeConsumeWhere AND $colHigh >= ? AND $colSeq <= ?
          ''';
          final overlapArgs = [...rangeConsumeArgs, startId, endId];

          // 2. 执行删除和更新操作
          // 删除符合条件的消息
          await txn.delete(
            kTableName,
            where: messageSelectorWhere,
            whereArgs: messageSelectorArgs,
          );

          // 删除符合条件的范围记录
          await txn.delete(
            kTableName,
            where: rangeDeleteWhere,
            whereArgs: rangeDeleteArgs,
          );

          // 更新有效序列为null
          await txn.update(
            kTableName,
            {colEffectiveSeq: null},
            where: effectiveSeqWhere,
            whereArgs: effectiveSeqArgs,
          );

          // 3. 查询重叠范围的最大连续范围
          final overlapQuery =
              '''
            SELECT MIN($colSeq) as minSeq, MAX($colHigh) as maxHigh 
            FROM $kTableName 
            WHERE $overlapWhere
          ''';
          final List<Map<String, dynamic>> overlapResult = await txn.rawQuery(
            overlapQuery,
            overlapArgs,
          );

          if (overlapResult.isNotEmpty) {
            final row = overlapResult.first;
            if (row['minSeq'] != null && row['minSeq'] < startId) {
              startId = row['minSeq'] as int;
            }
            if (row['maxHigh'] != null && row['maxHigh'] > endId) {
              endId = row['maxHigh'] as int;
            }
          }

          // 4. 删除部分重叠的范围记录（将被新范围替代）
          await txn.delete(
            kTableName,
            where: overlapWhere,
            whereArgs: overlapArgs,
          );

          // 5. 插入新的范围记录
          final newRange = {
            colTopicId: topicId,
            colDelId: actualDelId,
            colSeq: startId,
            colHigh: endId,
            colStatus: statusToConsume.value,
            // 可根据需要添加其他字段
          };

          final insertId = await txn.insert(kTableName, newRange);
          updateResult = insertId != -1;

          // 提交保存点
          await txn.execute('RELEASE SAVEPOINT $savepointName');
        } catch (e) {
          // 回滚到保存点
          await txn.execute('ROLLBACK TO SAVEPOINT $savepointName');
          rethrow;
        }
      });

      return updateResult;
    } on DatabaseException catch (e) {
      // 释放保存点并处理SQL错误
      await _db.execute('RELEASE SAVEPOINT $savepointName');
      print(
        'MessageDb[topicId = $topicId] - markDeleted SQLite error: code = ${e.hashCode}, error = $e',
      );
      return false;
    } catch (e) {
      // 释放保存点并处理其他错误
      await _db.execute('RELEASE SAVEPOINT $savepointName');
      print(
        'MessageDb - markDeleted operation failed: topicId = $topicId, error = ${e.toString()}',
      );
      return false;
    }
  }

  // 查询消息（核心查询方法）
  Future<List<StoredMessage>?> query({
    required int topicId,
    required int from,
    required int limit,
    required bool forward,
  }) async {
    final whereClause = forward
        ? '$colTopicId = ? AND $colEffectiveSeq > ? AND $colEffectiveSeq IS NOT NULL'
        : '$colTopicId = ? AND $colEffectiveSeq < ? AND $colEffectiveSeq IS NOT NULL';
    final orderBy = forward ? '$colEffectiveSeq ASC' : '$colEffectiveSeq DESC';

    final result = await _db.query(
      kTableName,
      where: whereClause,
      whereArgs: [topicId, from],
      orderBy: orderBy,
      limit: limit,
    );

    return result.map((row) => _readOne(row)).toList();
  }

  Future<StoredMessage?> queryByMsgId({
    int? msgId,
    required int previewLen,
  }) async {
    // 如果msgId为null，直接返回null
    if (msgId == null) {
      return null;
    }

    try {
      // 查询指定id的消息记录，获取所有字段
      var rows = await _db.query(
        kTableName,
        where: '$colId = ?',
        whereArgs: [msgId],
        limit: 1, // 只需要一条记录
      );

      // 如果查询到结果，转换为StoredMessage对象
      if (rows.isNotEmpty) {
        return _readOne(rows.first);
      }
      return null;
    } catch (e) {
      BaseDb.log.error('MessageDb - query failed for msgId: $msgId, error: $e');
      return null;
    }
  }

  Future<List<StoredMessage>?> queryUnsent(int? topicId) async {
    // 构建查询条件
    var whereClauses = <String>[];
    var whereArgs = <dynamic>[];

    // 添加topicId条件
    if (topicId != null) {
      whereClauses.add('$colTopicId = ?');
      whereArgs.add(topicId);
    } else {
      // 如果topicId为null，可能需要查询所有topic的未发送消息
      // 或者根据业务需求返回null
    }

    // 添加状态条件：只查询状态为queued的消息
    whereClauses.add('$colStatus = ?');
    whereArgs.add(BaseDbStatus.queued.value);

    var whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      var rows = await _db.query(
        kTableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: colTs, // 按ts字段排序
      );

      // 转换结果为StoredMessage列表
      var messages = rows.map((row) {
        return _readOne(row);
      }).toList();

      return messages;
    } catch (e) {
      // 错误处理
      var errorMsg = e.toString();
      var errorCode = 0;

      if (e is DatabaseException) {
        errorCode = e.hashCode;
      }

      print(
        'MessageDb[topicId = $topicId] - queryUnsent error: code = $errorCode, error = $errorMsg',
      );
      return null;
    }
  }

  Future<List<MsgRange>?> queryDeleted(int? topicId, bool hard) async {
    // 验证topicId不为null
    if (topicId == null) {
      return null;
    }

    // 确定要查询的状态
    final status = hard ? BaseDbStatus.deletedHard : BaseDbStatus.deletedSoft;

    try {
      // 执行查询
      List<Map<String, dynamic>> rows = await _db.query(
        kTableName,
        columns: [colDelId, colSeq, colHigh], // 选择需要的字段
        where: '$colTopicId = ? AND $colStatus = ?',
        whereArgs: [topicId, status.value],
        orderBy: colSeq, // 按seq排序
      );

      // 转换结果为MsgRange列表
      var ranges = <MsgRange>[];
      for (var row in rows) {
        final low = row[colSeq] as int?;
        if (low != null) {
          ranges.add(MsgRange(low: low, hi: row[colHigh] as int?));
        }
      }

      return ranges;
    } catch (e) {
      // 错误处理
      var errorMsg = e.toString();
      var errorCode = 0;

      if (e is DatabaseException) {
        errorCode = e.hashCode;
      }

      BaseDb.log.error(
        'MessageDb[topicId = $topicId] - queryDelete SQLite error: code = $errorCode, error = $errorMsg',
      );
      return null;
    }
  }

  Future<List<StoredMessage>?> queryLatest() async {
    // 获取话题数据库实例
    final topicDb = _baseDb.topicDb;
    if (topicDb == null) {
      return null;
    }

    // 构建SQL查询语句，实现表连接和过滤逻辑
    // 这里使用原始SQL是因为涉及到自连接和复杂条件，比sqflite的query方法更直观
    final sql =
        '''
      SELECT m1.*, ${TopicDb.kTableName}.${topicDb.columnTopic} 
      FROM $kTableName m1
      LEFT OUTER JOIN $kTableName m2 
        ON m1.$colTopicId = m2.$colTopicId 
        AND m1.$colEffectiveSeq < m2.$colEffectiveSeq
      LEFT OUTER JOIN ${TopicDb.kTableName} 
        ON m1.$colTopicId = ${TopicDb.kTableName}.${topicDb.columnId}
      WHERE m1.$colDelId IS NULL 
        AND m2.$colDelId IS NULL 
        AND m2.id IS NULL 
        AND m1.$colEffectiveSeq IS NOT NULL
    ''';

    try {
      // 执行查询
      final List<Map<String, dynamic>> rows = await _db.rawQuery(sql);

      // 转换结果为StoredMessage列表
      final messages = <StoredMessage>[];
      for (final row in rows) {
        final sm = _readOne(row);
        sm.topic = row[topicDb.columnTopic] as String?;
        messages.add(sm);
      }

      return messages;
    } catch (e) {
      BaseDb.log.error('MessageDb - queryLatest SQLite error: $e');
      return null;
    }
  }

  Future<List<StoredMessage>?> queryByTopicIdAndFromAndLimitAndForward(
    int? topicId,
    int from,
    int limit,
    bool forward,
  ) async {
    // 验证topicId不为null
    if (topicId == null) {
      return null;
    }

    // 构建查询条件
    final whereClauses = <String>[
      '$colTopicId = ?', // 匹配话题ID
      '$colEffectiveSeq IS NOT NULL', // 有效序列不为null
    ];
    final whereArgs = <dynamic>[topicId];

    // 根据查询方向添加序列范围条件
    if (forward) {
      whereClauses.add('$colEffectiveSeq > ?');
      whereArgs.add(from);
    } else {
      whereClauses.add('$colEffectiveSeq < ?');
      whereArgs.add(from);
    }

    final whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      final List<Map<String, dynamic>> rows = await _db.query(
        kTableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: forward
            ? '$colEffectiveSeq ASC' // 正向查询按序列升序
            : '$colEffectiveSeq DESC', // 反向查询按序列降序
        limit: limit,
      );

      // 转换结果为StoredMessage列表
      final messages = rows.map((row) {
        return _readOne(row);
      }).toList();

      return messages;
    } catch (e) {
      BaseDb.log.error(
        'MessageDb[topicId = $topicId] - query SQLite error: $e',
      );
      return null;
    }
  }

  Future<StoredMessage?> getMessage(int topicId, int seqId) async {
    try {
      // 查询指定话题ID和有效序列的消息
      List<Map<String, dynamic>> rows = await _db.query(
        kTableName,
        where: '$colTopicId = ? AND $colEffectiveSeq = ?',
        whereArgs: [topicId, seqId],
        limit: 1, // 只需要一条匹配的记录
      );

      // 如果查询到结果，转换为StoredMessage对象
      if (rows.isNotEmpty) {
        return _readOne(rows.first);
      }
      return null;
    } catch (e) {
      BaseDb.log.error(
        'MessageDb - getMessage failed: topicId = $topicId, seqId = $seqId, error: $e',
      );
      return null;
    }
  }

  Future<List<int>?> getAllVersions(int topicId, int seqId, int? limit) async {
    // 构建查询条件
    final whereClause = '$colTopicId = ? AND $colReplSeq = ?';
    final whereArgs = [topicId, seqId];

    try {
      // 执行查询
      final rows = await _db.query(
        kTableName,
        columns: [colSeq],
        // 只查询seq字段
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: '$colSeq DESC',
        // 按seq降序排列
        limit: limit, // 可选的限制数量
      );

      // 提取seq值列表
      final seqIds = <int>[];
      for (final row in rows) {
        final seq = row[colSeq] as int?;
        if (seq != null) {
          seqIds.add(seq);
        }
      }

      return seqIds;
    } catch (e) {
      // 错误处理

      BaseDb.log.error(
        'MessageDb[topicId = $topicId] - getAllVersions SQLite error: $e',
      );
      return null;
    }
  }

  // 将查询结果转换为StoredMessage
  StoredMessage _readOne(Map<String, dynamic> row) {
    final msg = StoredMessage();
    msg.msgId = row[colId] as int;
    msg.topicId = row[colTopicId] as int?;
    msg.userId = row[colUserId] as int?;
    msg.dbStatus = BaseDbStatus.fromValue(row[colStatus] as int? ?? 0);
    msg.from = row[colSender] as String?;

    // 处理时间
    final effTs = row[colEffectiveTs] as int?;
    final ts = row[colTs] as int?;
    msg.ts = effTs != null
        ? DateTime.fromMillisecondsSinceEpoch(effTs)
        : (ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null);

    msg.seq = row[colEffectiveSeq] as int? ?? row[colSeq] as int?;
    msg.head = row[colHead] != null ? jsonDecode(row[colHead] as String) : null;
    msg.deserializeContent(row[colContent]);

    return msg;
  }

  Future<List<MsgRange>> getCachedRanges(
    int? topicId,
    List<MsgRange> ranges,
  ) async {
    // 构建查询条件
    var whereClauses = <String>[];
    var whereArgs = <dynamic>[];

    // 添加topicId条件
    if (topicId != null) {
      whereClauses.add('$colTopicId = ?');
      whereArgs.add(topicId);
    } else {
      // 如果topicId为null，可能需要特殊处理或返回空列表
      return [];
    }

    // 构建范围查询条件
    var rangeConditions = <String>[];
    for (var r in ranges) {
      if (r.hi != null) {
        // 处理r.hi不为null的情况
        // Find deleted ranges
        rangeConditions.add('($colSeq < ? AND $colHigh > ?)');
        whereArgs.add(r.hi);
        whereArgs.add(r.low);

        // Find normal entries
        rangeConditions.add(
          '($colSeq < ? AND $colSeq >= ? AND $colHigh IS NULL)',
        );
        whereArgs.add(r.hi);
        whereArgs.add(r.low);
      } else {
        // 处理r.hi为null的情况
        // Find deleted ranges
        rangeConditions.add('($colSeq <= ? AND $colHigh > ?)');
        whereArgs.add(r.low);
        whereArgs.add(r.low);

        // Find normal entries
        rangeConditions.add('($colSeq = ? AND $colHigh IS NULL)');
        whereArgs.add(r.low);
      }
    }

    if (rangeConditions.isNotEmpty) {
      whereClauses.add('(' + rangeConditions.join(' OR ') + ')');
    }

    var whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      List<Map<String, dynamic>> rows = await _db.query(
        kTableName, // 替换为实际表名
        columns: [colSeq, colHigh],
        where: whereClause,
        whereArgs: whereArgs,
      );

      // 转换结果为MsgRange列表
      var found = rows.map((row) {
        return MsgRange(low: row[colSeq] as int, hi: row[colHigh] as int?);
      }).toList();

      // 排序并合并范围
      found.sort((a, b) => a.low.compareTo(b.low));
      return MsgRange.collapse(found);
    } catch (e) {
      // 错误处理
      var errorMsg = e.toString();
      var errorCode = 0; // sqflite不直接提供错误代码，可能需要从异常中解析

      // 简单的错误代码解析示例
      if (e is DatabaseException) {
        errorCode = e.hashCode ?? 0;
      }

      BaseDb.log.error(
        'MessageDb[topicId = $topicId] - getCachedRanges error: code = $errorCode, error = $errorMsg',
      );
      return [];
    }
  }

  Future<List<MsgRange>> getMissingRanges(
    int? topicId,
    int startFrom,
    int pageSize,
    bool newer,
  ) async {
    // 构建查询条件
    var whereClauses = <String>[];
    var whereArgs = <dynamic>[];

    // 添加topicId条件
    if (topicId != null) {
      whereClauses.add('$colTopicId = ?');
      whereArgs.add(topicId);
    } else {
      return []; // topicId为null时返回空列表
    }

    // 构建核心条件：newer ? ((high ?? (seq + 1)) > startFrom) : ((high ?? (seq + 1)) < startFrom)
    // 在SQL中使用CASE表达式实现null处理和比较逻辑
    var condition = newer
        ? '(CASE WHEN $colHigh IS NULL THEN $colSeq + 1 ELSE $colHigh END) > ?'
        : '(CASE WHEN $colHigh IS NULL THEN $colSeq + 1 ELSE $colHigh END) < ?';

    whereClauses.add(condition);
    whereArgs.add(startFrom);

    var whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      List<Map<String, dynamic>> rows = await _db.query(
        kTableName,
        columns: [colSeq, colHigh],
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: newer ? '$colSeq ASC' : '$colSeq DESC',
        limit: pageSize,
      );

      // 转换结果为MsgRange列表
      var found = rows.map((row) {
        return MsgRange(low: row[colSeq] as int, hi: row[colHigh] as int?);
      }).toList();

      // 排序、合并并计算间隙范围
      found.sort((a, b) => a.low.compareTo(b.low));
      return MsgRange.gaps(MsgRange.collapse(found));
    } catch (e) {
      // 错误处理
      var errorMsg = e.toString();
      var errorCode = 0;

      if (e is DatabaseException) {
        errorCode = e.hashCode;
      }

      BaseDb.log.error(
        'MessageDb[topicId = $topicId] - getMissingRanges error: code = $errorCode, error = $errorMsg',
      );
      return [];
    }
  }
}
