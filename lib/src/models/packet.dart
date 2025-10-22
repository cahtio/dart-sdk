import 'package:tinode/src/models/packet-data.dart';

class Packet {
  String? id;
  String? name;
  PacketData? data;
  Map<String, dynamic>? extra;

  bool? failed;
  bool? sending;
  bool? cancelled;
  bool? noForwarding;

  Packet(String name, PacketData data, [String? id = null]) {
    this.name = name;
    this.data = data;
    this.id = id;

    failed = false;
    sending = false;
  }

  Map<String, dynamic> toMap() {
    return data?.toMap() ?? {};
  }
}
