import 'package:get_it/get_it.dart';
import 'package:tinode/src/models/packet.dart';
import 'package:tinode/src/services/packet-generator.dart';
import 'package:tinode/tinode.dart';
import 'packet-types.dart' as packet_types;

class SetMoment {
  String topic;
  String content;
  int? momId;
  bool? privacy;
  List<String>? attachments;

  late PacketGenerator _packetGenerator;

  SetMoment(
      {required this.topic,
      required this.content,
      this.momId,
      this.privacy,
      this.attachments}) {
    _packetGenerator = GetIt.I.get<PacketGenerator>();
  }

  Packet asMomentPacket() {
    var packet = _packetGenerator.generate(packet_types.Moment, topic);
    var data = packet.data as MomentPacketData;
    data.content = content;
    if (privacy != null) data.privacy = privacy! ? 1 : 0;
    data.momId = momId;
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

class Moment {
  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String userId;
  final String content;
  final int privacy;
  final bool isOwner;
  final int? likeCount;
  final int? shareCount;
  final int? viewCount;
  final bool? isShared;
  final int? commentCount;
  final int? shareFromId;
  final Moment? shareFromMoment;
  final OwnerUser? ownerUser;
  final List<String>? attachments;

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
    this.commentCount,
    this.shareFromId,
    this.shareFromMoment,
    this.ownerUser,
    this.attachments,
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
      commentCount: msg['commentCount'],
      shareFromId: msg['shareFromId'],
      shareFromMoment: msg['shareFromMoment'] != null
          ? Moment.fromMessage(msg['shareFromMoment'])
          : null,
      ownerUser: msg['ownerUser'] != null
          ? OwnerUser.fromMessage(msg['ownerUser'])
          : null,
      attachments: (msg['attachments'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
