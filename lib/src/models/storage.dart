import 'package:tinode/src/models/message.dart';
import 'package:tinode/src/models/msg_range.dart';
import 'package:tinode/src/models/stored_message.dart';
import 'package:tinode/src/models/user.dart';
import 'package:tinode/tinode.dart';

import 'drafty.dart';

abstract class Storage {
  String? myUid;

  Future<String?> deviceToken();

  Future<bool> setDeviceToken(String? token);

  Future<void> logout();

  Future<void> deleteAccount(String uid);

  Future<void> setMyUid({required String uid, List<String>? credMethods});

  void setTimeAdjustment(Duration adjustment);

  bool get isReady;

  // Topics
  Future<List<Topic>?> topicGetAll(Tinode? tinode);

  Future<Topic?> topicGet(Tinode? tinode, String? name);

  Future<int> topicAdd(Topic topic);

  Future<bool> topicUpdate(Topic topic);

  Future<bool> topicDelete(Topic topic, bool hard);

  // Read/Recv markers
  Future<bool> setRead(Topic topic, int read);

  Future<bool> setRecv(Topic topic, int recv);

  // Subscriptions
  Future<int> subAdd(Topic topic, TopicSubscription sub);

  Future<bool> subUpdate(Topic topic, TopicSubscription sub);

  Future<int> subNew(Topic topic, TopicSubscription sub);

  Future<bool> subDelete(Topic topic, TopicSubscription sub);

  Future<List<TopicSubscription>?> getSubscriptions(Topic topic);

  // Users
  Future<User?> userGet(String uid);

  Future<int> userAdd(User user);

  Future<bool> userUpdate(User user);

  // Messages
  Future<StoredMessage?> msgReceived({
    required Topic topic,
    TopicSubscription? sub,
    DataMessage? msg,
  });

  Future<StoredMessage?> msgSend({
    required Topic topic,
    required Drafty data,
    Map<String, dynamic>? head,
  });

  Future<StoredMessage?> msgDraft({
    required Topic topic,
    required Drafty data,
    Map<String, dynamic>? head,
  });

  Future<bool> msgDraftUpdate({
    required Topic topic,
    required int dbMessageId,
    required Drafty data,
  });

  Future<bool> msgReady({
    required Topic topic,
    required int dbMessageId,
    required Drafty data,
  });

  Future<bool> msgSyncing({
    required Topic topic,
    required int dbMessageId,
    required bool sync,
  });

  Future<bool> msgFailed({required Topic topic, required int dbMessageId});

  Future<bool> msgPruneFailed(Topic topic);

  Future<bool> msgDiscardById({required Topic topic, required int dbMessageId});

  Future<bool> msgDiscardBySeq({required Topic topic, required int seqId});

  Future<bool> msgDelivered({
    required Topic topic,
    required int dbMessageId,
    required DateTime timestamp,
    required int seq,
  });

  Future<bool> msgMarkToDeleteRange({
    required Topic topic,
    required int idLo,
    required int idHi,
    required bool markAsHard,
  });

  Future<bool> msgMarkToDeleteRanges({
    required Topic topic,
    List<MsgRange>? ranges,
    required bool markAsHard,
  });

  Future<bool> msgDeleteRange({
    required Topic topic,
    required int delId,
    required int idLo,
    required int idHi,
  });

  Future<bool> msgDeleteRanges({
    required Topic topic,
    required int id,
    List<MsgRange>? ranges,
  });

  Future<bool> msgRecvByRemote({required TopicSubscription sub, int? recv});

  Future<bool> msgReadByRemote({required TopicSubscription sub, int? read});

  // Message queries
  MsgRange? getCachedMessagesRange(Topic topic);

  Future<List<MsgRange>> msgIsCached({
    required Topic topic,
    required List<MsgRange> ranges,
  });

  Future<List<MsgRange>> getMissingRanges({
    required Topic topic,
    required int startFrom,
    required int pageSize,
    required bool newer,
  });

  Future<StoredMessage?> getMessageById(int dbMessageId);

  Future<StoredMessage?> getMessagePreviewById(int dbMessageId);

  Future<List<StoredMessage>?> getQueuedMessages(Topic topic);

  Future<List<MsgRange>?> getQueuedMessageDeletes({
    required Topic topic,
    required bool hard,
  });

  Future<List<StoredMessage>?> getLatestMessagePreviews();

  Future<List<StoredMessage>?> getMessagePage({
    required Topic topic,
    required int from,
    required int limit,
    required bool forward,
  });

  Future<StoredMessage?> getMessageBySeq({
    required Topic topic,
    required int seqId,
  });

  Future<List<int>?> getAllMsgVersions({
    required Topic topic,
    required int seqId,
    int? limit,
  });
}
