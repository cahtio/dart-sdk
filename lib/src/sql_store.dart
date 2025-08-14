import 'package:tinode/src/base_db.dart';
import 'package:tinode/src/subscriber_db.dart';
import 'package:tinode/src/topic_db.dart';

import '../tinode.dart';
import 'models/drafty.dart';
import 'models/msg_range.dart';
import 'models/storage.dart';
import 'models/stored_message.dart';
import 'models/user.dart';

class SqlStoreError implements Exception {
  final String message;

  const SqlStoreError(this.message);

  @override
  String toString() {
    return 'MessageDb $message';
  }
}

class SqlStore implements Storage {
  @override
  String? get myUid => _dbh?.uid;

  @override
  set myUid(String? value) => _dbh?.setUid(uid: value, credMethods: null);

  @override
  Future<String?> deviceToken() async {
    return _dbh?.accountDb?.getDeviceToken();
  }

  @override
  Future<bool> setDeviceToken(String? token) async {
    final result = await _dbh?.accountDb?.saveDeviceToken(token);
    return result ?? false;
  }

  final BaseDb? _dbh;
  int _myId = -1;
  var _timeAdjustment = Duration.zero;

  SqlStore(this._dbh);

  @override
  Future<void> logout() async {
    await _dbh?.logout();
  }

  @override
  Future<void> deleteAccount(String uid) async {
    if (!(await _dbh?.deleteUid(uid) ?? true)) {
      BaseDb.log.info('Account deletion did not succeed. Uid [$uid]');
    }
  }

  @override
  Future<void> setMyUid({
    required String uid,
    List<String>? credMethods,
  }) async {
    await _dbh?.setUid(uid: uid, credMethods: credMethods);
  }

  @override
  void setTimeAdjustment(Duration adjustment) => _timeAdjustment = adjustment;

  @override
  bool get isReady => _dbh?.isReady ?? false;

  @override
  Future<List<Topic>?> topicGetAll(Tinode? tinode) async {
    final tdb = _dbh?.topicDb;
    final rows = await tdb?.query();
    if (rows == null) return null;

    final results = <Topic>[];
    for (final row in rows) {
      final topic = tdb?.readOneFromRow(row);
      if (topic != null) results.add(topic);
    }
    return results;
  }

  @override
  Future<Topic?> topicGet(Tinode? tinode, String? name) async {
    return _dbh?.topicDb?.readOne(name);
  }

  @override
  Future<int> topicAdd(Topic topic) async {
    if (topic.payload is StoredTopic) {
      return (topic.payload as StoredTopic).id ?? 0;
    }
    return _dbh?.topicDb?.insert(topic) ?? 0;
  }

  @override
  Future<bool> topicUpdate(Topic topic) async {
    return (await _dbh?.topicDb?.update(topic)) ?? false;
  }

