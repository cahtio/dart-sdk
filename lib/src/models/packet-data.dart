import 'package:tinode/src/models/set-params.dart';
import 'package:tinode/src/models/get-query.dart';

abstract class PacketData {
  Map<String, dynamic> toMap();
}

class HiPacketData extends PacketData {
  final String? ver;
  final String? ua;
  final String? dev;
  final String? lang;
  final String? platf;

  HiPacketData({
    this.ua,
    this.ver,
    this.dev,
    this.lang,
    this.platf,
  });

  @override
  Map<String, String> toMap() {
    return {
      'ua': ua ?? '',
      'ver': ver ?? '',
      'dev': dev ?? '',
      'lang': lang ?? '',
      'platf': platf ?? '',
    };
  }
}

class AccPacketData extends PacketData {
  String? user;
  String? scheme;
  String? secret;
  bool? login;
  List<String>? tags;
  Map<String, dynamic>? desc;
  dynamic cred;
  String? token;

  AccPacketData({
    this.user,
    this.scheme,
    this.secret,
    this.login,
    this.tags,
    this.desc,
    this.cred,
    this.token,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'user': user,
      'scheme': scheme,
      'secret': secret,
      'login': login,
      'tags': tags,
      'desc': desc,
      'cred': cred,
      'token': token,
    };
  }
}

class LoginPacketData extends PacketData {
  String? scheme;
  String? secret;
  List<Map<String, dynamic>>? cred;

  LoginPacketData({this.scheme, this.secret, this.cred});

  @override
  Map<String, dynamic> toMap() {
    return {
      'scheme': scheme,
      'secret': secret,
      'cred': cred,
    };
  }
}

class SubPacketData extends PacketData {
  String? topic;
  SetParams? set;
  GetQuery? get;

  SubPacketData({this.topic, this.set, this.get});

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'set': set?.toMap(),
      'get': get?.toMap(),
    };
  }
}

class LeavePacketData extends PacketData {
  final String? topic;
  bool? unsub;

  LeavePacketData({this.topic, this.unsub});

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'unsub': unsub,
    };
  }
}

class PubPacketData extends PacketData {
  String? topic;
  bool? noecho;
  dynamic head;
  dynamic content;
  int? seq;
  String? from;
  DateTime? ts;

  PubPacketData(
      {this.topic,
      this.noecho,
      this.head,
      this.content,
      this.seq,
      this.from,
      this.ts});

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'noecho': noecho,
      'head': head,
      'content': content,
      'seq': seq,
      'from': from,
      'ts': ts,
    };
  }
}

class GetPacketData extends PacketData {
  String? topic;
  String? what;
  dynamic desc;
  dynamic sub;
  dynamic data;

  GetPacketData({this.topic, this.what, this.desc, this.sub, this.data});

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'what': what,
      'desc': desc,
      'sub': sub,
      'data': data,
    };
  }
}

class SetPacketData extends PacketData {
  String? topic;
  dynamic desc;
  dynamic sub;
  dynamic cred;
  List<String>? tags;
  dynamic favorite;

  SetPacketData({
    this.topic,
    this.desc,
    this.sub,
    this.tags,
    this.cred,
    this.favorite,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'desc': desc,
      'sub': sub,
      'tags': tags,
      'cred': cred,
      'favorite': favorite,
    };
  }
}

class DelPacketData extends PacketData {
  String? topic;
  String? what;
  dynamic delseq;
  dynamic user;
  bool? hard;
  dynamic cred;

  DelPacketData(
      {this.topic, this.what, this.delseq, this.user, this.hard, this.cred});

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'what': what,
      'delseq': delseq,
      'user': user,
      'hard': hard,
      'cred': cred,
    };
  }
}

class NotePacketData extends PacketData {
  String? topic;
  String? what;
  dynamic seq;
  String? event;
  dynamic payload;

  NotePacketData({this.topic, this.what, this.seq, this.event, this.payload});

  @override
  Map<String, dynamic> toMap() {
    final map = {
      'topic': topic,
      'what': what,
      'seq': seq,
      'event': event,
      'payload': payload
    };
    final nonullMap = <String, dynamic>{};
    map.forEach((key, value) {
      if (value == null) return;
      nonullMap[key] = value;
    });
    return nonullMap;
  }
}

class MomentPacketData extends PacketData {
  String topic;
  String content;
  int? privacy;
  int? momId;
  List<dynamic>? data;
  List<dynamic>? attachments;

  MomentPacketData(
      {required this.topic,
      required this.content,
      this.privacy,
      this.momId,
      this.data,
      this.attachments});

