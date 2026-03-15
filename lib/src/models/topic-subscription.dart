import 'package:tinode/src/models/topic-description.dart';
import 'package:tinode/src/models/access-mode.dart';
import 'package:tinode/src/services/tools.dart';
import 'package:tinode/tinode.dart';

/// Info on when the peer was last online
class Seen {
  /// Timestamp
  DateTime? when;

  /// User agent of peer's client
  final String? ua;

  Seen({this.when, this.ua});

  static Seen fromMessages(Map<String, dynamic> msg) {
    return Seen(
      ua: msg['ua'],
      when: msg['when'] != null ? DateTime.parse(msg['when']) : DateTime.now(),
    );
  }
}

/// Topic subscriber
class TopicSubscription {
  /// Id of the user this subscription
  String? user;

  /// Timestamp of the last change in the subscription, present only for
  /// requester's own subscriptions
  DateTime? updated;

  /// Timestamp of the last message in the topic (may also include
  /// other events in the future, such as new subscribers)
  DateTime? touched;

  DateTime? deleted;
  DateTime? created;

  /// User's access permissions
  AccessMode? acs;

  /// Id of the message user claims through {note} message
  int? read;

  /// Like 'read', but received, optional
  int? recv;

  /// In case some messages were deleted, the greatest Id of a deleted message, optional
  int? clear;

  /// Application-defined user's 'public' object, absent when querying P2P topics
  dynamic public;

  /// Application-defined user's 'private' object.
  dynamic private;

  /// current online status of the user; if this is a
  /// group or a p2p topic, it's user's online status in the topic,
  /// i.e. if the user is attached and listening to messages; if this
  /// is a response to a 'me' query, it tells if the topic is
  /// online; p2p is considered online if the other party is
  /// online, not necessarily attached to topic; a group topic
  /// is considered online if it has at least one active
  /// subscriber.
  bool? online;

  /// Topic this subscription describes
  ///
  /// can be used only when querying 'me' topic
  String? topic;

  /// Server-issued id of the last {data} message
  ///
  /// can be used only when querying 'me' topic
  int? seq;

  /// If this is a P2P topic, info on when the peer was last online
  ///
  /// can be used only when querying 'me' topic
  Seen? seen;

  bool? noForwarding = false;

  String? mode;

  // int? unread;

  DataMessage? lastMessage;

  bool? isChannel = false;

  int? subCount;

  /// 申请状态
  int? apply_status = 0;

  List<DelRange> delseqs = [];

  int get unread {
    if (seq == null) return 0;
    if (read == null) return seq!;
    var count = seq! - read!;
    final min = count;
    for (var i = seq!; i > min; i--) {
      for (var delseq in delseqs) {
        if (delseq.isContain(i)) {
          count--;
        }
      }
    }
    return count;
  }

  TopicSubscription(
      {this.user,
      this.updated,
      this.touched,
      this.acs,
      this.read,
      this.recv,
      this.clear,
      this.public,
      this.private,
      this.online,
      this.topic,
      this.seq,
      this.seen,
      this.noForwarding,
      this.deleted,
      this.created,
      this.mode,
      this.lastMessage,
      this.isChannel,
      this.subCount,
      this.apply_status});

  static TopicSubscription fromMessage(Map<String, dynamic> msg) {
    return TopicSubscription(
      user: msg['user'],
      updated: msg['updated'] != null ? DateTime.parse(msg['updated']) : null,
      touched: msg['touched'] != null ? DateTime.parse(msg['touched']) : null,
      deleted: msg['deleted'] != null ? DateTime.parse(msg['deleted']) : null,
      created: msg['created'] != null ? DateTime.parse(msg['created']) : null,
      acs: msg['acs'] != null ? AccessMode(msg['acs']) : null,
      read: msg['read'],
      recv: msg['recv'],
      clear: msg['clear'],
      public: msg['public'],
      private: msg['private'],
      online: msg['online'],
      topic: msg['topic'],
      seq: msg['seq'],
      seen: msg['seen'] != null ? Seen.fromMessages(msg['seen']) : null,
      noForwarding: msg['noForwarding'] ?? false,
      mode: msg['mode'],
      isChannel: msg['is_channel'] ?? false,
      apply_status: msg['apply_status'] ?? 0,
      subCount: msg['sub_count'],
      lastMessage: msg['lastMessage'] != null
          ? DataMessage.fromMessage(msg['lastMessage'])
          : null,
    );
  }

  TopicSubscription copy() {
    return TopicSubscription(
        user: user,
        updated: updated,
        touched: touched,
        deleted: deleted,
        created: created,
        acs: acs,
        read: read,
        recv: recv,
        clear: clear,
        public: public,
        private: private,
        online: online,
        topic: topic,
        seq: seq,
        seen: seen,
        noForwarding: noForwarding,
        mode: mode,
        isChannel: isChannel,
        subCount: subCount,
        lastMessage: lastMessage);
  }

  TopicDescription asDesc() {
    return TopicDescription(
      acs: acs,
      clear: clear,
      created: created,
      noForwarding: noForwarding,
      private: private,
      public: public,
      read: read,
      recv: recv,
      seq: seq,
      touched: touched,
      updated: updated,
      chan: isChannel,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (user != null) json['user'] = user;
    if (acs != null) json['acs'] = acs!.toJson();
    if (mode != null) json['mode'] = mode;
    if (isChannel != null) json['is_channel'] = isChannel;
    if (updated != null) json['updated'] = updated!.toIso8601String();
    if (touched != null) json['touched'] = touched!.toIso8601String();
    if (deleted != null) json['deleted'] = deleted!.toIso8601String();
    if (created != null) json['created'] = created!.toIso8601String();
    if (read != null) json['read'] = read;
    if (recv != null) json['recv'] = recv;
    if (clear != null) json['clear'] = clear;
    if (public != null) json['public'] = public;
    if (private != null) json['private'] = private;
    if (online != null) json['online'] = online;
    if (topic != null) json['topic'] = topic;
    if (seq != null) json['seq'] = seq;
    // if (seen != null) json['seen'] = seen!.toJson();
    if (noForwarding != null) json['noForwarding'] = noForwarding;
    if (subCount != null) json['sub_count'] = subCount;
    if (lastMessage != null) json['lastMessage'] = lastMessage!.toJson();
    return json;
  }

  void addDelseq(DelRange delseq) {
    if (delseqs.contains(delseq)) return;
    delseqs.add(delseq);
  }

  void addDelseqList(List<DelRange> list) {
    for (final delseq in list) {
      addDelseq(delseq);
    }
  }
}
