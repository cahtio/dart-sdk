import 'package:get_it/get_it.dart';
import 'package:tinode/src/models/packet.dart';
import 'package:tinode/src/services/packet-generator.dart';
import 'package:tinode/tinode.dart';
import 'packet-types.dart' as packet_types;

class SetMoment {
  String topic;
  dynamic content;
  int? momId;
  bool? privacy;
  List<Map<String, dynamic>>? data;
  List<String>? attachments; // 附件用户后端持久化

  late PacketGenerator _packetGenerator;

  SetMoment(
      {required this.topic,
      required this.content,
      this.momId,
      this.privacy,
      this.data}) {
    _packetGenerator = GetIt.I.get<PacketGenerator>();
  }

  Packet asMomentPacket() {
    var packet = _packetGenerator.generate(packet_types.GetMoment, topic);
    var packetData = packet.data as MomentPacketData;
    packetData.content = content;
    if (privacy != null) packetData.privacy = privacy! ? 1 : 0;
    packetData.momId = momId;
    packetData.attachments = attachments;
    packetData.data = data;
    return packet;
  }
}

class SetComment {
  String topic;
  int momId;
  String content;
  int? topId;
  int? parentId;
  List<String>? attachments;

  late PacketGenerator _packetGenerator;

  SetComment({
    required this.topic,
    required this.momId,
    required this.content,
    this.topId,
    this.parentId,
    this.attachments,
  }) {
    _packetGenerator = GetIt.I.get<PacketGenerator>();
  }

  Packet asCommentPacket() {
    var packet = _packetGenerator.generate(packet_types.Comment, topic);
    var data = packet.data as CommentPacketData;
    data.momId = momId;
    data.content = content;
    data.topId = topId;
    data.parentId = parentId;
    data.attachments = attachments;
    return packet;
  }
}

class PhotoData {
  final String data;
  final String type;

  PhotoData({required this.data, required this.type});

  factory PhotoData.fromMessage(Map<String, dynamic> msg) {
    return PhotoData(
      data: msg['data'] ?? '',
      type: msg['type'] ?? '',
    );
  }
}

class PublicData {
  final String fn;
  final PhotoData? photo;

  PublicData({required this.fn, this.photo});

  factory PublicData.fromMessage(Map<String, dynamic> msg) {
    return PublicData(
      fn: msg['fn'] ?? '',
      photo: msg['photo'] != null ? PhotoData.fromMessage(msg['photo']) : null,
    );
  }
}

class OwnerUser {
  final String id;
  final PublicData public;

  OwnerUser({required this.id, required this.public});

  factory OwnerUser.fromMessage(Map<String, dynamic> msg) {
    return OwnerUser(
      id: msg['id'] ?? '',
      public: PublicData.fromMessage(msg['public'] ?? {}),
    );
  }
}

class MomentComment {
  final int id;
  final int momentId;
  String userId;
  DateTime createdAt;
  String content;
  final OwnerUser? user;

  MomentComment({
    required this.id,
    required this.momentId,
    required this.userId,
    required this.createdAt,
    required this.content,
    this.user,
  });

  factory MomentComment.fromMessage(Map<String, dynamic> msg) {
    return MomentComment(
      id: msg['id'],
      momentId: msg['momentId'],
      userId: msg['userId'] ?? '',
      createdAt: msg['createdAt'] != null
          ? DateTime.parse(msg['createdAt'])
          : DateTime.now(),
      content: msg['content'] ?? '',
      user: msg['user'] != null ? OwnerUser.fromMessage(msg['user']) : null,
    );
  }
}

class Moment {
  final int id;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String userId;
  dynamic content;
  final int privacy;
  final bool isOwner;
  int? likeCount;
  final int? shareCount;
  final int? viewCount;
  final bool? isShared;
  bool? isLiked;
  int? commentCount;
  final int? shareFromId;
  final Moment? shareFromMoment;
  final OwnerUser? ownerUser;
  List<Map<String, dynamic>>? data;

  Moment({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.content,
    required this.privacy,
    required this.isOwner,
    this.likeCount,
    this.shareCount,
    this.viewCount,
    this.isShared,
    this.isLiked,
    this.commentCount,
    this.shareFromId,
    this.shareFromMoment,
    this.ownerUser,
    this.data,
  });

  factory Moment.fromMessage(Map<String, dynamic> msg) {
    return Moment(
      id: msg['id'],
      createdAt: msg['createdAt'] != null
          ? DateTime.parse(msg['createdAt'])
          : DateTime.now(),
      updatedAt: msg['updatedAt'] != null
          ? DateTime.parse(msg['updatedAt'])
          : DateTime.now(),
      userId: msg['userId'] ?? '',
      content: msg['content'] ?? '',
      privacy: msg['privacy'] ?? 0,
      isOwner: msg['isOwner'] ?? false,
      likeCount: msg['likeCount'],
      shareCount: msg['shareCount'],
      viewCount: msg['viewCount'],
      isShared: msg['isShared'],
      isLiked: msg['isLiked'],
      commentCount: msg['commentCount'],
      shareFromId: msg['shareFromId'],
      shareFromMoment: msg['shareFromMoment'] != null
          ? Moment.fromMessage(msg['shareFromMoment'])
          : null,
      ownerUser: msg['ownerUser'] != null
          ? OwnerUser.fromMessage(msg['ownerUser'])
          : null,
      data: msg['data'] != null
          ? (msg['data'] as List<dynamic>).cast<Map<String, dynamic>>()
          : null,
    );
  }
}

class MomentNotification {
  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String userId;
  final String type;
  final String title;
  final String content;
  final Moment? data; // 使用现有的 Moment 类
  final String fromUserId;
  final PublicData fromUserPublic;
  final String sourceId;
  final String targetId;
  final String relatedId;
  final String relatedType;
  final int status;

  MomentNotification({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.type,
    required this.title,
    required this.content,
    this.data,
    required this.fromUserId,
    required this.fromUserPublic,
    required this.sourceId,
    required this.targetId,
    required this.relatedId,
    required this.relatedType,
    required this.status,
  });

  factory MomentNotification.fromMessage(Map<String, dynamic> msg) {
    return MomentNotification(
      id: msg['id'],
      createdAt: msg['createdAt'] != null
          ? DateTime.parse(msg['createdAt'])
          : DateTime.now(),
      updatedAt: msg['updatedAt'] != null
          ? DateTime.parse(msg['updatedAt'])
          : DateTime.now(),
      userId: msg['userId'] ?? '',
      type: msg['type'] ?? '',
      title: msg['title'] ?? '',
      content: msg['content'] ?? '',
      data: msg['data'] != null ? Moment.fromMessage(msg['data']) : null,
      fromUserId: msg['fromUserId'] ?? '',
      fromUserPublic: PublicData.fromMessage(msg['fromUserPublic'] ?? {}),
      sourceId: msg['sourceId'] ?? '',
      targetId: msg['targetId'] ?? '',
      relatedId: msg['relatedId'] ?? '',
      relatedType: msg['relatedType'] ?? '',
      status: msg['status'] ?? 0,
    );
  }
}