  @override
  Map<String, dynamic> toMap() {
    final dataMap = <String, dynamic>{'content': content};

    if (privacy != null) dataMap['privacy'] = privacy;
    if (momId != null) dataMap['momId'] = momId;
    if (data !=null) dataMap['data'] = data;
    if (attachments?.isNotEmpty ?? true) dataMap['attachments'] = attachments;

    return {
      'topic': topic,
      'set': {'data': dataMap}
    };
  }
}

class NotificationsPacketData extends PacketData {
  String topic;
  String content;
  int? privacy;
  int? momId;
  List<dynamic>? data;
  List<dynamic>? attachments;

  NotificationsPacketData(
      {required this.topic,
      required this.content,
      this.privacy,
      this.momId,
      this.data,
      this.attachments});

  @override
  Map<String, dynamic> toMap() {
    final dataMap = <String, dynamic>{'content': content};

    if (privacy != null) dataMap['privacy'] = privacy;
    if (momId != null) dataMap['momId'] = momId;
    if (data !=null) dataMap['data'] = data;
    if (attachments?.isNotEmpty ?? true) dataMap['attachments'] = attachments;

    return {
      'topic': topic,
      'set': {'data': dataMap}
    };
  }
}

class GetNotificationsPacketData extends PacketData {
  String topic;
  int? since;
  int? before;
  int? limit;

  GetNotificationsPacketData({
    required this.topic,
    this.since,
    this.before,
    this.limit,
  });

  @override
  Map<String, dynamic> toMap() {
    final notifications = <String, dynamic>{};

    if (since != null) notifications['since'] = since;
    if (before != null) notifications['before'] = before;
    if (limit != null) notifications['limit'] = limit;

    return {
      'topic': topic,
      'get': {'notifications': notifications}
    };
  }
}
class GetMomentsPacketData extends PacketData {
  String topic;
  String? channelTopic;
  String? user;
  int? since;
  int? before;
  int? limit;

  GetMomentsPacketData({
    required this.topic,
    this.channelTopic,
    this.user,
    this.since,
    this.before,
    this.limit,
  });

  @override
  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{};

    if (user != null) data['user'] = user;
    if (since != null) data['since'] = since;
    if (before != null) data['before'] = before;
    if (limit != null) data['limit'] = limit;
    if (channelTopic != null) data['topic'] = channelTopic;

    return {
      'topic': topic,
      'get': {'data': data}
    };
  }
}

class GetCommentsPacketData extends PacketData {
  String topic;
  int momId;
  int? since;
  int? before;
  int? limit;

  GetCommentsPacketData({
    required this.topic,
    required this.momId,
    this.since,
    this.before,
    this.limit,
  });

  @override
  Map<String, dynamic> toMap() {
    final comments = <String, dynamic>{
      'momId': momId,
    };

    if (since != null) comments['since'] = since;
    if (before != null) comments['before'] = before;
    if (limit != null) comments['limit'] = limit;

    return {
      'topic': topic,
      'get': {'comments': comments}
    };
  }
}

class CommentPacketData extends PacketData {
  String topic;
  int momId;
  String content;
  int? topId;
  int? parentId;
  List<String>? attachments;

  CommentPacketData({
    required this.topic,
    required this.momId,
    required this.content,
    this.topId,
    this.parentId,
    this.attachments,
  });

  @override
  Map<String, dynamic> toMap() {
    final comment = <String, dynamic>{
      'momId': momId,
      'content': content,
    };

    if (topId != null) comment['topId'] = topId;
    if (parentId != null) comment['parentId'] = parentId;
    if (attachments != null && attachments!.isNotEmpty) {
      comment['attachments'] = attachments;
    }

    return {
      'topic': topic,
      'set': {'comment': comment}
    };
  }
}

class DeleteCommentPacketData extends PacketData {
  String topic;
  int momId;
  int commentId;

  DeleteCommentPacketData({
    required this.topic,
    required this.momId,
    required this.commentId,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'del': {
        'what': 'comment',
        'id': commentId,
        'momId': momId,
      }
    };
  }
}

class LikeMomentPacketData extends PacketData {
  String topic;
  int momId;
  int action;

  LikeMomentPacketData({
    required this.topic,
    required this.momId,
    required this.action,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'set': {
        'like': {
          'momId': momId,
          'action': action,
        }
      }
    };
  }
}

class DeleteMomentPacketData extends PacketData {
  String topic;
  int momId;

  DeleteMomentPacketData({
    required this.topic,
    required this.momId,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'topic': topic,
      'del': {
        'what': 'moment',
        'id': momId,
      }
    };
  }
}

