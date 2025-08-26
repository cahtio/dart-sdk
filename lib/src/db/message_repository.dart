import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import 'package:tinode/src/db/repository.dart';
import 'package:tinode/src/db/topic_repository.dart';
import 'package:tinode/src/db/user_repository.dart';
import 'package:tinode/src/topic.dart';
import 'package:tinode/src/models/message_stored.dart';
import 'package:tinode/src/models/drafty.dart';
import 'package:tinode/src/models/msg_range.dart';

class MessageRepositoryError implements Exception {
  final String message;

  MessageRepositoryError.data(String msg) : message = 'Data Error: $msg';

  MessageRepositoryError.db(String msg) : message = 'Database Error: $msg';

  @override
  String toString() {
    return 'MessageRepository $message';
  }
}

class MessageRepository extends Repository {
  static const String kTableName = 'messages';
  static const int kMessagePreviewLength = 80;

  // 表字段名
  static const String kColumnId = 'id';
  static const String kColumnTopicId = 'topic_id';
  static const String kColumnUserId = 'user_id';
  static const String kColumnStatus = 'status';
  static const String kColumnSender = 'sender';
  static const String kColumnTs = 'ts';
  static const String kColumnSeq = 'seq';
  static const String kColumnHigh = 'high';
  static const String kColumnDelId = 'del_id';
  static const String kColumnReplSeq = 'repl_seq';
  static const String kColumnEffectiveSeq = 'effective_seq';
  static const String kColumnEffectiveTs = 'effective_ts';
  static const String kColumnHead = 'head';
  static const String kColumnContent = 'content';

  late UserRepository _userRepository;
  late TopicRepository _topicRepository;

  MessageRepository() {
    _userRepository = GetIt.I.get<UserRepository>();
    _topicRepository = GetIt.I.get<TopicRepository>();
  }

  // 删除表
  Future<void> destroyTable(DatabaseExecutor dbe) async {
    await dbe.execute('DROP INDEX IF EXISTS idx_topic_effective_seq_desc');
    await dbe.execute('DROP INDEX IF EXISTS idx_topic_seq_desc');
    await dbe.execute('DROP TABLE IF EXISTS $kTableName');
  }