  @override
  Future<bool> topicDelete(Topic topic, bool hard) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null) return false;

    const savepointName = 'SqlStore.topicDelete';
    try {
      await _dbh?.DB?.execute('SAVEPOINT $savepointName');
      if (hard) {
        await _dbh?.messageDb?.deleteAll(topicId: topicId);
        await _dbh?.subscriberDb?.deleteForTopic(topicId: topicId);
        await _dbh?.topicDb?.delete(topicId);
      } else {
        await _dbh?.topicDb?.markDeleted(topicId);
      }
      await _dbh?.DB?.execute('RELEASE SAVEPOINT $savepointName');
      return true;
    } catch (e) {
      await _dbh?.DB?.execute('ROLLBACK TO SAVEPOINT $savepointName');
      BaseDb.log.error(
        'SqlStore - topicDelete failed: topicId = $topicId, error = ${e.toString()}',
      );
      return false;
    }
  }

  @override
  Future<bool> setRead(Topic topic, int read) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId != null && topicId > 0) {
      return (await _dbh?.topicDb?.updateRead(topicId, read)) ?? false;
    } else {
      return false;
    }
  }

  @override
  Future<bool> setRecv(Topic topic, int recv) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId != null && topicId > 0) {
      return (await _dbh?.topicDb?.updateRecv(topicId, recv)) ?? false;
    } else {
      return false;
    }
  }

  @override
  Future<int> subAdd(Topic topic, TopicSubscription sub) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null) return 0;
    return (await _dbh?.subscriberDb?.insert(
          topicId: topicId,
          status: BaseDbStatus.synced,
          sub: sub,
        )) ??
        0;
  }

  @override
  Future<bool> subUpdate(Topic topic, TopicSubscription sub) async {
    final ss = sub.payload as StoredSubscription?;
    final subId = ss?.id;
    if (subId == null || subId <= 0) return false;
    return (await _dbh?.subscriberDb?.update(sub: sub)) ?? false;
  }

  @override
  Future<int> subNew(Topic topic, TopicSubscription sub) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null) return 0;
    return (await _dbh?.subscriberDb?.insert(
          topicId: topicId,
          status: BaseDbStatus.queued,
          sub: sub,
        )) ??
        0;
  }

  @override
  Future<bool> subDelete(Topic topic, TopicSubscription sub) async {
    final ss = sub.payload as StoredSubscription?;
    final subId = ss?.id;
    if (subId == null || subId <= 0) return false;
    return (await _dbh?.subscriberDb?.delete(recordId: subId)) ?? false;
  }

  @override
  Future<List<TopicSubscription>?> getSubscriptions(Topic topic) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null) return null;
    return _dbh?.subscriberDb?.readAll(topicId: topicId);
  }

  @override
  Future<User?> userGet(String uid) async {
    return _dbh?.userDb?.readOne(uid);
  }

  @override
  Future<int> userAdd(User user) async {
    return (await _dbh?.userDb?.insert(
          uid: user.uid,
          updated: user.updated,
          serializedPub: user.pub,
        )) ??
        0;
  }

  @override
  Future<bool> userUpdate(User user) async {
    return (await _dbh?.userDb?.updateUser(user)) ?? false;
  }

  @override
  Future<StoredMessage?> msgReceived({
    required Topic topic,
    TopicSubscription? sub,
    DataMessage? msg,
  }) async {
    if (msg == null) return null;

    var topicId = -1;
    var userId = -1;

    if (sub?.payload is StoredSubscription) {
      final ss = sub!.payload as StoredSubscription;
      topicId = ss.topicId ?? -1;
      userId = ss.userId ?? -1;
    } else if (topic.payload is StoredTopic) {
      final st = topic.payload as StoredTopic;
      topicId = st.id ?? -1;
      userId = (await _dbh?.userDb?.getId(msg.from)) ?? -1;

      if (userId < 0) {
        userId = sub != null
            ? (await _dbh?.userDb?.insertSubscription(sub) ?? -1)
            : (await _dbh?.userDb?.insert(
                    uid: msg.from,
                    updated: msg.ts,
                    serializedPub: null,
                  ) ??
                  -1);
      }
    }

    if (topicId < 0 || userId < 0) {
      BaseDb.log.error('SqlStore - msgReceived: user or topic not available');
      return null;
    }

    final sm = StoredMessage.fromDataMessage(msg);
    sm.topicId = topicId;
    sm.userId = userId;
    sm.dbStatus = BaseDbStatus.synced;
    const savepointName = 'SqlStore.msgReceived';

    try {
      await _dbh?.DB?.execute('SAVEPOINT $savepointName');
      sm.msgId = (await _dbh?.messageDb?.insert(topic: topic, msg: sm)) ?? -1;
      if (sm.msgId <= 0 ||
          !(await _dbh?.topicDb?.msgReceived(
                topic,
                sm.ts ?? DateTime.now(),
                sm.seqId,
              ) ??
              false)) {
        throw SqlStoreError(
          'Could not handle received message: msgId = ${sm.msgId}, topicId = $topicId, userId = $userId',
        );
      }

      await _dbh?.DB?.execute('RELEASE SAVEPOINT $savepointName');
      return sm;
    } catch (e) {
      await _dbh?.DB?.execute('ROLLBACK TO SAVEPOINT $savepointName');
      BaseDb.log.error('SqlStore - msgReceived failed: ${e.toString()}');
      return null;
    }
  }

  @override
  Future<StoredMessage?> msgSend({
    required Topic topic,
    required Drafty data,
    Map<String, dynamic>? head,
  }) => _insertMessage(topic, data, head, BaseDbStatus.undefined);

  @override
  Future<StoredMessage?> msgDraft({
    required Topic topic,
    required Drafty data,
    Map<String, dynamic>? head,
  }) => _insertMessage(topic, data, head, BaseDbStatus.draft);

  @override
  Future<bool> msgDraftUpdate({
    required Topic topic,
    required int dbMessageId,
    required Drafty data,
  }) async =>
      await _dbh?.messageDb?.updateStatusAndContent(
        msgId: dbMessageId,
        status: BaseDbStatus.undefined,
        content: data,
      ) ??
      false;

  @override
  Future<bool> msgReady({
    required Topic topic,
    required int dbMessageId,
    required Drafty data,
  }) async =>
      await _dbh?.messageDb?.updateStatusAndContent(
        msgId: dbMessageId,
        status: BaseDbStatus.queued,
        content: data,
      ) ??
      false;

  @override
  Future<bool> msgSyncing({
    required Topic topic,
    required int dbMessageId,
    required bool sync,
  }) async =>
      await _dbh?.messageDb?.updateStatusAndContent(
        msgId: dbMessageId,
        status: sync ? BaseDbStatus.sending : BaseDbStatus.queued,
        content: null,
      ) ??
      false;

  @override
  Future<bool> msgFailed({
    required Topic topic,
    required int dbMessageId,
  }) async =>
      await _dbh?.messageDb?.updateStatusAndContent(
        msgId: dbMessageId,
        status: BaseDbStatus.failed,
        content: null,
      ) ??
      false;

  @override
  Future<bool> msgPruneFailed(Topic topic) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    return topicId != null
        ? _dbh?.messageDb?.deleteFailed(topicId) ?? false
        : false;
  }

  @override
  Future<bool> msgDiscardById({
    required Topic topic,
    required int dbMessageId,
  }) async => await _dbh?.messageDb?.deleteByMsgId(dbMessageId) ?? false;

  @override
  Future<bool> msgDiscardBySeq({
    required Topic topic,
    required int seqId,
  }) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null) return false;
    return await _dbh?.messageDb?.deleteInTopic(
          topicId: topicId,
          seqId: seqId,
        ) ??
        false;
  }

  @override
  Future<bool> msgDelivered({
    required Topic topic,
    required int dbMessageId,
    required DateTime timestamp,
    required int seq,
  }) async {
    const savepointName = 'SqlStore.msgDelivered';
    try {
      await _dbh?.DB?.execute('SAVEPOINT $savepointName');

      final messageSuccess =
          await _dbh?.messageDb?.delivered(
            msgId: dbMessageId,
            ts: timestamp,
            seq: seq,
          ) ??
          false;
      final topicSuccess =
          await _dbh?.topicDb?.msgReceived(topic, timestamp, seq) ?? false;
      if (!messageSuccess || !topicSuccess) {
        throw SqlStoreError(
          'messageDb = $messageSuccess, topicDb = $topicSuccess',
        );
      }
      await _dbh?.DB?.execute('RELEASE SAVEPOINT $savepointName');
      return true;
    } catch (e) {
      await _dbh?.DB?.execute('ROLLBACK TO SAVEPOINT $savepointName');
      BaseDb.log.error('SqlStore - msgDelivered failed: ${e.toString()}');
      return false;
    }
  }

  @override
  Future<bool> msgMarkToDeleteRange({
    required Topic topic,
    required int idLo,
    required int idHi,
    required bool markAsHard,
  }) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    return topicId != null
        ? await _dbh?.messageDb?.deleteOrMarkDeleted(
                topicId: topicId,
                delId: null,
                from: idLo,
                to: idHi,
                hard: markAsHard,
              ) ??
              false
        : false;
  }

  @override
  Future<bool> msgMarkToDeleteRanges({
    required Topic topic,
    List<MsgRange>? ranges,
    required bool markAsHard,
  }) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null || ranges == null || ranges.isEmpty) return false;
    return await _dbh?.messageDb?.deleteOrMarkDeletedWithRanges(
          topicId: topicId,
          delId: null,
          ranges: ranges,
          hard: markAsHard,
        ) ??
        false;
  }

  @override
  Future<bool> msgDeleteRange({
    required Topic topic,
    required int delId,
    required int idLo,
    required int idHi,
  }) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null) return false;

    final adjustedIdHi = idHi <= 0 ? (st?.maxLocalSeq ?? 0) + 1 : idHi;
    var success = false;
    const savepointName = 'SqlStore.msgDelete-bounds';

    try {
      await _dbh?.DB?.execute('SAVEPOINT $savepointName');
      success =
          (await _dbh?.topicDb?.msgDeleted(topic, delId, idLo, adjustedIdHi) ??
              false) &&
          (await _dbh?.messageDb?.delete(
                topicId: topicId,
                delId: delId,
                loId: idLo,
                hiId: adjustedIdHi,
              ) ??
              false);
      await _dbh?.DB?.execute('RELEASE SAVEPOINT $savepointName');
    } catch (e) {
      await _dbh?.DB?.execute('ROLLBACK TO SAVEPOINT $savepointName');
      BaseDb.log.error('SqlStore - msgDelete failed: ${e.toString()}');
    }
    return success;
  }

  @override
  Future<bool> msgDeleteRanges({
    required Topic topic,
    required int id,
    List<MsgRange>? ranges,
  }) async {
    // 验证参数：topic.payload 必须是 StoredTopic，且包含有效 topicId，ranges 不为空且非空
    if (topic.payload is! StoredTopic) return false;
    final storedTopic = topic.payload as StoredTopic;
    final topicId = storedTopic.id;
    if (topicId == null) return false;
    if (ranges == null || ranges.isEmpty) return false;

    // 处理范围：折叠和获取包围范围
    final collapsedRanges = MsgRange.collapse(ranges);
    final enclosing = MsgRange.enclosing(collapsedRanges);
    if (enclosing == null) return false;

    var success = false;
    const savepointName = 'SqlStore.msgDelete-ranges';
    final db = _dbh?.DB;

    if (db == null) return false;

    try {
      // 开启事务并创建保存点
      await db.transaction((txn) async {
        // 创建保存点
        await txn.execute('SAVEPOINT $savepointName');

        try {
          // 执行两个核心操作：标记主题消息已删除 + 标记 / 删除消息
          final topicDbSuccess =
              await _dbh?.topicDb?.msgDeleted(
                topic,
                id,
                enclosing.lower,
                enclosing.upper,
              ) ??
              false;

          final messageDbSuccess =
              await _dbh?.messageDb?.deleteOrMarkDeletedWithRanges(
                topicId: topicId,
                delId: id,
                ranges: collapsedRanges,
                hard: false,
              ) ??
              false;

          success = topicDbSuccess && messageDbSuccess;

          // 操作成功，释放保存点
          await txn.execute('RELEASE SAVEPOINT $savepointName');
        } catch (e) {
          // 操作失败，回滚到保存点
          await txn.execute('ROLLBACK TO SAVEPOINT $savepointName');
          return false;
        }
      });
    } catch (e) {
      BaseDb.log.error(
        'SqlStore - msgDelete operation failed: ${e.toString()}',
      );
    }

    return success;
  }

  @override
  Future<bool> msgRecvByRemote({
    required TopicSubscription sub,
    int? recv,
  }) async {
    if (sub.payload is! StoredSubscription) return false;
    final storedSub = sub.payload as StoredSubscription;
    final sid = storedSub.id;
    if (sid == null || sid <= 0 || recv == null) return false;

    return await _dbh?.subscriberDb?.updateRecv(subId: sid, value: recv) ??
        false;
  }

  @override
  Future<bool> msgReadByRemote({
    required TopicSubscription sub,
    int? read,
  }) async {
    if (sub.payload is! StoredSubscription) return false;
    final storedSub = sub.payload as StoredSubscription;
    final sid = storedSub.id;
    if (sid == null || sid <= 0 || read == null) return false;

    return await _dbh?.subscriberDb?.updateRead(subId: sid, value: read) ??
        false;
  }

  Future<StoredMessage?> _insertMessage(
    Topic topic,
    Drafty data,
    Map<String, dynamic>? head,
    BaseDbStatus initialStatus,
  ) async {
    final msg = StoredMessage()
      ..topic = topic.name
      ..from = myUid
      ..ts = DateTime.now().add(_timeAdjustment)
      ..seq = 0
      ..dbStatus = initialStatus
      ..content = data
      ..head = head
      ..topicId = (topic.payload as StoredTopic?)?.id ?? -1;

    if (_myId < 0) {
      _myId = await _dbh?.userDb?.getId(msg.from) ?? -1;
    }
    msg.userId = _myId;

    final id = await _dbh?.messageDb?.insert(topic: topic, msg: msg) ?? -1;
    return id > 0 ? msg : null;
  }

  @override
  MsgRange? getCachedMessagesRange(Topic topic) {
    final st = topic.payload as StoredTopic?;
    if (st == null) return null;
    return MsgRange(low: st.minLocalSeq ?? 0, hi: (st.maxLocalSeq ?? 0) + 1);
  }

  @override
  Future<List<MsgRange>> msgIsCached({
    required Topic topic,
    required List<MsgRange> ranges,
  }) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    if (topicId == null) return [];

    return await _dbh?.messageDb?.getCachedRanges(topicId, ranges) ?? [];
  }

  @override
  Future<List<MsgRange>> getMissingRanges({
    required Topic topic,
    required int startFrom,
    required int pageSize,
    required bool newer,
  }) async {
    final st = topic.payload as StoredTopic?;
    final topicId = st?.id;
    return topicId != null
        ? await _dbh?.messageDb?.getMissingRanges(
                topicId,
                startFrom,
                pageSize,
                newer,
              ) ??
              []
        : [];
  }

  @override
  Future<StoredMessage?> getMessageById(int dbMessageId) async {
    return await _dbh?.messageDb?.queryByMsgId(
      msgId: dbMessageId,
      previewLen: -1,
    );
  }

  @override
  Future<StoredMessage?> getMessagePreviewById(int dbMessageId) {
    return getMessageById(dbMessageId);
  }

  @override
  Future<List<StoredMessage>?> getQueuedMessages(Topic topic) async {
    // 检查topic的payload是否为StoredTopic类型
    if (topic.payload is! StoredTopic) {
      return null;
    }

    var st = topic.payload as StoredTopic;

    // 检查id是否有效
    if (st.id == null || st.id! <= 0) {
      return null;
    }

    // 调用数据库查询未发送消息
    return await _dbh?.messageDb?.queryUnsent(st.id);
  }

  @override
  Future<List<MsgRange>?> getQueuedMessageDeletes({
    required Topic topic,
    required bool hard,
  }) async {
    if (topic.payload is! StoredTopic) {
      return null;
    }
    var st = topic.payload as StoredTopic;
    if (st.id == null || st.id! <= 0) {
      return null;
    }

    return await _dbh?.messageDb?.queryDeleted(st.id, hard);
  }

  @override
  Future<List<StoredMessage>?> getLatestMessagePreviews() async {
    return await _dbh?.messageDb?.queryLatest();
  }

  @override
  Future<List<StoredMessage>?> getMessagePage({
    required Topic topic,
    required int from,
    required int limit,
    required bool forward,
  }) async {
    if (topic.payload is! StoredTopic) {
      return null;
    }
    var st = topic.payload as StoredTopic;
    if (st.id == null || st.id! <= 0) {
      return null;
    }

    return await _dbh?.messageDb?.queryByTopicIdAndFromAndLimitAndForward(
      st.id,
      from,
      limit,
      forward,
    );
  }

  @override
  Future<StoredMessage?> getMessageBySeq({
    required Topic topic,
    required int seqId,
  }) async {
    if (topic.payload is! StoredTopic) {
      return null;
    }
    var st = topic.payload as StoredTopic;
    if (st.id == null || st.id! <= 0) {
      return null;
    }
    return await _dbh?.messageDb?.getMessage(st.id!, seqId);
  }

  @override
  Future<List<int>?> getAllMsgVersions({
    required Topic topic,
    required int seqId,
    int? limit,
  }) async {
    if (topic.payload is! StoredTopic) {
      return null;
    }
    var st = topic.payload as StoredTopic;
    if (st.id == null || st.id! <= 0) {
      return null;
    }
    return await _dbh?.messageDb?.getAllVersions(st.id!, seqId, limit);
  }
}
