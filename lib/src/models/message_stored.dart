import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:tinode/src/db/repository.dart';

import 'package:tinode/src/models/server-messages.dart';
import 'package:tinode/src/services/database_manager.dart';

class MessageStored extends DataMessage {
  var msgId = 0;

  int get seqId => seq ?? 0;

  int? topicId;
  int? userId;

  RepositoryStatus? dbStatus;

  int? get status => dbStatus?.value;

  bool get isDraft => dbStatus == RepositoryStatus.draft;

  bool get isReady => dbStatus == RepositoryStatus.queued;

  bool get isDeleted =>
      dbStatus == RepositoryStatus.deletedHard ||
      dbStatus == RepositoryStatus.deletedSoft ||
      dbStatus == RepositoryStatus.deletedSynced;

  bool get isSynced => dbStatus == RepositoryStatus.synced;

  /// 消息尚未交付到服务器
  bool get isPending =>
      dbStatus == null || (dbStatus!.index <= RepositoryStatus.sending.index);

  /// 如果消息是从其他主题转发的则为true
  bool get isForwarded {
    if (head == null) return false;
    var forwarded = head!['forwarded'];
    return forwarded != null && forwarded.toString().isNotEmpty;
  }

  /// 如果消息已被编辑则为true
  bool get isEdited {
    if (head == null) return false;
    return head!['replace'] != null && head!['webrtc'] == null;
  }

  /// 如果账户所有者是消息的作者则为true
  bool get isMine => DatabaseManager.instance.isMe(from);

  /// 消息内容的缓存表示（富文本）
  AttributedString? cachedContent;

  /// 消息预览的缓存表示（富文本）
  AttributedString? cachedPreview;

  MessageStored();

  MessageStored.fromDataMessage(DataMessage message)
    : super(
        topic: message.topic,
        from: message.from,
        head: message.head,
        ts: message.ts,
        seq: message.seq,
        content: message.content,
        noForwarding: message.noForwarding,
        hi: message.hi,
      );

  MessageStored.fromDataMessageWithStatus(
    DataMessage message,
    RepositoryStatus status,
  ) : super(
        topic: message.topic,
        from: message.from,
        head: message.head,
        ts: message.ts,
        seq: message.seq,
        content: message.content,
        noForwarding: message.noForwarding,
        hi: message.hi,
      ) {
    dbStatus = status;
  }

  bool isDeletedWithHard(bool hard) => hard
      ? dbStatus == RepositoryStatus.deletedHard
      : dbStatus == RepositoryStatus.deletedSoft;

  MessageStored copyOf() {
    var copy = MessageStored.fromDataMessage(this);
    copy.msgId = msgId;
    copy.topicId = topicId;
    copy.userId = userId;
    copy.dbStatus = dbStatus;
    copy.cachedContent = cachedContent;
    copy.cachedPreview = cachedPreview;
    return copy;
  }

  String serializeContent() {
    return json.encode(content);
  }

  bool deserializeContent(String? data) {
    if (data == null) return false;
    content = json.decode(data);
    return true;
  }
}