  // 创建表
  Future<void> createTable(DatabaseExecutor dbe) async {
    await dbe.execute('''
      CREATE TABLE IF NOT EXISTS $kTableName (
        $kColumnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $kColumnTopicId INTEGER REFERENCES topics(id),
        $kColumnUserId INTEGER REFERENCES users(id),
        $kColumnStatus INTEGER,
        $kColumnSender TEXT,
        $kColumnTs INTEGER,
        $kColumnSeq INTEGER,
        $kColumnHigh INTEGER,
        $kColumnDelId INTEGER,
        $kColumnReplSeq INTEGER,
        $kColumnEffectiveSeq INTEGER,
        $kColumnEffectiveTs INTEGER,
        $kColumnHead TEXT,
        $kColumnContent TEXT
      )
    ''');
    // 创建索引
    await dbe.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_topic_seq_desc 
      ON $kTableName ($kColumnTopicId, $kColumnSeq DESC)
    ''');
    await dbe.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_topic_effective_seq_desc 
      ON $kTableName ($kColumnTopicId, $kColumnEffectiveSeq DESC)
      WHERE $kColumnEffectiveSeq IS NOT NULL
    ''');
  }

  // 清空表
  Future<void> truncateTable(DatabaseExecutor db) async {
    await db.delete(kTableName);
  }

  // 插入原始数据（内部方法）
  Future<int> _insertRaw(
    DatabaseExecutor dbe,
    Topic topic,
    MessageStored msg, {
    int? effectiveSeqId,
    DateTime? effectiveTs,
  }) async {
    // 补全用户ID
    if (msg.userId == null || msg.userId! <= 0) {
      msg.userId = await _userRepository.getId(dbe, msg.from);
    }

    // 校验必要参数
    if (msg.topicId == null ||
        msg.userId == null ||
        msg.topicId! <= 0 ||
        msg.userId! <= 0) {
      throw MessageRepositoryError.data('无效的topicId或userId');
    }

    // 处理状态和序号
    var status = RepositoryStatus.undefined;
    if (msg.seq != null && msg.seq! > 0) {
      status = RepositoryStatus.synced;
    } else {
      msg.seq = await _topicRepository.getNextUnusedSeq(dbe, topic);
      status =
          (msg.dbStatus == null || msg.dbStatus == RepositoryStatus.undefined)
          ? RepositoryStatus.queued
          : msg.dbStatus!;
      effectiveSeqId ??= msg.seq;
    }

    // 构建插入数据
    final values = {
      kColumnTopicId: msg.topicId,
      kColumnUserId: msg.userId,
      kColumnStatus: status.value,
      kColumnSender: msg.from,
      kColumnTs: msg.ts?.millisecondsSinceEpoch,
      kColumnSeq: msg.seq,
      kColumnReplSeq: msg.seq, // 简化处理，实际需关联原replSeq
      kColumnEffectiveSeq: effectiveSeqId,
      kColumnEffectiveTs: effectiveTs?.millisecondsSinceEpoch,
      kColumnHead: msg.head != null ? jsonEncode(msg.head) : null,
      kColumnContent: msg.serializeContent(),
    };

    // 执行插入
    final msgId = await dbe.insert(kTableName, values);
    msg.msgId = msgId;
    return msgId;
  }

  // 获取有效版本消息
  Future<Map<String, dynamic>?> _getActiveVersion(
    DatabaseExecutor dbe,
    int effSeq,
    int topicId,
  ) async {
    final result = await dbe.query(
      kTableName,
      where: '$kColumnTopicId = ? AND $kColumnEffectiveSeq = ?',
      whereArgs: [topicId, effSeq],
    );
    return result.isNotEmpty ? result.first : null;
  }

  // 停用消息版本
  Future<void> _deactivateMessageVersion(
    DatabaseExecutor dbe,
    int seqId,
    int topicId,
  ) async {
    await dbe.update(
      kTableName,
      {kColumnEffectiveSeq: null},
      where: '$kColumnTopicId = ? AND $kColumnEffectiveSeq = ?',
      whereArgs: [topicId, seqId],
    );
  }

  // 激活消息版本
  Future<bool> _activateMessageVersion(
    DatabaseExecutor dbe,
    int seqId,
    int topicId, {
    DateTime? effectiveTs,
    String? originalAuthor,
  }) async {
    final result = await dbe.query(
      kTableName,
      columns: [kColumnId],
      where:
          '$kColumnTopicId = ? AND $kColumnReplSeq = ? AND $kColumnSender = ?',
      whereArgs: [topicId, seqId, originalAuthor],
      orderBy: '$kColumnSeq DESC',
      limit: 1,
    );
    if (result.isEmpty) return false;

    final recId = result.first[kColumnId] as int;
    final rowsAffected = await dbe.update(
      kTableName,
      {
        kColumnEffectiveSeq: seqId,
        kColumnEffectiveTs: effectiveTs?.millisecondsSinceEpoch,
      },
      where: '$kColumnId = ?',
      whereArgs: [recId],
    );
    return rowsAffected > 0;
  }

  // 插入消息（核心方法）
  Future<int> insert(
    DatabaseExecutor dbe,
    Topic topic,
    MessageStored msg,
  ) async {
    if (msg.msgId > 0) return msg.msgId; // 已保存

    // 获取topicId
    final topicId = msg.topicId ?? await _topicRepository.getId(dbe, msg.topic);
    if (topicId <= 0) return -1;
    msg.topicId = topicId;

    // 使用事务处理
    try {
      return await transaction(dbe, (txn) async {
        int? effSeq;
        DateTime? effTs;

        // 处理消息替换逻辑
        if (msg.seq != null) {
          final replaceSeq = msg.seq;
          if (replaceSeq != null) {
            final orig = await _getActiveVersion(txn, replaceSeq, topicId);
            if (orig != null && msg.from == orig[kColumnSender] as String?) {
              await _deactivateMessageVersion(txn, replaceSeq, topicId);
              effSeq = replaceSeq;
              effTs = orig[kColumnEffectiveTs] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      orig[kColumnEffectiveTs] as int,
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
              dbe,
              effSeq,
              topicId,
              effectiveTs: effTs,
              originalAuthor: msg.from,
            );
            if (activated) effSeq = null;
          }
        }

        // 执行插入
        return await _insertRaw(
          dbe,
          topic,
          msg,
          effectiveSeqId: effSeq,
          effectiveTs: effTs,
        );
      });
    } catch (e) {
      logError('插入消息失败: $e');
      return -1;
    }
  }

  // 更新消息状态和内容
  Future<bool> updateStatusAndContent(
    DatabaseExecutor dbe,
    int msgId, {
    RepositoryStatus? status,
    Drafty? content,
  }) async {
    final values = <String, dynamic>{};
    if (status != null && status != RepositoryStatus.undefined) {
      values[kColumnStatus] = status.value;
    }
    if (content != null) {
      values[kColumnContent] = json.encode(content);
    }
    if (values.isEmpty) return false;

    final rowsAffected = await dbe.update(
      kTableName,
      values,
      where: '$kColumnId = ?',
      whereArgs: [msgId],
    );
    return rowsAffected > 0;
  }

  // 标记消息已送达
  Future<bool> delivered(
    DatabaseExecutor dbe,
    int msgId,
    DateTime ts,
    int seq,
  ) async {
    final rowsAffected = await dbe.update(
      kTableName,
      {
        kColumnStatus: RepositoryStatus.synced.value,
        kColumnTs: ts.millisecondsSinceEpoch,
        kColumnSeq: seq,
        kColumnEffectiveSeq: seq, // 简化处理，实际需关联replSeq
        kColumnEffectiveTs: ts.millisecondsSinceEpoch,
      },
      where: '$kColumnId = ?',
      whereArgs: [msgId],
    );
    return rowsAffected > 0;
  }

  // 删除指定主题的所有消息
  Future<bool> deleteAll(DatabaseExecutor dbe, int topicId) async {
    final rowsAffected = await dbe.delete(
      kTableName,
      where: '$kColumnTopicId = ?',
      whereArgs: [topicId],
    );
    return rowsAffected > 0;
  }

  Future<bool> deleteFailed(DatabaseExecutor dbe, int topicId) async {
    try {
      final deleted = await dbe.delete(
        kTableName,
        where: '$kColumnTopicId = ? AND $kColumnStatus = ?',
        whereArgs: [topicId, RepositoryStatus.failed.value],
      );
      return deleted > 0;
    } catch (e) {
      logError('MessageDb[topicId = $topicId] - deleteFailed failed: $e');
      return false;
    }
  }

  Future<bool> deleteByMsgId(DatabaseExecutor dbe, int msgId) async {
    try {
      var deletedRows = await dbe.delete(
        kTableName,
        where: '$kColumnId = ?',
        whereArgs: [msgId],
      );
      return deletedRows > 0;
    } catch (e) {
      if (e is DatabaseException) {
        logError(
          'MessageDb[msgId = $msgId] - delete SQLite error: code = ${e.hashCode}, error = ${e.toString()}',
        );
      } else {
        logError(
          'MessageDb - delete operation failed: msgId = $msgId, error = ${e.toString()}',
        );
      }
      return false;
    }
  }

  Future<bool> deleteInTopic(
    DatabaseExecutor dbe,
    int topicId,
    int seqId,
  ) async {
    try {
      var deletedRows = await dbe.delete(
        kTableName,
        where: '$kColumnTopicId = ? AND $kColumnSeq = ?',
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

  Future<bool> delete(
    DatabaseExecutor dbe,
    int topicId,
    int? delId,
    int loId,
    int? hiId,
  ) async {
    return deleteOrMarkDeleted(dbe, topicId, delId, loId, hiId, false);
  }

  Future<bool> deleteOrMarkDeletedWithRanges(
    DatabaseExecutor dbe,
    int topicId,
    List<MsgRange> ranges,
    bool hard, {
    int? delId,
  }) async {
    const savepointName = 'MessageDb.deleteOrMarkDeleted-ranges';
    try {
      await transaction(dbe, (txn) async {
        await txn.execute('SAVEPOINT $savepointName');
        try {
          for (final range in ranges) {
            final result = await deleteOrMarkDeleted(
              dbe,
              topicId,
              delId,
              range.lower,
              range.upper,
              hard,
            );

            if (!result) {
              throw MessageRepositoryError.db(
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
      logError(
        'MessageDb[topicId = $topicId] - deleteOrMarkDeleted SQLite error: code = ${e.hashCode}, error = ${e.toString()}',
      );
    } catch (e) {
      logError(
        'MessageDb - deleteOrMarkDeleted2 with ranges failed: topicId = $topicId, error = ${e.toString()}',
      );
    }

    return true;
  }

  Future<bool> deleteOrMarkDeleted(
    DatabaseExecutor dbe,
    int topicId,
    int? delId,
    int from,
    int? to,
    bool hard,
  ) async {
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
      await transaction(dbe, (txn) async {
        // 创建保存点
        await txn.execute('SAVEPOINT $savepointName');

        try {
          // 1. 构建各种查询条件
          // 消息选择器：指定主题中seq在[startId, endId)范围内且状态<=synced的消息
          final messageSelectorWhere =
              '''
            $kColumnTopicId = ? AND ? <= $kColumnSeq AND $kColumnSeq < ? AND $kColumnStatus <= ?
          ''';
          final messageSelectorArgs = [
            topicId,
            startId,
            endId,
            RepositoryStatus.synced.value,
          ];

          // 范围删除选择器：状态>=deletedHard的记录
          final rangeDeleteWhere =
              '''
            $kColumnTopicId = ? AND ? <= $kColumnSeq AND $kColumnSeq < ? AND $kColumnStatus >= ?
          ''';
          final rangeDeleteArgs = [
            topicId,
            startId,
            endId,
            RepositoryStatus.deletedHard.value,
          ];

          // 有效序列选择器：effectiveSeq在[startId, endId)范围内的记录
          final effectiveSeqWhere =
              '''
            $kColumnTopicId = ? AND ? <= $kColumnEffectiveSeq AND $kColumnEffectiveSeq < ?
          ''';
          final effectiveSeqArgs = [topicId, startId, endId];

          // 确定状态类型
          final RepositoryStatus statusToConsume;
          if (actualDelId > 0) {
            statusToConsume = RepositoryStatus.deletedSynced;
          } else {
            statusToConsume = hard
                ? RepositoryStatus.deletedHard
                : RepositoryStatus.deletedSoft;
          }

          // 部分重叠删除范围选择器
          var rangeConsumeWhere =
              '''
            $kColumnTopicId = ? AND $kColumnStatus = ?
          ''';
          var rangeConsumeArgs = [topicId, statusToConsume.value];

          if (actualDelId > 0) {
            rangeConsumeWhere += ' AND $kColumnDelId < ?';
            rangeConsumeArgs.add(actualDelId);
          }

          // 重叠选择器：与当前范围有部分重叠的记录
          final overlapWhere =
              '''
            $rangeConsumeWhere AND $kColumnHigh >= ? AND $kColumnSeq <= ?
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
            {kColumnEffectiveSeq: null},
            where: effectiveSeqWhere,
            whereArgs: effectiveSeqArgs,
          );

          // 3. 查询重叠范围的最大连续范围
          final overlapQuery =
              '''
            SELECT MIN($kColumnSeq) as minSeq, MAX($kColumnHigh) as maxHigh
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
            kColumnTopicId: topicId,
            kColumnDelId: actualDelId,
            kColumnSeq: startId,
            kColumnHigh: endId,
            kColumnStatus: statusToConsume.value,
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
      await dbe.execute('RELEASE SAVEPOINT $savepointName');
      logError(
        'MessageDb[topicId = $topicId] - markDeleted SQLite error: code = ${e.hashCode}, error = $e',
      );
      return false;
    } catch (e) {
      // 释放保存点并处理其他错误
      await dbe.execute('RELEASE SAVEPOINT $savepointName');
      logError(
        'MessageDb - markDeleted operation failed: topicId = $topicId, error = ${e.toString()}',
      );
      return false;
    }
  }

  // 查询消息（核心查询方法）
  Future<List<MessageStored>?> query(
    DatabaseExecutor dbe,
    int topicId,
    int from,
    int limit,
    bool forward,
  ) async {
    final whereClause = forward
        ? '$kColumnTopicId = ? AND $kColumnEffectiveSeq > ? AND $kColumnEffectiveSeq IS NOT NULL'
        : '$kColumnTopicId = ? AND $kColumnEffectiveSeq < ? AND $kColumnEffectiveSeq IS NOT NULL';
    final orderBy = forward
        ? '$kColumnEffectiveSeq ASC'
        : '$kColumnEffectiveSeq DESC';

    final result = await dbe.query(
      kTableName,
      where: whereClause,
      whereArgs: [topicId, from],
      orderBy: orderBy,
      limit: limit,
    );

    return result.map((row) => _readOne(row)).toList();
  }

  Future<MessageStored?> queryByMsgId(
    DatabaseExecutor dbe,
    int? msgId,
    int previewLen,
  ) async {
    // 如果msgId为null，直接返回null
    if (msgId == null) {
      return null;
    }

    try {
      // 查询指定id的消息记录，获取所有字段
      var rows = await dbe.query(
        kTableName,
        where: '$kColumnId = ?',
        whereArgs: [msgId],
        limit: 1, // 只需要一条记录
      );

      // 如果查询到结果，转换为StoredMessage对象
      if (rows.isNotEmpty) {
        return _readOne(rows.first);
      }
      return null;
    } catch (e) {
      logError('MessageDb - query failed for msgId: $msgId, error: $e');
      return null;
    }
  }

  Future<List<MessageStored>?> queryUnsent(
    DatabaseExecutor dbe,
    int? topicId,
  ) async {
    // 构建查询条件
    var whereClauses = <String>[];
    var whereArgs = <dynamic>[];

    // 添加topicId条件
    if (topicId != null) {
      whereClauses.add('$kColumnTopicId = ?');
      whereArgs.add(topicId);
    } else {
      // 如果topicId为null，可能需要查询所有topic的未发送消息
      // 或者根据业务需求返回null
    }

    // 添加状态条件：只查询状态为queued的消息
    whereClauses.add('$kColumnStatus = ?');
    whereArgs.add(RepositoryStatus.queued.value);

    var whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      var rows = await dbe.query(
        kTableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: kColumnTs, // 按ts字段排序
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

      logError(
        'MessageDb[topicId = $topicId] - queryUnsent error: code = $errorCode, error = $errorMsg',
      );
      return null;
    }
  }

  Future<List<MsgRange>?> queryDeleted(
    DatabaseExecutor dbe,
    int? topicId,
    bool hard,
  ) async {
    // 验证topicId不为null
    if (topicId == null) {
      return null;
    }

    // 确定要查询的状态
    final status = hard
        ? RepositoryStatus.deletedHard
        : RepositoryStatus.deletedSoft;

    try {
      // 执行查询
      List<Map<String, dynamic>> rows = await dbe.query(
        kTableName,
        columns: [kColumnDelId, kColumnSeq, kColumnHigh], // 选择需要的字段
        where: '$kColumnTopicId = ? AND $kColumnStatus = ?',
        whereArgs: [topicId, status.value],
        orderBy: kColumnSeq, // 按seq排序
      );

      // 转换结果为MsgRange列表
      var ranges = <MsgRange>[];
      for (var row in rows) {
        final low = row[kColumnSeq] as int?;
        if (low != null) {
          ranges.add(MsgRange(low: low, hi: row[kColumnHigh] as int?));
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

      logError(
        'MessageDb[topicId = $topicId] - queryDelete SQLite error: code = $errorCode, error = $errorMsg',
      );
      return null;
    }
  }

  Future<List<MessageStored>?> queryLatest(DatabaseExecutor dbe) async {
    // 构建SQL查询语句，实现表连接和过滤逻辑
    // 这里使用原始SQL是因为涉及到自连接和复杂条件，比sqflite的query方法更直观
    final sql =
        '''
      SELECT m1.*, ${TopicRepository.kTableName}.${TopicRepository.kColumnTopic}
      FROM $kTableName m1
      LEFT OUTER JOIN $kTableName m2
        ON m1.$kColumnTopicId = m2.$kColumnTopicId
        AND m1.$kColumnEffectiveSeq < m2.$kColumnEffectiveSeq
      LEFT OUTER JOIN ${TopicRepository.kTableName}
        ON m1.$kColumnTopicId = ${TopicRepository.kTableName}.${TopicRepository.kColumnId}
      WHERE m1.$kColumnDelId IS NULL
        AND m2.$kColumnDelId IS NULL
        AND m2.id IS NULL
        AND m1.$kColumnEffectiveSeq IS NOT NULL
    ''';

    try {
      // 执行查询
      final List<Map<String, dynamic>> rows = await dbe.rawQuery(sql);

      // 转换结果为StoredMessage列表
      final messages = <MessageStored>[];
      for (final row in rows) {
        final sm = _readOne(row);
        sm.topic = row[TopicRepository.kColumnTopic] as String?;
        messages.add(sm);
      }

      return messages;
    } catch (e) {
      logError('MessageDb - queryLatest SQLite error: $e');
      return null;
    }
  }

  Future<List<MessageStored>?> queryByTopicIdAndFromAndLimitAndForward(
    DatabaseExecutor dbe,
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
      '$kColumnTopicId = ?', // 匹配话题ID
      '$kColumnEffectiveSeq IS NOT NULL', // 有效序列不为null
    ];
    final whereArgs = <dynamic>[topicId];

    // 根据查询方向添加序列范围条件
    if (forward) {
      whereClauses.add('$kColumnEffectiveSeq > ?');
      whereArgs.add(from);
    } else {
      whereClauses.add('$kColumnEffectiveSeq < ?');
      whereArgs.add(from);
    }

    final whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      final List<Map<String, dynamic>> rows = await dbe.query(
        kTableName,
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: forward
            ? '$kColumnEffectiveSeq ASC' // 正向查询按序列升序
            : '$kColumnEffectiveSeq DESC', // 反向查询按序列降序
        limit: limit,
      );

      // 转换结果为StoredMessage列表
      final messages = rows.map((row) {
        return _readOne(row);
      }).toList();

      return messages;
    } catch (e) {
      logError('MessageDb[topicId = $topicId] - query SQLite error: $e');
      return null;
    }
  }

  Future<MessageStored?> getMessage(
    DatabaseExecutor dbe,
    int topicId,
    int seqId,
  ) async {
    try {
      // 查询指定话题ID和有效序列的消息
      List<Map<String, dynamic>> rows = await dbe.query(
        kTableName,
        where: '$kColumnTopicId = ? AND $kColumnEffectiveSeq = ?',
        whereArgs: [topicId, seqId],
        limit: 1, // 只需要一条匹配的记录
      );

      // 如果查询到结果，转换为StoredMessage对象
      if (rows.isNotEmpty) {
        return _readOne(rows.first);
      }
      return null;
    } catch (e) {
      logError(
        'MessageDb - getMessage failed: topicId = $topicId, seqId = $seqId, error: $e',
      );
      return null;
    }
  }

  Future<List<int>?> getAllVersions(
    DatabaseExecutor dbe,
    int topicId,
    int seqId,
    int? limit,
  ) async {
    // 构建查询条件
    final whereClause = '$kColumnTopicId = ? AND $kColumnReplSeq = ?';
    final whereArgs = [topicId, seqId];

    try {
      // 执行查询
      final rows = await dbe.query(
        kTableName,
        columns: [kColumnSeq],
        // 只查询seq字段
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: '$kColumnSeq DESC',
        // 按seq降序排列
        limit: limit, // 可选的限制数量
      );

      // 提取seq值列表
      final seqIds = <int>[];
      for (final row in rows) {
        final seq = row[kColumnSeq] as int?;
        if (seq != null) {
          seqIds.add(seq);
        }
      }

      return seqIds;
    } catch (e) {
      // 错误处理
      logError(
        'MessageDb[topicId = $topicId] - getAllVersions SQLite error: $e',
      );
      return null;
    }
  }

  // 将查询结果转换为StoredMessage
  MessageStored _readOne(Map<String, dynamic> row) {
    final msg = MessageStored();
    msg.msgId = row[kColumnId] as int;
    msg.topicId = row[kColumnTopicId] as int?;
    msg.userId = row[kColumnUserId] as int?;
    msg.dbStatus = RepositoryStatus.fromValue(row[kColumnStatus] as int? ?? 0);
    msg.from = row[kColumnSender] as String?;

    // 处理时间
    final effTs = row[kColumnEffectiveTs] as int?;
    final ts = row[kColumnTs] as int?;
    msg.ts = effTs != null
        ? DateTime.fromMillisecondsSinceEpoch(effTs)
        : (ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null);

    msg.seq = row[kColumnEffectiveSeq] as int? ?? row[kColumnSeq] as int?;
    msg.head = row[kColumnHead] != null
        ? jsonDecode(row[kColumnHead] as String)
        : null;
    msg.deserializeContent(row[kColumnContent]);

    return msg;
  }

  Future<List<MsgRange>> getCachedRanges(
    DatabaseExecutor dbe,
    int? topicId,
    List<MsgRange> ranges,
  ) async {
    // 构建查询条件
    var whereClauses = <String>[];
    var whereArgs = <dynamic>[];

    // 添加topicId条件
    if (topicId != null) {
      whereClauses.add('$kColumnTopicId = ?');
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
        rangeConditions.add('($kColumnSeq < ? AND $kColumnHigh > ?)');
        whereArgs.add(r.hi);
        whereArgs.add(r.low);

        // Find normal entries
        rangeConditions.add(
          '($kColumnSeq < ? AND $kColumnSeq >= ? AND $kColumnHigh IS NULL)',
        );
        whereArgs.add(r.hi);
        whereArgs.add(r.low);
      } else {
        // 处理r.hi为null的情况
        // Find deleted ranges
        rangeConditions.add('($kColumnSeq <= ? AND $kColumnHigh > ?)');
        whereArgs.add(r.low);
        whereArgs.add(r.low);

        // Find normal entries
        rangeConditions.add('($kColumnSeq = ? AND $kColumnHigh IS NULL)');
        whereArgs.add(r.low);
      }
    }

    if (rangeConditions.isNotEmpty) {
      whereClauses.add('(' + rangeConditions.join(' OR ') + ')');
    }

    var whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      List<Map<String, dynamic>> rows = await dbe.query(
        kTableName, // 替换为实际表名
        columns: [kColumnSeq, kColumnHigh],
        where: whereClause,
        whereArgs: whereArgs,
      );

      // 转换结果为MsgRange列表
      var found = rows.map((row) {
        return MsgRange(
          low: row[kColumnSeq] as int,
          hi: row[kColumnHigh] as int?,
        );
      }).toList();

      // 排序并合并范围
      found.sort((a, b) => a.low.compareTo(b.low));
      return MsgRange.collapse(found);
    } catch (e) {
      logError(
        'MessageDb[topicId = $topicId] - getCachedRanges error: code = ${e.hashCode}, error = $e',
      );
      return [];
    }
  }

  Future<List<MsgRange>> getMissingRanges(
    DatabaseExecutor dbe,
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
      whereClauses.add('$kColumnTopicId = ?');
      whereArgs.add(topicId);
    } else {
      return []; // topicId为null时返回空列表
    }

    // 构建核心条件：newer ? ((high ?? (seq + 1)) > startFrom) : ((high ?? (seq + 1)) < startFrom)
    // 在SQL中使用CASE表达式实现null处理和比较逻辑
    var condition = newer
        ? '(CASE WHEN $kColumnHigh IS NULL THEN $kColumnSeq + 1 ELSE $kColumnHigh END) > ?'
        : '(CASE WHEN $kColumnHigh IS NULL THEN $kColumnSeq + 1 ELSE $kColumnHigh END) < ?';

    whereClauses.add(condition);
    whereArgs.add(startFrom);

    var whereClause = whereClauses.join(' AND ');

    try {
      // 执行查询
      List<Map<String, dynamic>> rows = await dbe.query(
        kTableName,
        columns: [kColumnSeq, kColumnHigh],
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: newer ? '$kColumnSeq ASC' : '$kColumnSeq DESC',
        limit: pageSize,
      );

      // 转换结果为MsgRange列表
      var found = rows.map((row) {
        return MsgRange(
          low: row[kColumnSeq] as int,
          hi: row[kColumnHigh] as int?,
        );
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

      logError(
        'MessageDb[topicId = $topicId] - getMissingRanges error: code = $errorCode, error = $errorMsg',
      );
      return [];
    }
  }
}
