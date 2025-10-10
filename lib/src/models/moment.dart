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

class Moment {
  final int id;
  final DateTime createdAt;

  Moment({required this.id, required this.createdAt});
}
