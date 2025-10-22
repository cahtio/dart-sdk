import 'package:get_it/get_it.dart';

import 'package:tinode/src/models/packet-types.dart' as packet_types;
import 'package:tinode/src/services/configuration.dart';
import 'package:tinode/src/models/packet-data.dart';
import 'package:tinode/src/services/tools.dart';
import 'package:tinode/src/models/packet.dart';

class PacketGenerator {
  late ConfigService _configService;

  PacketGenerator() {
    _configService = GetIt.I.get<ConfigService>();
  }

  Packet generate(String type, String? topicName) {
    PacketData packetData;
    switch (type) {
      case packet_types.Hi:
        packetData = HiPacketData(
          ver: _configService.appVersion,
          ua: _configService.userAgent,
          dev: _configService.deviceToken,
          lang: _configService.humanLanguage,
          platf: _configService.platform.toLowerCase(),
        );
        break;

      case packet_types.Acc:
        packetData = AccPacketData(
          user: null,
          scheme: null,
          secret: null,
          login: false,
          tags: null,
          desc: null,
          cred: null,
          token: null,
        );
        break;

      case packet_types.Login:
        packetData = LoginPacketData(
          scheme: null,
          secret: null,
          cred: null,
        );
        break;

      case packet_types.Sub:
        packetData = SubPacketData(
          topic: topicName,
          set: null,
          get: null,
        );
        break;

      case packet_types.Leave:
        packetData = LeavePacketData(
          topic: topicName,
          unsub: false,
        );
        break;

      case packet_types.Pub:
        packetData = PubPacketData(
          topic: topicName,
          noecho: false,
          content: null,
          head: null,
          from: null,
          seq: null,
          ts: null,
        );
        break;

      case packet_types.Get:
        packetData = GetPacketData(
          topic: topicName,
          what: null,
          desc: null,
          sub: null,
          data: null,
        );
        break;

      case packet_types.Set:
        packetData = SetPacketData(
          topic: topicName,
          desc: null,
          sub: null,
          tags: null,
        );
        break;

      case packet_types.Del:
        packetData = DelPacketData(
          topic: topicName,
          what: null,
          delseq: null,
          hard: false,
          user: null,
          cred: null,
        );
        break;

      case packet_types.Note:
        packetData = NotePacketData(
          topic: topicName,
          seq: null,
          what: null,
        );
        break;
      case packet_types.Moment:
        packetData = MomentPacketData(topic: topicName ?? '', content: '');
        break;
      case packet_types.GetMoment:
        packetData = GetMomentsPacketData(topic: topicName ?? '');
        break;
      case packet_types.GetComments:
        packetData = GetCommentsPacketData(topic: topicName ?? '', momId: 0);
        break;
      case packet_types.Comment:
        packetData = CommentPacketData(
          topic: topicName ?? '',
          momId: 0,
          content: '',
        );
        break;
      case packet_types.DeleteComment:
        packetData = DeleteCommentPacketData(
          topic: topicName ?? '',
          momId: 0,
          commentId: 0,
        );
        break;
      case packet_types.LikeMoment:
        packetData = LikeMomentPacketData(
          topic: topicName ?? '',
          momId: 0,
          action: 1,
        );
        break;
      case packet_types.DeleteMoment:
        packetData = DeleteMomentPacketData(
          topic: topicName ?? '',
          momId: 0,
        );
        break;
      default:
        packetData = null as dynamic;
    }

    final packet = Packet(type, packetData);
    if (type != packet_types.Note) {
      packet.id = Tools.getNextUniqueId();
    }
    return packet;
  }
}
